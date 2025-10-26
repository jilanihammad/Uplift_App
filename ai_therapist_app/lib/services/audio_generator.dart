import 'dart:convert';
import 'dart:io' as io;
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../data/datasources/remote/api_client.dart';
import 'path_manager.dart';
import '../di/interfaces/i_tts_service.dart';
import '../di/interfaces/i_audio_file_manager.dart';
import 'simple_tts_service.dart';
import '../utils/logger_util.dart';
import '../config/app_config.dart';
import '../config/llm_config.dart';
import '../utils/sentence_boundary_detector.dart';

/// Handles generation of audio from text
class AudioGenerator {
  // Singleton instance
  static AudioGenerator? _instance;

  // TTS service for audio generation and playback
  final ITTSService _ttsService;
  final IAudioFileManager _audioFileManager;

  // API client for direct API calls
  final ApiClient _apiClient;

  // Callback for TTS state updates (to avoid circular dependencies)
  void Function(bool isSpeaking)? _ttsStateCallback;

  // INTELLIGENT CACHE: cache_key -> file_path (PERFORMANCE OPTIMIZED!)
  final Map<String, String> _intelligentCache = {};

  // Legacy cache for backwards compatibility during migration
  final Map<String, String> _audioCache = {};

  // Performance profiling
  final Map<String, int> _performanceMetrics = {};

  // Flag to track if initialized
  bool _isInitialized = false;

  // Flag to control whether to use direct TTS calls or backend proxy
  // Set this to true to bypass backend and call TTS providers directly
  static const bool _useDirectTTSCalls =
      false; // Change to true to enable direct calls

  // Factory constructor to enforce singleton pattern
  factory AudioGenerator({
    required ITTSService ttsService,
    required IAudioFileManager audioFileManager,
    required ApiClient apiClient,
  }) {
    // Return existing instance if already created
    if (_instance != null) {
      if (kDebugMode) {
        debugPrint('Reusing existing AudioGenerator instance');
      }
      return _instance!;
    }

    // Create new instance if first time
    _instance = AudioGenerator._internal(
        ttsService: ttsService,
        audioFileManager: audioFileManager,
        apiClient: apiClient);

    return _instance!;
  }

  // Private constructor for singleton pattern
  AudioGenerator._internal({
    required ITTSService ttsService,
    required IAudioFileManager audioFileManager,
    required ApiClient apiClient,
  })  : _ttsService = ttsService,
        _audioFileManager = audioFileManager,
        _apiClient = apiClient {
    if (kDebugMode) {
      debugPrint('AudioGenerator initialized with constructor injection');
    }
  }

