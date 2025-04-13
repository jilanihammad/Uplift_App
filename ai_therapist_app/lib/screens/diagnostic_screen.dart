import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';
import 'package:ai_therapist_app/services/voice_service.dart';

/// A screen for diagnostic testing of critical app components like LLM and TTS
class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({Key? key}) : super(key: key);

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  final _therapyService = GetIt.instance<TherapyService>();
  final _voiceService = GetIt.instance<VoiceService>();
  
  final _promptController = TextEditingController();
  String _llmResponse = '';
  String _ttsStatus = '';
  String _currentAudioPath = '';
  bool _isProcessingLLM = false;
  bool _isProcessingTTS = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
  
  /// Test the LLM by sending a prompt and displaying the response
  Future<void> _testLLM() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }
    
    setState(() {
      _isProcessingLLM = true;
      _llmResponse = 'Processing...';
    });
    
    try {
      // Use therapy service to get a response
      final response = await _therapyService.processUserMessage(prompt);
      setState(() {
        _llmResponse = response; // Updated to use String response directly
        _isProcessingLLM = false;
      });
    } catch (e) {
      setState(() {
        _llmResponse = 'Error: ${e.toString()}';
        _isProcessingLLM = false;
      });
    }
  }

  /// Test the TTS by converting text to speech
  Future<void> _testTTS() async {
    if (_llmResponse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generate LLM response first')),
      );
      return;
    }
    
    setState(() {
      _isProcessingTTS = true;
      _ttsStatus = 'Converting text to speech...';
    });
    
    try {
      // Use voice service directly to convert text to speech
      final audioPath = await _voiceService.generateAudio(_llmResponse, isAiSpeaking: true); // Updated to use correct method
      setState(() {
        _currentAudioPath = audioPath;
        _ttsStatus = 'TTS conversion successful';
        _isProcessingTTS = false;
      });
      
      // Play the audio
      await _voiceService.playAudio(audioPath);
    } catch (e) {
      setState(() {
        _ttsStatus = 'Error: ${e.toString()}';
        _isProcessingTTS = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic Testing'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'LLM Testing',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Enter prompt for LLM',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isProcessingLLM ? null : _testLLM,
              child: Text(_isProcessingLLM ? 'Processing...' : 'Test LLM'),
            ),
            const SizedBox(height: 16),
            const Text(
              'LLM Response:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_llmResponse.isEmpty ? 'No response yet' : _llmResponse),
            ),
            
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            
            const Text(
              'TTS Testing',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isProcessingTTS || _llmResponse.isEmpty ? null : _testTTS,
              child: Text(_isProcessingTTS ? 'Processing...' : 'Test TTS with LLM Response'),
            ),
            const SizedBox(height: 16),
            const Text(
              'TTS Status:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_ttsStatus.isEmpty ? 'Not started' : _ttsStatus),
            ),
            if (_currentAudioPath.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Audio Path:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_currentAudioPath),
              ),
            ],
          ],
        ),
      ),
    );
  }
}