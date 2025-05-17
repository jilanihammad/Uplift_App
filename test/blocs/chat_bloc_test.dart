import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/matchers.dart';

// Your app imports
import 'package:ai_therapist_app/blocs/chat_bloc.dart';
import 'package:ai_therapist_app/services/groq_service.dart';

// Mock definition
class MockGroqService extends Mock implements GroqService {}

void main() {
  late ChatBloc chatBloc;
  late MockGroqService mockGroqService;

  setUp(() {
    mockGroqService = MockGroqService();
    chatBloc = ChatBloc(groqService: mockGroqService);
  });

  tearDown(() async {
    await chatBloc.close();
  });

  blocTest<ChatBloc, ChatState>(
    'emits [ChatLoading, ChatLoaded, ChatCompletedState] when stream completes successfully',
    build: () {
      // Option A: stub with exact literals
      when(
        mockGroqService.streamChatCompletionViaWebSocket(
          message: 'Hi',
          history: const <Map<String, dynamic>>[],
          sessionId: '123',
        ),
      ).thenAnswer(
        (_) => Stream.fromIterable([
          {'type': 'chunk', 'content': 'Hello'},
          {'type': 'done'},
        ]),
      );

      return chatBloc;
    },
    act:
        (bloc) => bloc.add(
          StartChat(message: 'Hi', history: const [], sessionId: '123'),
        ),
    expect: () => [ChatLoading(), ChatLoaded('Hello'), ChatCompletedState()],
  );
}
