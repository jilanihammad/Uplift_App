import 'dart:async';
import 'dart:convert';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:ai_therapist_app/services/groq_service.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/models/therapy_message.dart';
import 'package:flutter/foundation.dart';

// EVENTS
abstract class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

// Use StartChat only for session/sessionId initialization or initial AI welcome
class StartChat extends ChatEvent {
  final String? initialMessage;
  final List<Map<String, dynamic>> history;
  final String sessionId;
  const StartChat(
      {this.initialMessage, required this.history, required this.sessionId});
  @override
  List<Object?> get props => [initialMessage, history, sessionId];
}

// New event for user messages
class SendUserMessage extends ChatEvent {
  final String message;
  final List<Map<String, dynamic>> history;
  final String sessionId;
  const SendUserMessage(
      {required this.message, required this.history, required this.sessionId});
  @override
  List<Object?> get props => [message, history, sessionId];
}

// New event for streaming AI response chunks
class NewMessageChunkReceived extends ChatEvent {
  final String content;
  final bool isDone;
  final String? error;
  const NewMessageChunkReceived(
      {required this.content, this.isDone = false, this.error});
  @override
  List<Object?> get props => [content, isDone, error];
}

class ChatCompleted extends ChatEvent {}

class ChatError extends ChatEvent {
  final String error;
  const ChatError(this.error);
  @override
  List<Object?> get props => [error];
}

// STATES
abstract class ChatState extends Equatable {
  const ChatState();
  @override
  List<Object?> get props => [];
}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
  final List<TherapyMessage> messages;
  const ChatLoaded(this.messages);
  @override
  List<Object?> get props => [messages];
}

class ChatCompletedState extends ChatState {
  final List<TherapyMessage> messages;
  const ChatCompletedState(this.messages);
  @override
  List<Object?> get props => [messages];
}

class ChatErrorState extends ChatState {
  final String error;
  final List<TherapyMessage> messages;
  const ChatErrorState(this.error, this.messages);
  @override
  List<Object?> get props => [error, messages];
}