  /// Initialize the audio generator - now lazy (only runs when first needed)
  Future<bool> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('AudioGenerator already initialized, skipping initialize()');
      }
      return true;
    }

    final stopwatch = Stopwatch()..start();
    try {
      await _ttsService.initialize();
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

  /// Generate and play audio from text (PERFORMANCE OPTIMIZED WITH INTELLIGENT CACHING)
  Future<String?> generateAndPlayAudio(String text) async {
    final stopwatch = Stopwatch()..start();

    // Use intelligent caching for better context awareness while maintaining speed
    final audioPath = await generateAudioIntelligent(text);

    if (audioPath != null) {
      // Play the audio with performance tracking
      final playStopwatch = Stopwatch()..start();
      await _ttsService.playAudio(audioPath);
      playStopwatch.stop();

      log.i('Playing audio took ${playStopwatch.elapsedMilliseconds}ms');
      _performanceMetrics['play_audio'] = playStopwatch.elapsedMilliseconds;
    }

    stopwatch.stop();
    _performanceMetrics['total_with_playback'] = stopwatch.elapsedMilliseconds;
    log.i(
        'Total TTS + playback took ${stopwatch.elapsedMilliseconds}ms (intelligent caching enabled)');

    return audioPath;
  }

  /// Generate and optionally play audio from text (INTELLIGENT CACHING ENABLED)
  /// If autoPlay is false, it will only generate the audio without playing it
  Future<String?> generateAndOptionallyPlayAudio(String text,
      {bool autoPlay = true}) async {
    final stopwatch = Stopwatch()..start();

    // Use intelligent caching for better context decisions while maintaining ~1-10ms speed
    final audioPath = await generateAudioIntelligent(text);

    if (audioPath != null) {
      // Play the audio if requested
      if (autoPlay) {
        final playStopwatch = Stopwatch()..start();
        await _ttsService.playAudio(audioPath);
        playStopwatch.stop();
        _performanceMetrics['play_audio'] = playStopwatch.elapsedMilliseconds;
        log.i('Played audio in ${playStopwatch.elapsedMilliseconds}ms');
      } else {
        log.i('Generated audio without playing (intelligent caching)');
      }
    }

    stopwatch.stop();
    _performanceMetrics['total_optional_play'] = stopwatch.elapsedMilliseconds;
    log.i(
        'Total TTS process took ${stopwatch.elapsedMilliseconds}ms (intelligent caching, autoPlay=$autoPlay)');

    return audioPath;
  }

  /// Get the file path for an audio file
  String _getAudioFilePath(String fileName) {
    // Use PathManager to get cache directory and join with filename using path package
    return p.join(PathManager.instance.cacheDir, fileName);
  }

  /// Generate intelligent cache key locally (temporary until backend provides it)
  String _generateIntelligentCacheKey(String text) {
    // Simple hash-based approach for now - backend will provide better logic
    final textHash = text.hashCode.abs().toString();
    final timestamp =
        DateTime.now().millisecondsSinceEpoch ~/ (1000 * 60 * 60); // Hour-based
    return 'local_${textHash}_$timestamp';
  }

  /// Generate audio using intelligent caching (HYBRID PERFORMANCE APPROACH)
  Future<String?> generateAudioIntelligent(String text,
      {bool isAiSpeaking = true}) async {
    if (!_isInitialized) {
      await initializeOnlyIfNeeded();
    }

    final stopwatch = Stopwatch()..start();

    // Generate intelligent cache key (temporarily local, backend will provide this)
    final cacheKey = _generateIntelligentCacheKey(text);

    // Check intelligent cache FIRST (maintains ~1-10ms performance!)
    if (_intelligentCache.containsKey(cacheKey)) {
      final cachedPath = _intelligentCache[cacheKey]!;

      // Verify file still exists
      if (await io.File(cachedPath).exists()) {
        log.i(
            'INTELLIGENT CACHE HIT for key: $cacheKey (~1-10ms access maintained!)');
        stopwatch.stop();
        _performanceMetrics['fetch_intelligent_cached'] =
            stopwatch.elapsedMilliseconds;
        return cachedPath;
      } else {
        // Clean up dead cache entry
        _intelligentCache.remove(cacheKey);
        log.w('Removed dead cache entry for key: $cacheKey');
      }
    }

    // Not in intelligent cache, generate new audio
    log.i('Generating new audio for intelligent cache key: $cacheKey');

    try {
      String? audioPath;

      if (_useDirectTTSCalls) {
        audioPath = await generateAudioDirect(text, isAiSpeaking: isAiSpeaking);
      } else {
        audioPath =
            await _generateAudioViaBackend(text, isAiSpeaking: isAiSpeaking);
      }

      if (audioPath != null) {
        // Store in intelligent cache with intelligent key
        _intelligentCache[cacheKey] = audioPath;
        log.i(
            'Cached audio with intelligent key: $cacheKey (maintains local ~1-10ms access)');

        stopwatch.stop();
        _performanceMetrics['total_intelligent_generate'] =
            stopwatch.elapsedMilliseconds;
        return audioPath;
      }

      stopwatch.stop();
      return null;
    } catch (e) {
      stopwatch.stop();
      log.e('Error generating audio with intelligent caching', e);
      return null;
    }
  }

  /// Generate audio without playing it (LEGACY - will be replaced)
  Future<String?> generateAudio(String text, {bool isAiSpeaking = true}) async {
    if (!_isInitialized) {
      await initializeOnlyIfNeeded();
    }

    final stopwatch = Stopwatch()..start();

    // Check if audio is in cache first
    if (_audioCache.containsKey(text)) {
      log.i(
          'Using cached audio for text: "${text.substring(0, min(20, text.length))}..."');
      final cachedPath = _audioCache[text]!;
      stopwatch.stop();
      _performanceMetrics['fetch_cached_audio'] = stopwatch.elapsedMilliseconds;
      return cachedPath;
    }

    try {
      String? audioPath;

      if (_useDirectTTSCalls) {
        // Use direct TTS API call
        log.d(
            'Using direct TTS calls (${LLMConfig.activeTTSProvider} - ${LLMConfig.activeTTSModelId})');
        audioPath = await generateAudioDirect(text, isAiSpeaking: isAiSpeaking);
      } else {
        // Use backend proxy (original behavior)
        audioPath =
            await _generateAudioViaBackend(text, isAiSpeaking: isAiSpeaking);
      }

      if (audioPath != null) {
        // Cache the result
        _audioCache[text] = audioPath;
        stopwatch.stop();
        _performanceMetrics['total_generate'] = stopwatch.elapsedMilliseconds;
        return audioPath;
      }

      stopwatch.stop();
      _performanceMetrics['total_generate'] = stopwatch.elapsedMilliseconds;
      return null;
    } catch (e) {
      stopwatch.stop();
      log.e('Error generating audio', e);
      _performanceMetrics['generate_audio_error'] =
          stopwatch.elapsedMilliseconds;
      return null;
    }
  }

  /// Generate audio using TTSStreamingService (NEW clean approach)
  Future<String?> _generateAudioViaBackend(String text,
      {bool isAiSpeaking = true}) async {
    try {
      final generationStopwatch = Stopwatch()..start();
      final completer = Completer<String?>();

      // Use TTSService for TTS generation - no more duplicate calls!
      String? filePath;
      await _ttsService.streamAndPlayTTS(
        text,
        onDone: () {
          generationStopwatch.stop();
          _performanceMetrics['generate_audio'] =
              generationStopwatch.elapsedMilliseconds;
          log.i('TTSService TTS generation completed');
        },
        onError: (error) {
          generationStopwatch.stop();
          log.e('TTSService TTS error: $error');
        },
      );

      // Since streamAndPlayTTS doesn't return file path, we generate one for caching
      // This is a temporary solution - in future, TTSService could return file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      filePath = _getAudioFilePath('tts_audio_$timestamp.wav');

      return filePath;
    } catch (e) {
      log.e('Error generating audio via TTSService', e);
      return null;
    }
  }

  /// Play audio from a given URL or file path
  Future<bool> playAudio(String audioPath) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _ttsService.playAudio(audioPath);
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
      await _ttsService.stopAudio();
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
      debugPrint(
          '[BACKGROUND] Audio generation started for text: "${text.substring(0, min(20, text.length))}..."');

      // Simple audio generation using HTTP directly since we can't use the VoiceService in isolate
      final uri = Uri.parse('$backendUrl/voice/synthesize');
      final headers = {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      debugPrint('[BACKGROUND] Sending request to: $uri');
      final stopwatch = Stopwatch()..start();
      final response = await http.post(uri,
          headers: headers,
          body: jsonEncode({
            'text': text,
            'voice': LLMConfig.activeTTSVoice,
          }));
      stopwatch.stop();

      debugPrint(
          '[BACKGROUND] Response received in ${stopwatch.elapsedMilliseconds}ms with status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Use the correct backend URL for the audio file URL
        String audioUrl = data['url'];
        if (audioUrl.startsWith('/')) {
          audioUrl = '$backendUrl$audioUrl';
        }
        debugPrint('[BACKGROUND] Successfully generated audio, URL: $audioUrl');
        return audioUrl;
      } else {
        debugPrint(
            '[BACKGROUND] Audio generation failed with status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BACKGROUND] Error generating audio in background: $e');
    }

    return null;
  }

  /// Make a direct API call to generate audio (bypassing VoiceService)
  Future<String?> directApiGenerateAudio(String text,
      {bool isAiSpeaking = true}) async {
    try {
      final backendUrl = AppConfig().backendUrl;
      final response = await _apiClient.post('/voice/synthesize', {
        'text': text,
        'voice': LLMConfig.activeTTSVoice,
      });

      if (response.containsKey('url')) {
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
      // Use TTSService to play cached audio
      try {
        await _ttsService.playAudio(cachedAudioPath);
        onDone?.call();
      } catch (e) {
        onError?.call('Error playing cached audio: $e');
      }
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

    // Not in cache, generate new audio using TTSStreamingService with auto-playback
    log.i(
        'Audio not cached for: "${text.substring(0, min(20, text.length))}...". Generating via TTSStreamingService.');
    final genStopwatch = Stopwatch()..start();
    String? audioPath;
    try {
      // Generate audio WITH auto-play (VoiceService.generateAudio already plays during streaming)
      audioPath = await _generateAudioViaBackend(text, isAiSpeaking: true);
      genStopwatch.stop();
      _performanceMetrics['generate_audio_via_tts_service'] =
          genStopwatch.elapsedMilliseconds;

      // VoiceService.generateAudio() already played the audio during streaming
      // No need to play again - just trigger callbacks
      if (audioPath != null) {
        onDone?.call(); // Audio was already played during generation
      } else {
        onError?.call('Failed to generate audio file');
      }
    } catch (e) {
      genStopwatch.stop();
      log.e('Error calling TTSStreamingService: $e');
      onError?.call('Failed during TTS generation: ${e.toString()}');
      // audioPath will remain null
    }

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
      await _ttsService.playAudio(audioUrl);
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

  /// Make a direct TTS API call using centralized configuration
  /// This bypasses the backend and calls the TTS provider directly
  Future<String?> generateAudioDirect(String text,
      {bool isAiSpeaking = true}) async {
    try {
      final ttsConfig = LLMConfig.currentTTSConfig;

      if (kDebugMode) {
        debugPrint(
            '[AudioGenerator] Making direct TTS call to ${ttsConfig.modelId}');
      }

      // Get API key from environment variable
      final apiKey = await _getApiKeyForProvider(ttsConfig.apiKeyEnvVar);
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API key not found for ${ttsConfig.apiKeyEnvVar}');
      }

      // Build headers
      final headers = Map<String, String>.from(ttsConfig.headers);
      headers['Authorization'] = 'Bearer $apiKey';

      // Build request body based on provider
      final body = _buildTTSRequestBody(ttsConfig, text, isAiSpeaking);

      if (kDebugMode) {
        debugPrint('[AudioGenerator] TTS Request to: ${ttsConfig.endpoint}');
        debugPrint('[AudioGenerator] TTS Model: ${ttsConfig.modelId}');
      }

      // Make the request
      final response = await http.post(
        Uri.parse(ttsConfig.endpoint),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        // For OpenAI TTS, the response is the audio data directly
        final audioBytes = response.bodyBytes;

        // Save to temporary file
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final audioFileName = 'direct_tts_$timestamp.mp3';
        final audioFile = io.File(_getAudioFilePath(audioFileName));

        await audioFile.writeAsBytes(audioBytes);

        if (kDebugMode) {
          debugPrint(
              '[AudioGenerator] Direct TTS audio saved to: ${audioFile.path}');
        }

        return audioFile.path;
      } else {
        throw Exception(
            'TTS API call failed with status: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioGenerator] Direct TTS call failed: $e');
      }
      return null;
    }
  }

  /// Build request body for different TTS providers
  Map<String, dynamic> _buildTTSRequestBody(
    TTSModelConfig config,
    String text,
    bool isAiSpeaking,
  ) {
    final provider = LLMConfig.activeTTSProvider;

    switch (provider) {
      case LLMProvider.openai:
        return _buildOpenAITTSBody(config, text, isAiSpeaking);

      case LLMProvider.custom:
        // For custom providers, use OpenAI format as default
        return _buildOpenAITTSBody(config, text, isAiSpeaking);

      default:
        // For other providers that don't have TTS yet, use OpenAI format
        return _buildOpenAITTSBody(config, text, isAiSpeaking);
    }
  }

  /// Build OpenAI TTS style request body
  Map<String, dynamic> _buildOpenAITTSBody(
    TTSModelConfig config,
    String text,
    bool isAiSpeaking,
  ) {
    // Choose voice based on speaking role and config
    String voice = config.voice ?? LLMConfig.activeTTSVoice;

    // You could customize voice based on isAiSpeaking if needed
    // For example: if (!isAiSpeaking) voice = 'onyx';

    final body = {
      'model': config.modelId,
      'input': text,
      'voice': voice,
      ...config.defaultParams,
    };

    return body;
  }

  /// Get API key for a specific provider from secure storage
  Future<String?> _getApiKeyForProvider(String envVarName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(envVarName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[AudioGenerator] Error getting API key for $envVarName: $e');
      }
      return null;
    }
  }

  /// Get the current cache size
  int getCacheSize() {
    return _audioCache.length;
  }

  /// Generate TTS from streaming text chunks
  /// This method processes text chunks as they arrive and generates TTS for complete sentences
  Future<void> generateStreamingTTS({
    required Stream<String> textStream,
    required void Function(String audioPath) onAudioReady,
    required void Function() onDone,
    required void Function(String error) onError,
    bool useTherapeuticProcessing = false,
  }) async {
    final detector = SentenceBoundaryDetector();
    final List<Future<void>> audioGenerationTasks = [];

    try {
      await for (String chunk in textStream) {
        // Add chunk to sentence detector
        detector.addChunk(chunk);

        // Extract complete sentences
        List<String> sentences = useTherapeuticProcessing
            ? detector.extractTherapeuticSentences()
            : detector.extractCompleteSentences();

        // Generate TTS for each complete sentence
        for (String sentence in sentences) {
          final audioTask =
              _generateSentenceTTS(sentence, onAudioReady, onError);
          audioGenerationTasks.add(audioTask);
        }
      }

      // Process any remaining text
      final remaining = detector.flushRemaining();
      if (remaining != null) {
        final audioTask =
            _generateSentenceTTS(remaining, onAudioReady, onError);
        audioGenerationTasks.add(audioTask);
      }

      // Wait for all audio generation to complete
      await Future.wait(audioGenerationTasks);

      onDone();
    } catch (e) {
      log.e('Error in streaming TTS generation', e);
      onError('Error in streaming TTS: ${e.toString()}');
    }
  }

  /// Generate TTS for a single sentence with caching
  Future<void> _generateSentenceTTS(
    String sentence,
    void Function(String audioPath) onAudioReady,
    void Function(String error) onError,
  ) async {
    try {
      // Check cache first for performance
      if (_intelligentCache.containsKey(sentence)) {
        final cachedPath = _intelligentCache[sentence]!;
        if (await io.File(cachedPath).exists()) {
          onAudioReady(cachedPath);
          return;
        }
      }

      // Generate new audio
      final audioPath = await generateAudioIntelligent(sentence);
      if (audioPath != null) {
        onAudioReady(audioPath);
      } else {
        onError(
            'Failed to generate audio for: ${sentence.substring(0, min(30, sentence.length))}...');
      }
    } catch (e) {
      log.e('Error generating sentence TTS', e);
      onError('TTS generation error: ${e.toString()}');
    }
  }

  /// Streaming TTS with automatic playback queue management
  /// This method handles the complete flow: text streaming -> sentence detection -> TTS generation -> playback
  Future<void> streamingTTSWithPlayback({
    required Stream<String> textStream,
    required void Function() onFirstAudioStart,
    required void Function() onAllAudioComplete,
    required void Function(String error) onError,
    bool useTherapeuticProcessing = false,
  }) async {
    final audioQueue = <String>[];
    bool isPlaying = false;
    bool firstAudioStarted = false;

    // Handle audio generation
    await generateStreamingTTS(
      textStream: textStream,
      useTherapeuticProcessing: useTherapeuticProcessing,
      onAudioReady: (audioPath) async {
        audioQueue.add(audioPath);

        // Start playback queue if not already playing
        if (!isPlaying) {
          isPlaying = true;
          _playAudioQueue(audioQueue, onFirstAudioStart, onAllAudioComplete,
              onError, firstAudioStarted);
          firstAudioStarted = true;
        }
      },
      onDone: () {
        // Mark that text stream is complete
        log.i('Text streaming complete, waiting for audio queue to finish');
      },
      onError: onError,
    );
  }

  /// Play audio files in queue order
  Future<void> _playAudioQueue(
    List<String> queue,
    void Function() onFirstAudioStart,
    void Function() onAllAudioComplete,
    void Function(String error) onError,
    bool firstAudioStarted,
  ) async {
    bool hasStarted = firstAudioStarted;

    while (queue.isNotEmpty) {
      final audioPath = queue.removeAt(0);

      try {
        if (!hasStarted) {
          // Notify via callback that TTS is starting
          _ttsStateCallback?.call(true);
          onFirstAudioStart();
          hasStarted = true;
        }

        await _ttsService.playAudio(audioPath);
        log.i('Finished playing audio segment: $audioPath');
      } catch (e) {
        log.e('Error playing audio from queue', e);
        onError('Playback error: ${e.toString()}');
      }
    }

    // Notify via callback that TTS is complete
    _ttsStateCallback?.call(false);

    onAllAudioComplete();
  }

  /// Create text stream from WebSocket AI response
  /// This converts the WebSocket chunk stream into a text stream for TTS processing
  Stream<String> createTextStreamFromWebSocket(
      Stream<Map<String, dynamic>> webSocketStream) async* {
    await for (final event in webSocketStream) {
      if (event['type'] == 'chunk' && event.containsKey('content')) {
        yield event['content'] as String;
      } else if (event['type'] == 'error') {
        log.e('WebSocket error in text stream: ${event['detail']}');
        throw Exception('WebSocket error: ${event['detail']}');
      }
      // 'done' type is handled by stream completion
    }
  }

  /// High-level method to process AI response with streaming TTS
  /// This is the main entry point for streaming TTS functionality
  Future<void> processAIResponseWithStreamingTTS({
    required Stream<Map<String, dynamic>> aiResponseStream,
    required void Function() onTTSStart,
    required void Function() onTTSComplete,
    required void Function(String error) onError,
    bool useTherapeuticProcessing = false,
  }) async {
    try {
      // Convert AI response stream to text and collect it
      final textStream = createTextStreamFromWebSocket(aiResponseStream);
      final completeText = StringBuffer();
      bool hasStarted = false;

      // Collect all text from the stream
      await for (final chunk in textStream) {
        completeText.write(chunk);
        // Start TTS after first chunk to begin playback quickly
        if (!hasStarted && completeText.length > 10) {
          hasStarted = true;
          // Notify via callback that TTS is starting
          _ttsStateCallback?.call(true);
          onTTSStart();
        }
      }

      // Notify via callback that TTS is starting
      _ttsStateCallback?.call(true);

      // Use new simplified API - single method call!
      // SimpleTTSService will automatically call _ttsStateCallback(false) when done
      await _ttsService.speak(completeText.toString(), makeBackupFile: false);

      log.i('🎵 TTS streaming completed with simplified API');

      onTTSComplete();
    } catch (e) {
      log.e('Error processing AI response with streaming TTS', e);
      onError('Failed to process AI response: ${e.toString()}');
    }
  }

  /// Set callback for TTS state updates (to coordinate with VoiceService)
  void setTTSStateCallback(void Function(bool isSpeaking)? callback) {
    _ttsStateCallback = callback;

    // Wire the completion callback to SimpleTTSService if it supports it
    if (_ttsService is SimpleTTSService) {
      final simpleTTSService = _ttsService as SimpleTTSService;
      simpleTTSService.setCompletionCallback(callback);
      if (kDebugMode && callback != null) {
        log.i(
            'AudioGenerator: TTS completion callback wired to SimpleTTSService');
      }
    }

    if (kDebugMode && callback != null) {
      log.i('AudioGenerator: TTS state callback registered');
    }
  }

  /// Legacy method for VAD callbacks - now no-op as echo-loop prevention removed
  void setVADCallbacks({
    Future<void> Function()? pauseCallback,
    Future<void> Function()? resumeCallback,
  }) {
    if (kDebugMode) {
      log.i(
          'AudioGenerator: VAD callbacks disabled (legacy workaround removed)');
    }
    // No-op: VAD pause/resume logic removed with new TTS architecture
  }

  /// Dispose of resources
  void dispose() {
    clearCache();
  }
}
