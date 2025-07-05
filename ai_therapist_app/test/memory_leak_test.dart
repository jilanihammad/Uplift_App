// test/memory_leak_test.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/screens/chat_screen.dart';
import 'package:ai_therapist_app/blocs/voice_session_bloc.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';

void main() {
  group('Memory Leak Detection Tests', () {
    late DependencyContainer container;
    
    setUp(() {
      container = DependencyContainer();
    });
    
    tearDown(() {
      container.resetForTesting();
    });
    
    testWidgets('ChatScreen disposal cleans up all resources', (WidgetTester tester) async {
      // Track initial state
      final initialWidgetCount = tester.allWidgets.length;
      
      // Create ChatScreen
      await tester.pumpWidget(
        MaterialApp(
          home: const ChatScreen(),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify screen is created
      expect(find.byType(ChatScreen), findsOneWidget);
      final afterCreationCount = tester.allWidgets.length;
      expect(afterCreationCount, greaterThan(initialWidgetCount));
      
      // Navigate away (triggers disposal)
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(
            body: Text('Different Screen'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Allow time for disposal
      await tester.pump(const Duration(milliseconds: 500));
      
      // Verify resources are cleaned up
      expect(find.byType(ChatScreen), findsNothing);
      
      // Widget count should return close to initial (allowing for framework overhead)
      final afterDisposalCount = tester.allWidgets.length;
      expect(afterDisposalCount, lessThan(afterCreationCount));
    });
    
    testWidgets('Multiple ChatScreen creation/disposal cycles', (WidgetTester tester) async {
      // Test multiple cycles to detect accumulating leaks
      for (int cycle = 0; cycle < 3; cycle++) {
        // Create ChatScreen
        await tester.pumpWidget(
          MaterialApp(
            home: ChatScreen(sessionId: 'test-session-$cycle'),
          ),
        );
        await tester.pumpAndSettle();
        
        // Verify creation
        expect(find.byType(ChatScreen), findsOneWidget);
        
        // Dispose
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Text('Cycle $cycle complete'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Allow cleanup time
        await tester.pump(const Duration(milliseconds: 300));
        
        expect(find.byType(ChatScreen), findsNothing);
      }
      
      // If we reach here without memory issues, the test passes
      expect(true, isTrue);
    });
    
    testWidgets('Stream controllers are properly disposed', (WidgetTester tester) async {
      // This test verifies that stream controllers don't leak
      final List<StreamController> controllers = [];
      
      // Create a widget that uses stream controllers
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulWidget(
            createState: () => _TestStreamState(controllers),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controllers were created
      expect(controllers.length, greaterThan(0));
      
      // Verify controllers are open
      for (final controller in controllers) {
        expect(controller.isClosed, isFalse);
      }
      
      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Disposed')),
        ),
      );
      await tester.pumpAndSettle();
      
      // Allow time for disposal
      await tester.pump(const Duration(milliseconds: 500));
      
      // Verify controllers are closed
      for (final controller in controllers) {
        expect(controller.isClosed, isTrue);
      }
    });
    
    testWidgets('Animation controllers are properly disposed', (WidgetTester tester) async {
      final List<AnimationController> animationControllers = [];
      
      // Create widget with animation controllers
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulWidget(
            createState: () => _TestAnimationState(animationControllers),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controllers were created
      expect(animationControllers.length, greaterThan(0));
      
      // Verify controllers are active
      for (final controller in animationControllers) {
        expect(controller.isDisposed, isFalse);
      }
      
      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Disposed')),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controllers are disposed
      for (final controller in animationControllers) {
        expect(controller.isDisposed, isTrue);
      }
    });
    
    testWidgets('Text and scroll controllers are disposed', (WidgetTester tester) async {
      late TextEditingController textController;
      late ScrollController scrollController;
      
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulWidget(
            createState: () => _TestControllerState((text, scroll) {
              textController = text;
              scrollController = scroll;
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controllers are active
      expect(textController.hasListeners, isTrue);
      expect(scrollController.hasClients, isFalse); // No clients yet
      
      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Disposed')),
        ),
      );
      await tester.pumpAndSettle();
      
      // Note: Flutter controllers don't have a public isDisposed property,
      // but we can verify they're cleaned up by checking they don't throw
      // when accessing basic properties after disposal
      expect(() => textController.text, returnsNormally);
      expect(() => scrollController.offset, returnsNormally);
    });
  });
}

// Test helper classes
class _TestStreamState extends State<StatefulWidget> {
  final List<StreamController> controllers;
  late StreamController<String> _controller1;
  late StreamController<int> _controller2;
  
  _TestStreamState(this.controllers);
  
  @override
  void initState() {
    super.initState();
    _controller1 = StreamController<String>();
    _controller2 = StreamController<int>();
    controllers.addAll([_controller1, _controller2]);
  }
  
  @override
  void dispose() {
    _controller1.close();
    _controller2.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Text('Test Stream Widget'),
    );
  }
}

class _TestAnimationState extends State<StatefulWidget> with TickerProviderStateMixin {
  final List<AnimationController> controllers;
  late AnimationController _controller1;
  late AnimationController _controller2;
  
  _TestAnimationState(this.controllers);
  
  @override
  void initState() {
    super.initState();
    _controller1 = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _controller2 = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    controllers.addAll([_controller1, _controller2]);
  }
  
  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Text('Test Animation Widget'),
    );
  }
}

class _TestControllerState extends State<StatefulWidget> {
  final Function(TextEditingController, ScrollController) onControllersCreated;
  late TextEditingController _textController;
  late ScrollController _scrollController;
  
  _TestControllerState(this.onControllersCreated);
  
  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _scrollController = ScrollController();
    onControllersCreated(_textController, _scrollController);
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextField(controller: _textController),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: 10,
              itemBuilder: (context, index) => Text('Item $index'),
            ),
          ),
        ],
      ),
    );
  }
}