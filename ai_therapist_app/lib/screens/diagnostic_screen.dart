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
class DiagnosticScreen extends StatefulWidget {
  final ITherapyService? therapyService;
  final ApiClient? apiClient;
  final VoiceService? voiceService;
  final AudioGenerator? audioGenerator;
  const DiagnosticScreen({
    super.key,
    this.therapyService,
    this.apiClient,
    this.voiceService,
    this.audioGenerator,
  });
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
    _therapyService = widget.therapyService ?? DependencyContainer().therapy;
    _voiceService = widget.voiceService ?? serviceLocator<VoiceService>();
    _audioGenerator =
        widget.audioGenerator ?? DependencyContainer().audioGenerator;
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
      Map<String, dynamic> status;
      if (_therapyService is TherapyService) {
        status = await (_therapyService as TherapyService).checkServiceStatus();
      } else {
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
  Future<void> _testLLMService() async {
    setState(() {
      _isTestingLLM = true;
      _llmTestResult = 'Testing LLM service...';
    });
    try {
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
      final response = _llmTestResult.replaceFirst('LLM Response:\n', '');
      final audioPath = await _audioGenerator.generateAudio(response);
      setState(() {
        _ttsTestResult = 'Audio generated successfully: $audioPath';
      });
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
  Future<void> _testStatusEndpoint() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      try {
        final backendUrl = AppConfig().backendUrl;
        final uri = Uri.parse('$backendUrl/llm/status');
        final response = await http.get(uri);
        if (response.statusCode == 200) {
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
          setState(() {
            _isLoading = false;
            _error =
                'Status endpoint returned ${response.statusCode}: ${response.body}';
          });
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _error = 'Direct HTTP request failed: $e';
        });
      }
    } catch (e) {
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
