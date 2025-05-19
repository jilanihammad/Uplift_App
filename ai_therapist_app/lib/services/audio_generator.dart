import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../data/datasources/remote/api_client.dart';
import '../services/voice_service.dart';
import '../utils/logger_util.dart';
import '../config/app_config.dart';

/// Handles generation of audio from text
class AudioGenerator {
  // Singleton instance
  static AudioGenerator? _instance;

  // Voice service for audio generation and playback
  final VoiceService _voiceService;

  // API client for direct API calls
  final ApiClient _apiClient;

  // Cache for generated audio
  final Map<String, String> _audioCache = {};

  // Performance profiling
  final Map<String, int> _performanceMetrics = {};

  // Flag to track if initialized
  bool _isInitialized = false;

  // Factory constructor to enforce singleton pattern
  factory AudioGenerator({
    required VoiceService voiceService,
    required ApiClient apiClient,
  }) {
    // Return existing instance if already created
    if (_instance != null) {
      if (kDebugMode) {
        print('Reusing existing AudioGenerator instance');
      }
      return _instance!;
    }

    // Create new instance if first time
    _instance = AudioGenerator._internal(
        voiceService: voiceService, apiClient: apiClient);

    return _instance!;
  }

  // Private constructor for singleton pattern
  AudioGenerator._internal({
    required VoiceService voiceService,
    required ApiClient apiClient,
  })  : _voiceService = voiceService,
        _apiClient = apiClient {
    if (kDebugMode) {
      print('AudioGenerator initialized with constructor injection');
    }
  }

