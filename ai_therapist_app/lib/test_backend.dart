import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const TestBackendApp());
}

class TestBackendApp extends StatelessWidget {
  const TestBackendApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Backend Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const TestScreen(),
    );
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({Key? key}) : super(key: key);

  @override
  _TestScreenState createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  String _responseText = 'No response yet';
  bool _isLoading = false;
  final String _baseUrl =
      'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';

  Future<void> _testLlmStatus() async {
    setState(() {
      _isLoading = true;
      _responseText = 'Testing LLM status...';
    });

    try {
      // Test the status endpoint
      final uri = Uri.parse('$_baseUrl/api/v1/llm/status');
      final statusResponse =
          await http.get(uri).timeout(const Duration(seconds: 10));

      setState(() {
        _isLoading = false;
        _responseText =
            'Status response (${statusResponse.statusCode}):\n${statusResponse.body}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Error testing LLM status: $e';
      });
    }
  }

  Future<void> _testVoiceSynthesis() async {
    setState(() {
      _isLoading = true;
      _responseText = 'Testing voice synthesis...';
    });

    try {
      // Test the voice synthesis endpoint
      final uri = Uri.parse('$_baseUrl/voice/synthesize');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': 'This is a test of the voice synthesis system.',
              'voice': 'sage',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseJson = jsonDecode(response.body);
        final audioUrl = responseJson['url'];

        setState(() {
          _isLoading = false;
          _responseText = 'Voice synthesis response (${response.statusCode}):\n'
              'Audio URL: $audioUrl\n\n'
              'Full response: ${response.body}';
        });
      } else {
        setState(() {
          _isLoading = false;
          _responseText =
              'Error response (${response.statusCode}):\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Error testing voice synthesis: $e';
      });
    }
  }

  Future<void> _testRawAudio() async {
    setState(() {
      _isLoading = true;
      _responseText = 'Testing raw audio file...';
    });

    try {
      // First get the URL from synthesis
      final uri = Uri.parse('$_baseUrl/voice/synthesize');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': 'This is a test of the voice synthesis system.',
              'voice': 'sage',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseJson = jsonDecode(response.body);
        String audioUrl = responseJson['url'];

        // Make sure the URL is absolute
        if (audioUrl.startsWith('/')) {
          audioUrl = '$_baseUrl$audioUrl';
        }

        // Now try to download the audio file
        final audioResponse = await http
            .get(Uri.parse(audioUrl))
            .timeout(const Duration(seconds: 10));

        setState(() {
          _isLoading = false;
          _responseText = 'Audio file response (${audioResponse.statusCode}):\n'
              'Content-Type: ${audioResponse.headers['content-type']}\n'
              'Content-Length: ${audioResponse.contentLength} bytes\n\n'
              'Is this valid audio? ${audioResponse.contentLength != null && audioResponse.contentLength! > 1000 ? 'Likely' : 'No'}';
        });
      } else {
        setState(() {
          _isLoading = false;
          _responseText =
              'Error response (${response.statusCode}):\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Error testing raw audio: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _testLlmStatus,
                  child: const Text('Test LLM Status'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testVoiceSynthesis,
                  child: const Text('Test Voice Synthesis'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testRawAudio,
                  child: const Text('Test Audio File'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Response:'),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Text(_responseText),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
