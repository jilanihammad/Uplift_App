import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/di/interfaces/i_therapy_service.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/audio_generator.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'dart:async';
import 'package:ai_therapist_app/config/app_config.dart';

/// A screen for diagnostic testing of critical app components like LLM and TTS
class DiagnosticScreen extends StatefulWidget {
  final ITherapyService? therapyService;
  final ApiClient? apiClient;
  final VoiceService? voiceService;
  final AudioGenerator? audioGenerator;
  
  const DiagnosticScreen({
    Key? key,
    this.therapyService,
    this.apiClient,
    this.voiceService,
    this.audioGenerator,
  }) : super(key: key);

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  late final ITherapyService _therapyService;
  late final VoiceService _voiceService;
  late final AudioGenerator _audioGenerator;
  Map<String, dynamic>? _serviceStatus;
  bool _isLoading = false;
  String? _error;

  // Test results
  String _llmTestResult = '';
  String _ttsTestResult = '';
  bool _isTestingLLM = false;
  bool _isTestingTTS = false;

  final TextEditingController _testMessageController = TextEditingController(
    text: "Hello, I'm feeling a bit anxious today. Can you help me?",
  );

  @override
  void initState() {
    super.initState();
    // Use dependency injection with fallback to DependencyContainer
    _therapyService = widget.therapyService ?? DependencyContainer().therapy;
    _voiceService = widget.voiceService ?? serviceLocator<VoiceService>();
    _audioGenerator = widget.audioGenerator ?? DependencyContainer().audioGenerator;
    _checkServiceStatus();
  }

