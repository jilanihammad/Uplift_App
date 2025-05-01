import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
    'Cloud': 'https://ai-therapist-backend-385290373302.us-central1.run.app',
    'Firebase': 'https://upliftapp-cd86e.web.app',
  };

  Future<void> _testApi() async {
    setState(() {
      _isLoading = true;
      _responseText = 'Sending request...';
    });

    try {
      final String baseUrl =
          _endpoints[_selectedEndpoint] ?? _endpoints['Cloud']!;
      final String message = _messageController.text.isNotEmpty
          ? _messageController.text
          : 'Hello, I am feeling anxious today';

      // First test the status endpoint
      setState(() {
        _responseText = 'Testing status endpoint: $baseUrl/api/v1/llm/status';
      });

      final uri = Uri.parse('$baseUrl/api/v1/llm/status');
      final statusResponse =
          await http.get(uri).timeout(const Duration(seconds: 10));

      setState(() {
        _responseText =
            'Status response (${statusResponse.statusCode}):\n${statusResponse.body}\n\nNow testing AI response...';
      });

      // Now test the AI response endpoint
      final postUri = Uri.parse('$baseUrl/ai/response');
      final response = await http
          .post(
            postUri,
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
            'Status code: ${response.statusCode}\n\nResponse:\n${response.body}\n\nHeaders:\n${response.headers}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _responseText = 'Error: $e';
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
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testApi,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Test API Connection'),
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
