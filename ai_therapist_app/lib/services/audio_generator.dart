import 'dart:convert';
import 'dart:io' as io;
import 'dart:async';
import 'dart:math';
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
class AudioGenerator {
  static AudioGenerator? _instance;
  final ITTSService _ttsService;
  final IAudioFileManager _audioFileManager;
  final ApiClient _apiClient;
  void Function(bool isSpeaking)? _ttsStateCallback;
  final Map<String, String> _intelligentCache = {};
  final Map<String, String> _audioCache = {};
  final Map<String, int> _performanceMetrics = {};
  bool _isInitialized = false;
  static const bool _useDirectTTSCalls =
      false; // Change to true to enable direct calls
  factory AudioGenerator({
    required ITTSService ttsService,
    required IAudioFileManager audioFileManager,
    required ApiClient apiClient,
  }) {
    if (_instance != null) {
      return _instance!;
    }
    _instance = AudioGenerator._internal(
        ttsService: ttsService,
        audioFileManager: audioFileManager,
        apiClient: apiClient);
    return _instance!;
  }
  AudioGenerator._internal({
    required ITTSService ttsService,
    required IAudioFileManager audioFileManager,
    required ApiClient apiClient,
  })  : _ttsService = ttsService,
        _audioFileManager = audioFileManager,
        _apiClient = apiClient {
  }
  Future<bool> initialize() async {
    if (_isInitialized) {
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
  Future<bool> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      return await initialize();
    }
    return true;
  }
  Future<String?> generateAndPlayAudio(String text) async {
    final stopwatch = Stopwatch()..start();
    final audioPath = await generateAudioIntelligent(text);
    if (audioPath != null) {
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
  Future<String?> generateAndOptionallyPlayAudio(String text,
      {bool autoPlay = true}) async {
    final stopwatch = Stopwatch()..start();
    final audioPath = await generateAudioIntelligent(text);
    if (audioPath != null) {
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
  String _getAudioFilePath(String fileName) {
    return p.join(PathManager.instance.cacheDir, fileName);
  }
  String _generateIntelligentCacheKey(String text) {
    final textHash = text.hashCode.abs().toString();
    final timestamp =
        DateTime.now().millisecondsSinceEpoch ~/ (1000 * 60 * 60); // Hour-based
    return 'local_${textHash}_$timestamp';
  }
  Future<String?> generateAudioIntelligent(String text,
      {bool isAiSpeaking = true}) async {
    if (!_isInitialized) {
      await initializeOnlyIfNeeded();
    }
    final stopwatch = Stopwatch()..start();
    final cacheKey = _generateIntelligentCacheKey(text);
    if (_intelligentCache.containsKey(cacheKey)) {
      final cachedPath = _intelligentCache[cacheKey]!;
      if (await io.File(cachedPath).exists()) {
        log.i(
            'INTELLIGENT CACHE HIT for key: $cacheKey (~1-10ms access maintained!)');
        stopwatch.stop();
        _performanceMetrics['fetch_intelligent_cached'] =
            stopwatch.elapsedMilliseconds;
        return cachedPath;
      } else {
        _intelligentCache.remove(cacheKey);
        log.w('Removed dead cache entry for key: $cacheKey');
      }
    }
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
  Future<String?> generateAudio(String text, {bool isAiSpeaking = true}) async {
    if (!_isInitialized) {
      await initializeOnlyIfNeeded();
    }
    final stopwatch = Stopwatch()..start();
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
        log.d(
            'Using direct TTS calls (${LLMConfig.activeTTSProvider} - ${LLMConfig.activeTTSModelId})');
        audioPath = await generateAudioDirect(text, isAiSpeaking: isAiSpeaking);
      } else {
        audioPath =
            await _generateAudioViaBackend(text, isAiSpeaking: isAiSpeaking);
      }
      if (audioPath != null) {
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
  Future<String?> _generateAudioViaBackend(String text,
      {bool isAiSpeaking = true}) async {
    try {
      final generationStopwatch = Stopwatch()..start();
      final completer = Completer<String?>();
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
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      filePath = _getAudioFilePath('tts_audio_$timestamp.wav');
      return filePath;
    } catch (e) {
      log.e('Error generating audio via TTSService', e);
      return null;
    }
  }
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
  Future<void> stopAudio() async {
    try {
      await _ttsService.stopAudio();
    } catch (e) {
      log.e('Error stopping audio', e);
    }
  }
  void clearCache() {
    _audioCache.clear();
    log.i('Audio cache cleared');
  }
  Map<String, int> getPerformanceMetrics() {
    return Map.from(_performanceMetrics);
  }
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
  Future<String?> generateAndStreamAudio(
    String text, {
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (_audioCache.containsKey(text)) {
      final cachedAudioPath = _audioCache[text]!;
      log.i(
          'Using cached audio for text: "${text.substring(0, min(20, text.length))}..." Path: $cachedAudioPath');
      final playStopwatch = Stopwatch()..start();
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
    log.i(
        'Audio not cached for: "${text.substring(0, min(20, text.length))}...". Generating via TTSStreamingService.');
    final genStopwatch = Stopwatch()..start();
    String? audioPath;
    try {
      audioPath = await _generateAudioViaBackend(text, isAiSpeaking: true);
      genStopwatch.stop();
      _performanceMetrics['generate_audio_via_tts_service'] =
          genStopwatch.elapsedMilliseconds;
      if (audioPath != null) {
        onDone?.call(); // Audio was already played during generation
      } else {
        onError?.call('Failed to generate audio file');
      }
    } catch (e) {
      genStopwatch.stop();
      log.e('Error calling TTSStreamingService: $e');
      onError?.call('Failed during TTS generation: ${e.toString()}');
    }
    if (audioPath != null) {
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
  Future<String?> generateAudioDirect(String text,
      {bool isAiSpeaking = true}) async {
    try {
      final ttsConfig = LLMConfig.currentTTSConfig;
      final apiKey = await _getApiKeyForProvider(ttsConfig.apiKeyEnvVar);
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API key not found for ${ttsConfig.apiKeyEnvVar}');
      }
      final headers = Map<String, String>.from(ttsConfig.headers);
      headers['Authorization'] = 'Bearer $apiKey';
      final body = _buildTTSRequestBody(ttsConfig, text, isAiSpeaking);
      final response = await http.post(
        Uri.parse(ttsConfig.endpoint),
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final audioBytes = response.bodyBytes;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final audioFileName = 'direct_tts_$timestamp.mp3';
        final audioFile = io.File(_getAudioFilePath(audioFileName));
        await audioFile.writeAsBytes(audioBytes);
        return audioFile.path;
      } else {
        throw Exception(
            'TTS API call failed with status: ${response.statusCode}');
      }
    } catch (e) {
      return null;
    }
  }
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
        return _buildOpenAITTSBody(config, text, isAiSpeaking);
      default:
        return _buildOpenAITTSBody(config, text, isAiSpeaking);
    }
  }
  Map<String, dynamic> _buildOpenAITTSBody(
    TTSModelConfig config,
    String text,
    bool isAiSpeaking,
  ) {
    String voice = config.voice ?? LLMConfig.activeTTSVoice;
    final body = {
      'model': config.modelId,
      'input': text,
      'voice': voice,
      ...config.defaultParams,
    };
    return body;
  }
  Future<String?> _getApiKeyForProvider(String envVarName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(envVarName);
    } catch (e) {
      return null;
    }
  }
  int getCacheSize() {
    return _audioCache.length;
  }
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
        detector.addChunk(chunk);
        List<String> sentences = useTherapeuticProcessing
            ? detector.extractTherapeuticSentences()
            : detector.extractCompleteSentences();
        for (String sentence in sentences) {
          final audioTask =
              _generateSentenceTTS(sentence, onAudioReady, onError);
          audioGenerationTasks.add(audioTask);
        }
      }
      final remaining = detector.flushRemaining();
      if (remaining != null) {
        final audioTask =
            _generateSentenceTTS(remaining, onAudioReady, onError);
        audioGenerationTasks.add(audioTask);
      }
      await Future.wait(audioGenerationTasks);
      onDone();
    } catch (e) {
      log.e('Error in streaming TTS generation', e);
      onError('Error in streaming TTS: ${e.toString()}');
    }
  }
  Future<void> _generateSentenceTTS(
    String sentence,
    void Function(String audioPath) onAudioReady,
    void Function(String error) onError,
  ) async {
    try {
      if (_intelligentCache.containsKey(sentence)) {
        final cachedPath = _intelligentCache[sentence]!;
        if (await io.File(cachedPath).exists()) {
          onAudioReady(cachedPath);
          return;
        }
      }
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
    await generateStreamingTTS(
      textStream: textStream,
      useTherapeuticProcessing: useTherapeuticProcessing,
      onAudioReady: (audioPath) async {
        audioQueue.add(audioPath);
        if (!isPlaying) {
          isPlaying = true;
          _playAudioQueue(audioQueue, onFirstAudioStart, onAllAudioComplete,
              onError, firstAudioStarted);
          firstAudioStarted = true;
        }
      },
      onDone: () {
        log.i('Text streaming complete, waiting for audio queue to finish');
      },
      onError: onError,
    );
  }
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
    _ttsStateCallback?.call(false);
    onAllAudioComplete();
  }
  Stream<String> createTextStreamFromWebSocket(
      Stream<Map<String, dynamic>> webSocketStream) async* {
    await for (final event in webSocketStream) {
      if (event['type'] == 'chunk' && event.containsKey('content')) {
        yield event['content'] as String;
      } else if (event['type'] == 'error') {
        log.e('WebSocket error in text stream: ${event['detail']}');
        throw Exception('WebSocket error: ${event['detail']}');
      }
    }
  }
  Future<void> processAIResponseWithStreamingTTS({
    required Stream<Map<String, dynamic>> aiResponseStream,
    required void Function() onTTSStart,
    required void Function() onTTSComplete,
    required void Function(String error) onError,
    bool useTherapeuticProcessing = false,
  }) async {
    try {
      final textStream = createTextStreamFromWebSocket(aiResponseStream);
      final completeText = StringBuffer();
      bool hasStarted = false;
      await for (final chunk in textStream) {
        completeText.write(chunk);
        if (!hasStarted && completeText.length > 10) {
          hasStarted = true;
          _ttsStateCallback?.call(true);
          onTTSStart();
        }
      }
      _ttsStateCallback?.call(true);
      await _ttsService.speak(completeText.toString(), makeBackupFile: false);
      log.i('🎵 TTS streaming completed with simplified API');
      onTTSComplete();
    } catch (e) {
      log.e('Error processing AI response with streaming TTS', e);
      onError('Failed to process AI response: ${e.toString()}');
    }
  }
  void setTTSStateCallback(void Function(bool isSpeaking)? callback) {
    _ttsStateCallback = callback;
    if (_ttsService is SimpleTTSService) {
      final simpleTTSService = _ttsService as SimpleTTSService;
      simpleTTSService.setCompletionCallback(callback);
    }
  }
  void setVADCallbacks({
    Future<void> Function()? pauseCallback,
    Future<void> Function()? resumeCallback,
  }) {
  }
  void dispose() {
    clearCache();
  }
}