  @override
  void dispose() {
    _testMessageController.dispose();
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // For diagnostic purposes, we need access to the concrete implementation
      // Try to use the injected service if it has the method, otherwise fallback to DependencyContainer
      Map<String, dynamic> status;
      if (_therapyService is TherapyService) {
        status = await (_therapyService as TherapyService).checkServiceStatus();
      } else {
        // Fallback to DependencyContainer for diagnostic functionality
        final concreteService = DependencyContainer().get<TherapyService>();
        status = await concreteService.checkServiceStatus();
      }
      setState(() {
        _serviceStatus = status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // Test the LLM service
  Future<void> _testLLMService() async {
    setState(() {
      _isTestingLLM = true;
      _llmTestResult = 'Testing LLM service...';
    });

    try {
      // Get a response from the therapy service
      final response =
          await _therapyService.processUserMessage(_testMessageController.text);

      setState(() {
        _isTestingLLM = false;
        _llmTestResult = 'LLM Response:\n$response';
      });
    } catch (e) {
      setState(() {
        _isTestingLLM = false;
        _llmTestResult = 'Error: ${e.toString()}';
      });
    }
  }

  // Test the TTS service
  Future<void> _testTTSService() async {
    if (_llmTestResult.isEmpty || !_llmTestResult.contains('LLM Response:')) {
      setState(() {
        _ttsTestResult = 'Please test LLM first to get a response for TTS';
      });
      return;
    }

    setState(() {
      _isTestingTTS = true;
      _ttsTestResult = 'Testing TTS service...';
    });

    try {
      // Extract the LLM response text
      final response = _llmTestResult.replaceFirst('LLM Response:\n', '');

      // Generate audio from the LLM response using AudioGenerator
      final audioPath = await _audioGenerator.generateAudio(response);

      setState(() {
        _ttsTestResult = 'Audio generated successfully: $audioPath';
      });

      // Play the audio
      if (audioPath != null) {
        await _voiceService.playAudio(audioPath);
      }

      setState(() {
        _isTestingTTS = false;
        _ttsTestResult += '\nAudio playback complete.';
      });
    } catch (e) {
      setState(() {
        _isTestingTTS = false;
        _ttsTestResult = 'Error: ${e.toString()}';
      });
    }
  }

  // Test the status endpoint directly
  Future<void> _testStatusEndpoint() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiClient = widget.apiClient ?? DependencyContainer().apiClientConcrete;
      debugPrint(
          '[DEBUG] Testing status endpoint directly with raw HTTP request');

      // Make a direct HTTP request to verify API accessibility
      try {
        final backendUrl = AppConfig().backendUrl;
        final uri = Uri.parse('$backendUrl/llm/status');

        debugPrint('[DEBUG] Sending request to: $uri');
        final response = await http.get(uri);

        if (response.statusCode == 200) {
          debugPrint(
              '[DEBUG] Status endpoint accessible: ${response.statusCode}');

          // Parse the response
          final jsonResponse = jsonDecode(response.body);
          setState(() {
            _serviceStatus = jsonResponse;
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Status endpoint is accessible 👍'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          debugPrint(
              '[DEBUG] Status endpoint error: ${response.statusCode} - ${response.body}');
          setState(() {
            _isLoading = false;
            _error =
                'Status endpoint returned ${response.statusCode}: ${response.body}';
          });
        }
      } catch (e) {
        debugPrint('[DEBUG] Direct HTTP request failed: $e');
        setState(() {
          _isLoading = false;
          _error = 'Direct HTTP request failed: $e';
        });
      }
    } catch (e) {
      debugPrint('[DEBUG] Error testing status endpoint: $e');
      setState(() {
        _isLoading = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkServiceStatus,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.api),
          label: const Text('Test Status Endpoint Directly'),
          onPressed: _isLoading ? null : _testStatusEndpoint,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueGrey,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error checking service status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkServiceStatus,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_serviceStatus == null) {
      return const Center(
        child: Text('No service status information available'),
      );
    }

    // Check if we got an error response
    if (_serviceStatus!.containsKey('error')) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            Text(
              'Service Status Check Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_serviceStatus!['error'] as String),
            const SizedBox(height: 8),
            Text('Status: ${_serviceStatus!['status'] as String}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkServiceStatus,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    // Display the full service status and manual testing UI
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Service Status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  _buildServiceStatusSection(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Keys',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  _buildApiKeysSection(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Raw Response',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  Text(
                    const JsonEncoder.withIndent('  ').convert(_serviceStatus),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manual Testing',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _testMessageController,
                    decoration: const InputDecoration(
                      labelText: 'Test message',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isTestingLLM ? null : _testLLMService,
                          child:
                              Text(_isTestingLLM ? 'Testing...' : 'Test LLM'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isTestingTTS ? null : _testTTSService,
                          child:
                              Text(_isTestingTTS ? 'Testing...' : 'Test TTS'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_llmTestResult.isNotEmpty) ...[
                    const Text(
                      'LLM Test Result:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      width: double.infinity,
                      child: Text(_llmTestResult),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_ttsTestResult.isNotEmpty) ...[
                    const Text(
                      'TTS Test Result:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      width: double.infinity,
                      child: Text(_ttsTestResult),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceStatusSection() {
    if (!_serviceStatus!.containsKey('services')) {
      return const Text('No service information available');
    }

    final services = _serviceStatus!['services'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildServiceItem(
          'LLM Service',
          services['llm']['available'] as bool,
          'Model: ${services['llm']['model']}',
        ),
        const Divider(),
        _buildServiceItem(
          'TTS Service',
          services['tts']['available'] as bool,
          'Model: ${services['tts']['model']}, Voice: ${services['tts']['voice']}',
        ),
        const Divider(),
        _buildServiceItem(
          'Transcription Service',
          services['transcription']['available'] as bool,
          'Model: ${services['transcription']['model']}',
        ),
      ],
    );
  }

  Widget _buildApiKeysSection() {
    if (!_serviceStatus!.containsKey('api_keys')) {
      return const Text('No API key information available');
    }

    final apiKeys = _serviceStatus!['api_keys'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildApiKeyItem(
          'OpenAI API Key',
          apiKeys['openai']['available'] as bool,
          apiKeys['openai']['key_preview'] as String?,
        ),
        const Divider(),
        _buildApiKeyItem(
          'Groq API Key',
          apiKeys['groq']['available'] as bool,
          apiKeys['groq']['key_preview'] as String?,
        ),
      ],
    );
  }

  Widget _buildServiceItem(String name, bool available, String details) {
    return Row(
      children: [
        Icon(
          available ? Icons.check_circle : Icons.error_outline,
          color: available ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                available ? 'Available' : 'Unavailable',
                style: TextStyle(
                  color: available ? Colors.green : Colors.red,
                ),
              ),
              Text(details),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyItem(String name, bool available, String? preview) {
    return Row(
      children: [
        Icon(
          available ? Icons.vpn_key : Icons.no_encryption,
          color: available ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                available ? 'Configured' : 'Not Configured',
                style: TextStyle(
                  color: available ? Colors.green : Colors.red,
                ),
              ),
              if (preview != null) Text('Key: $preview'),
            ],
          ),
        ),
      ],
    );
  }
}
