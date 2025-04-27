import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const DebugApp());
}

class DebugApp extends StatelessWidget {
  const DebugApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API Debug Tool',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const DebugApiScreen(),
    );
  }
}

class DebugApiScreen extends StatefulWidget {
  const DebugApiScreen({Key? key}) : super(key: key);

  @override
  _DebugApiScreenState createState() => _DebugApiScreenState();
}

class _DebugApiScreenState extends State<DebugApiScreen> {
  final TextEditingController _messageController = TextEditingController();
  String _responseText = 'No response yet';
  bool _isLoading = false;
  String _selectedEndpoint = 'Cloud';

  final Map<String, String> _endpoints = {
    'Cloud': 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app',
    'Local Emulator': 'http://10.0.2.2:8001',
    'Local Device':
        'http://192.168.1.100:8001', // Change this to your actual IP
  };

  Future<void> _testLlmStatus() async {
    setState(() {
      _isLoading = true;
      _responseText = 'Testing LLM status...';
    });

    try {
      final String baseUrl =
          _endpoints[_selectedEndpoint] ?? _endpoints['Cloud']!;

      // Test the status endpoint
      final uri = Uri.parse('$baseUrl/api/v1/llm/status');
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

  Future<void> _testAiResponse() async {
    setState(() {
      _isLoading = true;
      _responseText = 'Testing AI response...';
    });

    try {
      final String baseUrl =
          _endpoints[_selectedEndpoint] ?? _endpoints['Cloud']!;
      final String message = _messageController.text.isNotEmpty
          ? _messageController.text
          : 'Hello, I am feeling anxious today';

      // Test the AI response endpoint
      final uri = Uri.parse('$baseUrl/ai/response');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'message': message,
              'system_prompt': 'You are a helpful AI assistant.',
              'temperature': 0.7,
              'max_tokens': 500,
            }),
          )
          .timeout(const Duration(seconds: 30));

      setState(() {
        _isLoading = false;
        _responseText =
            'AI Response (${response.statusCode}):\n${response.body}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Error testing AI response: $e';
      });
    }
  }

  Future<void> _testBackendEndpoints() async {
    setState(() {
      _isLoading = true;
      _responseText = 'Checking all backend endpoints...';
    });

    try {
      final String baseUrl =
          _endpoints[_selectedEndpoint] ?? _endpoints['Cloud']!;

      // Test various endpoints
      final List<String> endpointsToTest = [
        '/health',
        '/api/v1/llm/status',
        '/'
      ];

      String results = '';

      for (final endpoint in endpointsToTest) {
        try {
          final uri = Uri.parse('$baseUrl$endpoint');
          final response =
              await http.get(uri).timeout(const Duration(seconds: 10));

          results +=
              'Endpoint: $endpoint\nStatus: ${response.statusCode}\nResponse: ${response.body}\n\n';
        } catch (e) {
          results += 'Endpoint: $endpoint\nError: $e\n\n';
        }
      }

      setState(() {
        _isLoading = false;
        _responseText = 'Backend Endpoint Tests:\n\n$results';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Error testing backend endpoints: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Debug Tool'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select API Endpoint:'),
            DropdownButton<String>(
              value: _selectedEndpoint,
              isExpanded: true,
              items: _endpoints.keys.map((String endpoint) {
                return DropdownMenuItem<String>(
                  value: endpoint,
                  child: Text('$endpoint (${_endpoints[endpoint]})'),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedEndpoint = newValue;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message (optional)',
                hintText: 'Enter a test message',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _testLlmStatus,
                  child: const Text('Test LLM Status'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testAiResponse,
                  child: const Text('Test AI Response'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testBackendEndpoints,
                  child: const Text('Test All Endpoints'),
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
                child: SingleChildScrollView(
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
