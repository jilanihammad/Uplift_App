/// Unit tests for MessageCoordinator
/// 
/// These tests verify message management, sequencing, and conversation history
/// functionality of MessageCoordinator.

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/blocs/managers/message_coordinator.dart';
import 'package:ai_therapist_app/models/therapy_message.dart';
import 'package:ai_therapist_app/widgets/mood_selector.dart';

void main() {
  group('MessageCoordinator', () {
    late MessageCoordinator coordinator;

    setUp(() {
      coordinator = MessageCoordinator();
    });

    group('Initialization', () {
      test('initializes with empty state', () {
        expect(coordinator.messages, isEmpty);
        expect(coordinator.currentSequence, 0);
        expect(coordinator.messageCount, 0);
        expect(coordinator.hasMessages, false);
      });

      test('resetMessages clears all data', () {
        // Add some messages
        coordinator.addUserMessage('Test message 1');
        coordinator.addAIMessage('Test response');
        
        expect(coordinator.messageCount, 2);
        expect(coordinator.currentSequence, 2);
        
        // Reset
        coordinator.resetMessages();
        
        expect(coordinator.messages, isEmpty);
        expect(coordinator.currentSequence, 0);
        expect(coordinator.hasMessages, false);
      });
    });

    group('Message Addition', () {
      test('addUserMessage creates proper user message', () {
        final message = coordinator.addUserMessage('Hello, Maya!');
        
        expect(message.content, 'Hello, Maya!');
        expect(message.isUser, true);
        expect(message.sequence, 1);
        expect(message.id, isNotEmpty);
        expect(message.timestamp, isA<DateTime>());
        
        expect(coordinator.messageCount, 1);
        expect(coordinator.currentSequence, 1);
        expect(coordinator.messages.first, equals(message));
      });

      test('addAIMessage creates proper AI message', () {
        final message = coordinator.addAIMessage('Hello! How can I help you today?');
        
        expect(message.content, 'Hello! How can I help you today?');
        expect(message.isUser, false);
        expect(message.sequence, 1);
        expect(message.id, isNotEmpty);
        
        expect(coordinator.messageCount, 1);
        expect(coordinator.currentSequence, 1);
      });

      test('messages maintain sequence order', () {
        coordinator.addUserMessage('First');
        coordinator.addAIMessage('Second');
        coordinator.addUserMessage('Third');
        coordinator.addAIMessage('Fourth');
        
        expect(coordinator.messages[0].sequence, 1);
        expect(coordinator.messages[1].sequence, 2);
        expect(coordinator.messages[2].sequence, 3);
        expect(coordinator.messages[3].sequence, 4);
        expect(coordinator.currentSequence, 4);
      });

      test('addMessage with zero sequence auto-increments', () {
        final inputMessage = TherapyMessage(
          id: 'test-id',
          content: 'Test message',
          isUser: true,
          timestamp: DateTime.now(),
          sequence: 0,
        );
        
        final result = coordinator.addMessage(inputMessage);
        
        expect(result.sequence, 1);
        expect(coordinator.currentSequence, 1);
      });

      test('addMessage with higher sequence updates current', () {
        coordinator.addUserMessage('First'); // sequence 1
        
        final inputMessage = TherapyMessage(
          id: 'test-id',
          content: 'Jump ahead',
          isUser: false,
          timestamp: DateTime.now(),
          sequence: 5,
        );
        
        coordinator.addMessage(inputMessage);
        
        expect(coordinator.currentSequence, 5);
        expect(coordinator.messages.last.sequence, 5);
      });
    });

    group('Welcome Message Generation', () {
      test('addWelcomeMessage creates AI message with mood-specific content', () {
        final message = coordinator.addWelcomeMessage(Mood.happy);
        
        expect(message.isUser, false);
        expect(message.sequence, 1);
        expect(message.content, isNotEmpty);
        
        // Should contain happy mood keywords
        expect(
          message.content.toLowerCase(),
          anyOf(
            contains('spirits'),
            contains('positivity'),
            contains('upbeat'),
            contains('happy'),
            contains('brightening'),
          ),
        );
      });

      test('generateWelcomeMessage returns appropriate messages for each mood', () {
        // Test each mood
        for (final mood in Mood.values) {
          final message = coordinator.generateWelcomeMessage(mood);
          expect(message, isNotEmpty);
          expect(message.length, greaterThan(10)); // Reasonable message length
        }
      });

      test('welcome messages vary (not always the same)', () {
        // Generate multiple messages and check for variety
        final messages = <String>{};
        
        // Generate 20 messages - should get some variety
        for (int i = 0; i < 20; i++) {
          messages.add(coordinator.generateWelcomeMessage(Mood.neutral));
        }
        
        // Should have gotten at least 2 different messages
        expect(messages.length, greaterThan(1));
      });
    });

    group('Conversation History', () {
      test('buildConversationHistory creates correct format', () {
        coordinator.addUserMessage('Hello');
        coordinator.addAIMessage('Hi there!');
        coordinator.addUserMessage('How are you?');
        coordinator.addAIMessage('I\'m doing well, thank you!');
        
        final history = coordinator.buildConversationHistory();
        
        expect(history, hasLength(4));
        
        expect(history[0], {
          'role': 'user',
          'content': 'Hello',
        });
        
        expect(history[1], {
          'role': 'assistant',
          'content': 'Hi there!',
        });
        
        expect(history[2], {
          'role': 'user',
          'content': 'How are you?',
        });
        
        expect(history[3], {
          'role': 'assistant',
          'content': 'I\'m doing well, thank you!',
        });
      });

      test('empty conversation returns empty history', () {
        final history = coordinator.buildConversationHistory();
        expect(history, isEmpty);
      });
    });

    group('Message Queries', () {
      setUp(() {
        // Add test messages with small delays to ensure different timestamps
        coordinator.addUserMessage('User 1');
        coordinator.addAIMessage('AI 1');
        coordinator.addUserMessage('User 2');
        coordinator.addAIMessage('AI 2');
        coordinator.addUserMessage('User 3');
      });

      test('getLastMessages returns correct messages', () {
        final last2 = coordinator.getLastMessages(2);
        expect(last2, hasLength(2));
        expect(last2[0].content, 'AI 2');
        expect(last2[1].content, 'User 3');
        
        final last10 = coordinator.getLastMessages(10);
        expect(last10, hasLength(5)); // Only 5 messages total
      });

      test('getUserMessages filters correctly', () {
        final userMessages = coordinator.getUserMessages();
        
        expect(userMessages, hasLength(3));
        expect(userMessages.every((m) => m.isUser), true);
        expect(userMessages.map((m) => m.content), ['User 1', 'User 2', 'User 3']);
      });

      test('getAIMessages filters correctly', () {
        final aiMessages = coordinator.getAIMessages();
        
        expect(aiMessages, hasLength(2));
        expect(aiMessages.every((m) => !m.isUser), true);
        expect(aiMessages.map((m) => m.content), ['AI 1', 'AI 2']);
      });

      test('findMessageById returns correct message', () {
        final messages = coordinator.messages;
        final targetId = messages[2].id; // User 2
        
        final found = coordinator.findMessageById(targetId);
        expect(found, isNotNull);
        expect(found!.content, 'User 2');
      });

      test('findMessageById returns null for non-existent ID', () {
        final found = coordinator.findMessageById('non-existent-id');
        expect(found, isNull);
      });
    });

    group('Message Management', () {
      test('removeMessage removes correct message', () {
        coordinator.addUserMessage('Keep 1');
        final toRemove = coordinator.addAIMessage('Remove this');
        coordinator.addUserMessage('Keep 2');
        
        expect(coordinator.messageCount, 3);
        
        final removed = coordinator.removeMessage(toRemove.id);
        
        expect(removed, true);
        expect(coordinator.messageCount, 2);
        expect(coordinator.messages.map((m) => m.content), ['Keep 1', 'Keep 2']);
      });

      test('removeMessage returns false for non-existent ID', () {
        coordinator.addUserMessage('Test');
        
        final removed = coordinator.removeMessage('non-existent-id');
        
        expect(removed, false);
        expect(coordinator.messageCount, 1);
      });

      test('updateMessages replaces entire message list', () {
        // Add initial messages
        coordinator.addUserMessage('Old 1');
        coordinator.addAIMessage('Old 2');
        
        // Create new messages
        final newMessages = [
          TherapyMessage(
            id: 'new-1',
            content: 'New 1',
            isUser: true,
            timestamp: DateTime.now(),
            sequence: 10,
          ),
          TherapyMessage(
            id: 'new-2',
            content: 'New 2',
            isUser: false,
            timestamp: DateTime.now(),
            sequence: 11,
          ),
        ];
        
        coordinator.updateMessages(newMessages, 11);
        
        expect(coordinator.messageCount, 2);
        expect(coordinator.currentSequence, 11);
        expect(coordinator.messages.map((m) => m.content), ['New 1', 'New 2']);
      });
    });

    group('Conversation Summary', () {
      test('getConversationSummary with messages', () {
        final startTime = DateTime.now();
        
        coordinator.addUserMessage('User 1');
        coordinator.addAIMessage('AI 1');
        coordinator.addUserMessage('User 2');
        
        final summary = coordinator.getConversationSummary();
        
        expect(summary['totalMessages'], 3);
        expect(summary['userMessages'], 2);
        expect(summary['aiMessages'], 1);
        expect(summary['currentSequence'], 3);
        expect(summary['hasMessages'], true);
        expect(summary['conversationDuration'], isA<int>());
        expect(summary['conversationDuration'], greaterThanOrEqualTo(0));
      });

      test('getConversationSummary with no messages', () {
        final summary = coordinator.getConversationSummary();
        
        expect(summary['totalMessages'], 0);
        expect(summary['userMessages'], 0);
        expect(summary['aiMessages'], 0);
        expect(summary['currentSequence'], 0);
        expect(summary['hasMessages'], false);
        expect(summary['conversationDuration'], 0);
      });
    });

    group('Time-based Queries', () {
      test('getMessagesInRange filters by time', () async {
        final start = DateTime.now();
        
        coordinator.addUserMessage('Message 1');
        await Future.delayed(const Duration(milliseconds: 10));
        
        coordinator.addAIMessage('Message 2');
        await Future.delayed(const Duration(milliseconds: 10));
        
        coordinator.addUserMessage('Message 3');
        
        final end = DateTime.now();
        
        // Get messages in full range
        final allInRange = coordinator.getMessagesInRange(
          start.subtract(const Duration(seconds: 1)),
          end.add(const Duration(seconds: 1)),
        );
        expect(allInRange, hasLength(3));
        
        // Get messages in restricted range
        final someInRange = coordinator.getMessagesInRange(
          start.add(const Duration(milliseconds: 5)),
          end.subtract(const Duration(milliseconds: 5)),
        );
        expect(someInRange.length, lessThan(3));
      });
    });

    group('Edge Cases', () {
      test('messages list is immutable from getter', () {
        coordinator.addUserMessage('Test');
        
        final messages = coordinator.messages;
        
        // This should throw because the list is unmodifiable
        expect(() => messages.add(TherapyMessage(
          id: 'bad',
          content: 'Should not add',
          isUser: true,
          timestamp: DateTime.now(),
          sequence: 99,
        )), throwsUnsupportedError);
      });

      test('handles very long message content', () {
        final longContent = 'A' * 1000;
        final message = coordinator.addUserMessage(longContent);
        
        expect(message.content, longContent);
        expect(message.content.length, 1000);
      });
    });
  });
}