  /// Initialize the audio generator - now lazy (only runs when first needed)
  Future<bool> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        print('AudioGenerator already initialized, skipping initialize()');
      }
      return true;
    }

    final stopwatch = Stopwatch()..start();
    try {
      await _voiceService.initialize();
      stopwatch.stop();
      _performanceMetrics['initialization'] = stopwatch.elapsedMilliseconds;
      log.i(
          'Audio generator initialized successfully in ${stopwatch.elapsedMilliseconds}ms');
      _isInitialized = true;
      return true;
    } catch (e) {
      stopwatch.stop();
      log.w('Error initializing audio generator', e);
      return false;
    }
  }

  /// Initialize only if needed - for lazy initialization
  Future<bool> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      return await initialize();
    }
    return true;
  }

  /// Generate and play audio from text
  Future<String?> generateAndPlayAudio(String text) async {
    final stopwatch = Stopwatch()..start();

    // Check if audio is in cache first
    if (_audioCache.containsKey(text)) {
      log.i(
          'Using cached audio for text: "${text.substring(0, min(20, text.length))}..."');
      final cachedAudioPath = _audioCache[text]!;

      // Start playback and measure time
      final playStopwatch = Stopwatch()..start();
      await _voiceService.playAudio(cachedAudioPath);
      playStopwatch.stop();

      log.i('Playing cached audio took ${playStopwatch.elapsedMilliseconds}ms');
      _performanceMetrics['play_cached_audio'] =
          playStopwatch.elapsedMilliseconds;

      stopwatch.stop();
      _performanceMetrics['total_cached'] = stopwatch.elapsedMilliseconds;
      return cachedAudioPath;
    }

    // Not in cache, generate new audio
    final genStopwatch = Stopwatch()..start();
    final audioPath = await generateAudio(text);
    genStopwatch.stop();
    _performanceMetrics['generate_audio'] = genStopwatch.elapsedMilliseconds;

    if (audioPath != null) {
      // Cache the result
      _audioCache[text] = audioPath;

      // Play the audio
      final playStopwatch = Stopwatch()..start();
      await _voiceService.playAudio(audioPath);
      playStopwatch.stop();
      _performanceMetrics['play_new_audio'] = playStopwatch.elapsedMilliseconds;
    }

    stopwatch.stop();
    _performanceMetrics['total_uncached'] = stopwatch.elapsedMilliseconds;
    log.i(
        'Total TTS process took ${stopwatch.elapsedMilliseconds}ms (cached=${_audioCache.containsKey(text)})');

    return audioPath;
  }

  /// Generate and optionally play audio from text
  /// If autoPlay is false, it will only generate the audio without playing it
  Future<String?> generateAndOptionallyPlayAudio(String text,
      {bool autoPlay = true}) async {
    final stopwatch = Stopwatch()..start();

    // Check if audio is in cache first
    if (_audioCache.containsKey(text)) {
      log.i(
          'Using cached audio for text: "${text.substring(0, min(20, text.length))}..."');
      final cachedAudioPath = _audioCache[text]!;

      // Play if requested
      if (autoPlay) {
        // Start playback and measure time
        final playStopwatch = Stopwatch()..start();
        await _voiceService.playAudio(cachedAudioPath);
        playStopwatch.stop();

        log.i(
            'Playing cached audio took ${playStopwatch.elapsedMilliseconds}ms');
        _performanceMetrics['play_cached_audio'] =
            playStopwatch.elapsedMilliseconds;
      } else {
        log.i('Retrieved cached audio without playing');
      }

      stopwatch.stop();
      _performanceMetrics['total_cached'] = stopwatch.elapsedMilliseconds;
      return cachedAudioPath;
    }

    // Not in cache, generate new audio
    final genStopwatch = Stopwatch()..start();
    final audioPath = await generateAudio(text);
    genStopwatch.stop();
    _performanceMetrics['generate_audio'] = genStopwatch.elapsedMilliseconds;

    if (audioPath != null) {
      // Cache the result
      _audioCache[text] = audioPath;

      // Play the audio if requested
      if (autoPlay) {
        final playStopwatch = Stopwatch()..start();
        await _voiceService.playAudio(audioPath);
        playStopwatch.stop();
        _performanceMetrics['play_new_audio'] =
            playStopwatch.elapsedMilliseconds;
      } else {
        log.i('Generated audio without playing');
      }
    }

    stopwatch.stop();
    _performanceMetrics['total_uncached'] = stopwatch.elapsedMilliseconds;
    log.i(
        'Total TTS process took ${stopwatch.elapsedMilliseconds}ms (cached=${_audioCache.containsKey(text)}, autoPlay=$autoPlay)');

    return audioPath;
  }

  /// Get the file path for an audio file
  Future<String> _getAudioFilePath(String fileName) async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/$fileName';
  }

  /// Generate audio without playing it
  Future<String?> generateAudio(String text, {bool isAiSpeaking = true}) async {
    if (!_isInitialized) {
      await initializeOnlyIfNeeded();
    }

    final stopwatch = Stopwatch()..start();

    // Check if audio is in cache first
    if (_audioCache.containsKey(text)) {
      log.i(
          'Using cached audio for text: \"${text.substring(0, min(20, text.length))}...\"');
      final cachedPath = _audioCache[text]!;
      stopwatch.stop();
      _performanceMetrics['fetch_cached_audio'] = stopwatch.elapsedMilliseconds;
      return cachedPath;
    }

    try {
      // Generate a unique filename with OGG extension for opus format
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final hash = text.hashCode.abs();
      final audioFileName = 'audio_${timestamp}_$hash.ogg';

      // Generate audio using voice service
      final generationStopwatch = Stopwatch()..start();
      final audioPath = await _voiceService.generateAudio(text);
      generationStopwatch.stop();
      _performanceMetrics['generate_audio'] =
          generationStopwatch.elapsedMilliseconds;

      // If received a URL from voice service, download it to a local file
      if (audioPath != null && audioPath.startsWith('http')) {
        final tempDir = await getTemporaryDirectory();
        final localPath = '${tempDir.path}/$audioFileName';

        // Download the audio file
        final response = await http.get(Uri.parse(audioPath));
        if (response.statusCode == 200) {
          final file = File(localPath);
          await file.writeAsBytes(response.bodyBytes);

          // Cache the local file path
          _audioCache[text] = localPath;

          stopwatch.stop();
          _performanceMetrics['total_generate'] = stopwatch.elapsedMilliseconds;
          return localPath;
        }
      }

      // If it's a local file path already, just use it
      if (audioPath != null && !audioPath.startsWith('http')) {
        _audioCache[text] = audioPath;
        stopwatch.stop();
        _performanceMetrics['total_generate'] = stopwatch.elapsedMilliseconds;
        return audioPath;
      }

      // Return whatever we got from voice service
      stopwatch.stop();
      _performanceMetrics['total_generate'] = stopwatch.elapsedMilliseconds;
      return audioPath;
    } catch (e) {
      stopwatch.stop();
      log.e('Error generating audio', e);
      _performanceMetrics['generate_audio_error'] =
          stopwatch.elapsedMilliseconds;
      return null;
    }
  }

  /// Play audio from a given URL or file path
  Future<bool> playAudio(String audioPath) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _voiceService.playAudio(audioPath);
      stopwatch.stop();
      _performanceMetrics['play_audio'] = stopwatch.elapsedMilliseconds;
      return true;
    } catch (e) {
      stopwatch.stop();
      log.e('Error playing audio', e);
      return false;
    }
  }

  /// Stop any ongoing audio playback
  Future<void> stopAudio() async {
    try {
      await _voiceService.stopAudio();
    } catch (e) {
      log.e('Error stopping audio', e);
    }
  }

  /// Clear the audio cache to free up memory
  void clearCache() {
    _audioCache.clear();
    log.i('Audio cache cleared');
  }

  /// Get performance metrics for diagnostics
  Map<String, int> getPerformanceMetrics() {
    return Map.from(_performanceMetrics);
  }

  /// Generate audio in a background isolate
  static Future<String?> _generateAudioInBackground(
      Map<String, dynamic> params) async {
    final text = params['text'] as String;
    final apiUrl = params['voiceServiceUrl'] as String;
    final authToken = params['authToken'] as String?;
    final backendUrl = params['backendUrl'] as String;

    try {
      // Note: In background isolates, we can't use the logger class directly
      print(
          '[BACKGROUND] Audio generation started for text: "${text.substring(0, min(20, text.length))}..."');

      // Simple audio generation using HTTP directly since we can't use the VoiceService in isolate
      final uri = Uri.parse('$backendUrl/voice/synthesize');
      final headers = {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      print('[BACKGROUND] Sending request to: $uri');
      final stopwatch = Stopwatch()..start();
      final response = await http.post(uri,
          headers: headers, body: jsonEncode({'text': text, 'voice': 'sage'}));
      stopwatch.stop();

      print(
          '[BACKGROUND] Response received in ${stopwatch.elapsedMilliseconds}ms with status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Use the correct backend URL for the audio file URL
        String audioUrl = data['url'];
        if (audioUrl.startsWith('/')) {
          audioUrl = '$backendUrl$audioUrl';
        }
        print('[BACKGROUND] Successfully generated audio, URL: $audioUrl');
        return audioUrl;
      } else {
        print(
            '[BACKGROUND] Audio generation failed with status code: ${response.statusCode}');
      }
    } catch (e) {
      print('[BACKGROUND] Error generating audio in background: $e');
    }

    return null;
  }

  /// Make a direct API call to generate audio (bypassing VoiceService)
  Future<String?> directApiGenerateAudio(String text,
      {bool isAiSpeaking = true}) async {
    try {
      final backendUrl = AppConfig().backendUrl;
      final response = await _apiClient.post('/voice/synthesize', body: {
        'text': text,
        'voice': isAiSpeaking ? 'sage' : 'onyx',
      });

      if (response != null && response.containsKey('url')) {
        final audioUrl = response['url'];
        if (audioUrl != null) {
          // Ensure URL is absolute
          if (audioUrl.startsWith('/')) {
            return '$backendUrl$audioUrl';
          }
          return audioUrl;
        }
      }
      return null;
    } catch (e) {
      log.e('Error making direct API call for audio', e);
      return null;
    }
  }

  /// Generate and play audio with streaming (faster startup)
  Future<String?> generateAndStreamAudio(
    String text, {
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Check if audio is in cache first
    if (_audioCache.containsKey(text)) {
      final cachedAudioPath = _audioCache[text]!;
      log.i(
          'Using cached audio for text: "${text.substring(0, min(20, text.length))}..." Path: $cachedAudioPath');

      final playStopwatch = Stopwatch()..start();
      // Use the new VoiceService method to play cached audio with callbacks
      await _voiceService.playAudioWithCallbacks(cachedAudioPath,
          onDone: onDone, onError: onError);
      playStopwatch.stop();

      log.i(
          'Playing cached audio with callbacks took ${playStopwatch.elapsedMilliseconds}ms');
      _performanceMetrics['play_cached_audio_with_callbacks'] =
          playStopwatch.elapsedMilliseconds;

      stopwatch.stop();
      _performanceMetrics['total_cached_with_callbacks'] =
          stopwatch.elapsedMilliseconds;
      return cachedAudioPath;
    }

    // Not in cache, generate new audio using VoiceService.generateAudio, which handles TTS and callbacks
    log.i(
        'Audio not cached for: "${text.substring(0, min(20, text.length))}...". Generating anew via VoiceService.generateAudio.');
    final genStopwatch = Stopwatch()..start();
    String? audioPath;
    try {
      audioPath = await _voiceService.generateAudio(text,
          onDone: onDone, onError: onError);
    } catch (e) {
      log.e('Error calling _voiceService.generateAudio: $e');
      onError?.call('Failed during TTS generation: ${e.toString()}');
      // audioPath will remain null
    }
    genStopwatch.stop();
    _performanceMetrics['generate_audio_via_voice_service'] =
        genStopwatch.elapsedMilliseconds;

    if (audioPath != null) {
      // Cache the result
      _audioCache[text] = audioPath;
      log.i('Audio generated and cached: $audioPath');
    } else {
      log.w('Failed to generate audio path via VoiceService.generateAudio.');
    }

    stopwatch.stop();
    _performanceMetrics['total_generate_and_play_with_callbacks'] =
        stopwatch.elapsedMilliseconds;
    log.i(
        'Total TTS process (generate/play with callbacks) took ${stopwatch.elapsedMilliseconds}ms. Path: $audioPath');

    return audioPath;
  }

  /// Stream audio directly from a URL without downloading it first
  Future<bool> streamAudio(String audioUrl) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _voiceService.playStreamingAudio(audioUrl);
      stopwatch.stop();
      _performanceMetrics['stream_audio'] = stopwatch.elapsedMilliseconds;
      log.i('Streamed audio in ${stopwatch.elapsedMilliseconds}ms');
      return true;
    } catch (e) {
      stopwatch.stop();
      log.e('Error streaming audio', e);
      return false;
    }
  }
}