// BLoC IMPLEMENTATION
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  StreamSubscription? _subscription;
  final GroqService _groqService;
  StringBuffer? _aiResponseBuffer; // Buffer for streaming AI response
  List<TherapyMessage> _currentMessages = [];

  ChatBloc({GroqService? groqService})
      : _groqService = groqService ?? serviceLocator<GroqService>(),
        super(ChatInitial()) {
    print('[ChatBloc] CREATED!');
    on<StartChat>(_onStartChat);
    on<SendUserMessage>(_onSendUserMessage);
    on<ChatCompleted>(_onChatCompleted);
    on<ChatError>(_onChatError);
    on<NewMessageChunkReceived>(_onNewMessageChunkReceived);
  }

  // StartChat: only for session/sessionId initialization or initial AI welcome
  Future<void> _onStartChat(StartChat event, Emitter<ChatState> emit) async {
    debugPrint(
        '[ChatBloc] _onStartChat called with history: [36m${event.history.length}[0m, sessionId: [36m${event.sessionId}[0m');
    emit(ChatLoading());
    debugPrint('[ChatBloc] Emitted ChatLoading (StartChat)');
    await _subscription?.cancel();
    _currentMessages = [];
    if (state is ChatLoaded) {
      _currentMessages =
          List<TherapyMessage>.from((state as ChatLoaded).messages);
    }
    if (event.initialMessage != null && event.initialMessage!.isNotEmpty) {
      final aiMsg = TherapyMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        content: event.initialMessage!,
        isUser: false, // Initial message is always from AI
        timestamp: DateTime.now(),
        audioUrl: null,
      );
      debugPrint(
          '[ChatBloc][DEBUG] Creating initial AI message: isUser=false, content="${aiMsg.content}"');
      _currentMessages.add(aiMsg);
      debugPrint('[ChatBloc] Added initial AI message: ${aiMsg.content}');
    }
    emit(ChatLoaded(List<TherapyMessage>.from(_currentMessages)));
    debugPrint(
        '[ChatBloc] Emitted ChatLoaded (StartChat) with ${_currentMessages.length} messages');
    for (var m in _currentMessages) {
      debugPrint(
          '[ChatBloc]   - [${m.isUser ? 'user' : 'assistant'}] ${m.content}');
    }
  }

  // SendUserMessage: for each user message
  Future<void> _onSendUserMessage(
      SendUserMessage event, Emitter<ChatState> emit) async {
    debugPrint(
        '[ChatBloc] _onSendUserMessage called with message: \x1B[32m${event.message}\x1B[0m');
    emit(ChatLoading());
    debugPrint('[ChatBloc] Emitted ChatLoading (SendUserMessage)');
    await _subscription?.cancel();
    if (state is ChatLoaded) {
      _currentMessages =
          List<TherapyMessage>.from((state as ChatLoaded).messages);
    } else if (state is ChatCompletedState) {
      _currentMessages =
          List<TherapyMessage>.from((state as ChatCompletedState).messages);
    } else if (state is ChatErrorState) {
      _currentMessages =
          List<TherapyMessage>.from((state as ChatErrorState).messages);
    }
    final userMsg = TherapyMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      content: event.message,
      isUser: true, // User message is always isUser=true
      timestamp: DateTime.now(),
      audioUrl: null,
    );
    debugPrint(
        '[ChatBloc][DEBUG] Creating user message: isUser=true, content="${userMsg.content}"');
    _currentMessages.add(userMsg);
    debugPrint(
        '[ChatBloc] Added user message to buffer. Buffer now has ${_currentMessages.length} messages:');
    for (var m in _currentMessages) {
      debugPrint(
          '[ChatBloc]   - [${m.isUser ? 'user' : 'assistant'}] ${m.content}');
    }
    _aiResponseBuffer = StringBuffer();
    debugPrint(
        '[ChatBloc] [STREAM] Subscribing to GroqService WebSocket stream...');
    _subscription = _groqService
        .streamChatCompletionViaWebSocket(
      message: event.message,
      history: event.history,
      sessionId: event.sessionId,
    )
        .listen((data) async {
      if (data['type'] == 'chunk') {
        final content = data['content']?.toString() ?? '';
        add(NewMessageChunkReceived(content: content));
      } else if (data['type'] == 'done') {
        add(NewMessageChunkReceived(content: '', isDone: true));
      } else if (data['type'] == 'error') {
        add(NewMessageChunkReceived(
            content: '', error: data['detail']?.toString() ?? 'Unknown error'));
      }
    }, onError: (error) {
      debugPrint('[ChatBloc] [STREAM] onError from GroqService: $error');
      add(NewMessageChunkReceived(content: '', error: error.toString()));
    });
  }

  void _onNewMessageChunkReceived(
      NewMessageChunkReceived event, Emitter<ChatState> emit) {
    if (event.error != null) {
      debugPrint('[ChatBloc] [CHUNK] Error received: ${event.error}');
      emit(ChatErrorState(
          event.error!, List<TherapyMessage>.from(_currentMessages)));
      return;
    }
    if (!event.isDone) {
      // Accumulate chunk
      _aiResponseBuffer ??= StringBuffer();
      _aiResponseBuffer!.write(event.content);
      debugPrint('[ChatBloc] [CHUNK] Appended chunk: "${event.content}"');
      debugPrint('[ChatBloc] [CHUNK] Buffer so far: "${_aiResponseBuffer}"');
      // Optionally, emit partial state for streaming UI (not required)
      // emit(ChatLoading());
    } else {
      // Done event: finalize AI message
      final fullContent = _aiResponseBuffer?.toString() ?? '';
      debugPrint(
          '[ChatBloc] [CHUNK] AI reply complete (done event): "$fullContent"');
      if (fullContent.isNotEmpty) {
        final aiMsg = TherapyMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          content: fullContent,
          isUser: false, // AI message is always isUser=false
          timestamp: DateTime.now(),
          audioUrl: null,
        );
        debugPrint(
            '[ChatBloc][DEBUG] Creating AI message: isUser=false, content="${aiMsg.content}"');
        _currentMessages.add(aiMsg);
        debugPrint(
            '[ChatBloc] [CHUNK] Added AI reply to buffer. Buffer now has ${_currentMessages.length} messages:');
        for (var m in _currentMessages) {
          debugPrint(
              '[ChatBloc] [CHUNK]   - [${m.isUser ? 'user' : 'assistant'}] ${m.content}');
        }
        emit(ChatLoaded(List<TherapyMessage>.from(_currentMessages)));
        debugPrint(
            '[ChatBloc] [CHUNK] Emitted ChatLoaded (AI reply) with ${_currentMessages.length} messages');
      } else {
        debugPrint(
            '[ChatBloc] [CHUNK] fullContent is empty at done event, not emitting ChatLoaded.');
      }
      _aiResponseBuffer = null;
      add(ChatCompleted());
    }
  }

  Future<void> _onChatCompleted(
      ChatCompleted event, Emitter<ChatState> emit) async {
    debugPrint('[ChatBloc] _onChatCompleted called');
    emit(ChatCompletedState(List<TherapyMessage>.from(_currentMessages)));
    debugPrint(
        '[ChatBloc] Emitted ChatCompletedState with [33m${_currentMessages.length}[0m messages');
    // Immediately transition back to ChatLoaded to allow further user input
    emit(ChatLoaded(List<TherapyMessage>.from(_currentMessages)));
    debugPrint('[ChatBloc] Emitted ChatLoaded after ChatCompletedState');
  }

  Future<void> _onChatError(ChatError event, Emitter<ChatState> emit) async {
    debugPrint('[ChatBloc] _onChatError called: ${event.error}');
    emit(ChatErrorState(
        event.error, List<TherapyMessage>.from(_currentMessages)));
    debugPrint(
        '[ChatBloc] Emitted ChatErrorState with ${_currentMessages.length} messages');
  }

  @override
  Future<void> close() {
    debugPrint('[ChatBloc] close() called');
    _subscription?.cancel();
    return super.close();
  }
}
