// test/stability_test.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/screens/widgets/chat_interface_view.dart';
import 'package:ai_therapist_app/screens/widgets/voice_controls_panel.dart';
import 'package:ai_therapist_app/screens/widgets/text_input_bar.dart';

void main() {
  group('Widget Stability Tests', () {
    testWidgets('Rapid widget creation and disposal', (WidgetTester tester) async {
      // Test multiple cycles of widget creation and disposal
      for (int cycle = 0; cycle < 5; cycle++) {
        // Create controllers
        final messageController = TextEditingController();
        final scrollController = ScrollController();
        
        // Create widget
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatInterfaceView(
                onSwitchMode: () {},
                onSendMessage: () {},
                messageController: messageController,
                scrollController: scrollController,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Verify widget exists
        expect(find.byType(ChatInterfaceView), findsOneWidget);
        
        // Dispose by removing widget
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Text('Cycle $cycle disposed'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        // Clean up controllers
        messageController.dispose();
        scrollController.dispose();
        
        // Allow cleanup time
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    
    testWidgets('VoiceControlsPanel rapid creation/disposal', (WidgetTester tester) async {
      // Test VoiceControlsPanel specifically since it has animations
      for (int cycle = 0; cycle < 3; cycle++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VoiceControlsPanel(
                onSwitchMode: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        expect(find.byType(VoiceControlsPanel), findsOneWidget);
        
        // Dispose
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Text('VoiceControls disposed $cycle')),
          ),
        );
        await tester.pumpAndSettle();
        
        // Allow animation controllers to dispose
        await tester.pump(const Duration(milliseconds: 200));
      }
    });
    
    testWidgets('TextInputBar rapid recreation', (WidgetTester tester) async {
      for (int cycle = 0; cycle < 5; cycle++) {
        final controller = TextEditingController();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextInputBar(
                messageController: controller,
                micButton: const Icon(Icons.mic),
                isProcessing: false,
                onSend: () {},
                onSwitchMode: () {},
                enabled: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        
        expect(find.byType(TextInputBar), findsOneWidget);
        
        // Test text input
        await tester.enterText(find.byType(TextField), 'Test message $cycle');
        expect(controller.text, equals('Test message $cycle'));
        
        // Dispose
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Text('TextInput disposed $cycle')),
          ),
        );
        await tester.pumpAndSettle();
        
        controller.dispose();
      }
    });
    
    testWidgets('Stream controller lifecycle management', (WidgetTester tester) async {
      final controllers = <StreamController<String>>[];
      
      // Create test widget with stream controllers
      await tester.pumpWidget(
        MaterialApp(
          home: _TestStreamWidget(controllers),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controllers were created
      expect(controllers.length, equals(2));
      
      // Verify streams are active
      for (final controller in controllers) {
        expect(controller.isClosed, isFalse);
      }
      
      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Streams disposed')),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controllers are closed
      for (final controller in controllers) {
        expect(controller.isClosed, isTrue);
      }
    });
    
    testWidgets('Animation controller lifecycle', (WidgetTester tester) async {
      final controllers = <AnimationController>[];
      
      await tester.pumpWidget(
        MaterialApp(
          home: _TestAnimationWidget(controllers),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controllers were created and are active
      expect(controllers.length, equals(1));
      expect(() => controllers.first.status, returnsNormally);
      
      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Animations disposed')),
        ),
      );
      await tester.pumpAndSettle();
      
      // Verify controller is disposed (accessing status should throw)
      expect(() => controllers.first.status, throwsFlutterError);
    });
    
    testWidgets('Multiple widget type stability', (WidgetTester tester) async {
      // Test creating multiple different widgets rapidly
      final widgets = [
        const Text('Widget 1'),
        const CircularProgressIndicator(),
        const LinearProgressIndicator(),
        Container(color: Colors.blue, width: 100, height: 100),
        const Icon(Icons.home),
      ];
      
      for (int cycle = 0; cycle < 3; cycle++) {
        for (final widget in widgets) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: widget),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      
      // Final pump to ensure stability
      await tester.pumpAndSettle();
      expect(find.byType(Icon), findsOneWidget);
    });
  });
}

// Test helper widgets
class _TestStreamWidget extends StatefulWidget {
  final List<StreamController<String>> controllers;
  
  const _TestStreamWidget(this.controllers);
  
  @override
  State<_TestStreamWidget> createState() => _TestStreamWidgetState();
}

class _TestStreamWidgetState extends State<_TestStreamWidget> {
  late StreamController<String> _controller1;
  late StreamController<String> _controller2;
  
  @override
  void initState() {
    super.initState();
    _controller1 = StreamController<String>();
    _controller2 = StreamController<String>();
    widget.controllers.addAll([_controller1, _controller2]);
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

class _TestAnimationWidget extends StatefulWidget {
  final List<AnimationController> controllers;
  
  const _TestAnimationWidget(this.controllers);
  
  @override
  State<_TestAnimationWidget> createState() => _TestAnimationWidgetState();
}

class _TestAnimationWidgetState extends State<_TestAnimationWidget> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    widget.controllers.add(_controller);
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Text('Test Animation Widget'),
    );
  }
}