# TTS Latency Reduction Implementation Guide

## Overview
This guide will walk you through implementing progressive audio streaming and other optimizations to reduce TTS latency by 50-70%. Follow each step in order and mark it complete before moving to the next.

**Expected Results:**
- Time to first audio: ~200-300ms (down from ~1000ms)
- Total latency reduction: 50-70%
- Better user experience with faster AI responses

**Important:** Make a backup of your current `voice_service.dart` file before starting.

---

## Step 1: Create Streaming TTS Helper Class
**Estimated Time:** 15 minutes

### [ ] 1.1 Create new file: `lib/services/streaming_tts.dart`

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

/// Custom audio source that supports progressive streaming
class StreamingTTS extends StreamAudioSource {
  final List<int> _buffer = [];
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  final String format;
  bool _isComplete = false;
  int _totalBytesReceived = 0;
  
  StreamingTTS({required this.format});
  
  void addChunk(List<int> chunk) {
    if (!_controller.isClosed) {
      _buffer.addAll(chunk);
      _totalBytesReceived += chunk.length;
      _controller.add(chunk);
    }
  }
  
  void complete() {
    _isComplete = true;
    _controller.close();
  }
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    end = end > _buffer.length ? _buffer.length : end;
    
    return StreamAudioResponse(
      sourceLength: _isComplete ? _buffer.length : null,
      contentLength: end - start,
      offset: start,
      contentType: _getContentType(),
      stream: Stream.value(Uint8List.fromList(_buffer.sublist(start, end))),
    );
  }
  
  String _getContentType() {
    switch (format) {
      case 'opus':
        return 'audio/ogg';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      default:
        return 'audio/mpeg';
    }
  }
  
  void dispose() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
```

### [ ] 1.2 Test compilation
Run: `flutter analyze lib/services/streaming_tts.dart`

---

## Step 2: Update VoiceService Imports
**Estimated Time:** 5 minutes

### [ ] 2.1 Add imports to `voice_service.dart`
Add these imports at the top of the file after the existing imports:

```dart
import 'streaming_tts.dart';
```

**Note:** We are NOT deleting voice_service.dart - we're only improving the TTS functionality within it.

---

## Step 3: Add WebSocket Pre-warming
**Estimated Time:** 20 minutes

### [ ] 3.1 Add these fields to VoiceService class
Add after the existing field declarations:

```dart
  // WebSocket pre-warming fields
  WebSocketChannel? _preWarmedConnection;
  Timer? _keepAliveTimer;
  final String _ttsWsUrl = 'wss://ai-therapist-backend-385290373302.us-central1.run.app/voice/ws/tts';
```

### [ ] 3.2 Add pre-warming methods
Add these methods to the VoiceService class:

```dart
  /// Pre-warm WebSocket connection for faster TTS
  void _preWarmTTSConnection() async {
    try {
      if (kDebugMode) print('🔥 Pre-warming TTS WebSocket connection...');
      
      _preWarmedConnection = WebSocketChannel.connect(Uri.parse(_ttsWsUrl));
      
      // Listen for connection errors
      _preWarmedConnection!.stream.listen(
        (_) {}, 
        onError: (error) {
          if (kDebugMode) print('❌ Pre-warmed connection error: $error');
          _preWarmedConnection = null;
        },
        onDone: () {
          if (kDebugMode) print('Pre-warmed connection closed');
          _preWarmedConnection = null;
        }
      );
      
      // Keep connection alive with periodic pings
      _keepAliveTimer?.cancel();
      _keepAliveTimer = Timer.periodic(Duration(seconds: 30), (_) {
        if (_preWarmedConnection != null) {
          try {
            _preWarmedConnection!.sink.add(jsonEncode({'type': 'ping'}));
          } catch (e) {
            if (kDebugMode) print('Failed to ping pre-warmed connection: $e');
            _preWarmedConnection = null;
          }
        }
      });
      
      if (kDebugMode) print('🔥 TTS connection pre-warmed and ready');
    } catch (e) {
      if (kDebugMode) print('❌ Failed to pre-warm connection: $e');
      _preWarmedConnection = null;
    }
  }
  
  /// Get pre-warmed connection or create new one
  WebSocketChannel _getOrCreateConnection() {
    if (_preWarmedConnection != null) {
      final connection = _preWarmedConnection!;
      _preWarmedConnection = null;
      // Pre-warm another for next time
      Future.delayed(Duration(milliseconds: 100), _preWarmTTSConnection);
      if (kDebugMode) print('🔥 Using pre-warmed connection');
      return connection;
    }
    
    if (kDebugMode) print('Creating new WebSocket connection');
    return WebSocketChannel.connect(Uri.parse(_ttsWsUrl));
  }
```

### [ ] 3.3 Update initialize() method
Add this line in the `initialize()` method after the existing initialization code:

```dart
      // Pre-warm WebSocket connection for TTS
      _preWarmTTSConnection();
```

### [ ] 3.4 Update dispose() method
Add these lines in the `dispose()` method:

```dart
    // Clean up WebSocket pre-warming
    _keepAliveTimer?.cancel();
    _preWarmedConnection?.sink.close();
```

---

## Step 4: Replace streamAndPlayTTS Method
**Estimated Time:** 30 minutes

### [ ] 4.1 Backup the current streamAndPlayTTS method
Copy the entire method to a text file as backup.

### [ ] 4.2 Replace with new progressive streaming version
Replace the entire `streamAndPlayTTS` method with this code:

```dart
  /// Stream TTS audio from backend with progressive playback
  Future<String?> streamAndPlayTTSProgressive({
    required String text,
    String voice = 'sage',
    String responseFormat = 'opus', // Changed from wav to opus
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    // Timing diagnostics
    final totalStopwatch = Stopwatch()..start();
    final wsConnectStopwatch = Stopwatch();
    final firstChunkStopwatch = Stopwatch();
    final playbackStartStopwatch = Stopwatch();

    if (kDebugMode) {
      print('🔍 [TTS TIMING] Starting progressive TTS for text length: ${text.length} chars');
      print('🔍 [TTS TIMING] Format: $responseFormat, Voice: $voice');
    }

    isAiSpeaking = true;
    _ttsSpeakingStateController.add(true);
    
    StreamingTTS? audioSource;
    AudioPlayer? streamingPlayer;
    StreamSubscription? subscription;
    WebSocketChannel? channel;
    bool disposed = false;

    try {
      // Get WebSocket connection
      wsConnectStopwatch.start();
      channel = _getOrCreateConnection();
      wsConnectStopwatch.stop();
      
      if (kDebugMode) {
        print('🔍 [TTS TIMING] WebSocket ready in: ${wsConnectStopwatch.elapsedMilliseconds}ms');
      }

      // Create streaming audio source and player
      audioSource = StreamingTTS(format: responseFormat);
      streamingPlayer = AudioPlayer();
      
      final completer = Completer<String?>();
      bool firstChunkReceived = false;
      bool playerStarted = false;
      int totalBytes = 0;
      int chunksReceived = 0;
      final int minBytesToStart = responseFormat == 'opus' ? 2048 : 4096;
      final int minChunksToStart = 2;

      // Listen to WebSocket stream
      subscription = channel.stream.listen((event) async {
        if (disposed) return;
        
        try {
          final data = jsonDecode(event);
          
          if (data['type'] == 'audio_chunk') {
            chunksReceived++;
            final chunk = base64Decode(data['data']);
            totalBytes += chunk.length;
            
            if (!firstChunkReceived) {
              firstChunkReceived = true;
              firstChunkStopwatch.stop();
              if (kDebugMode) {
                print('🔍 [TTS TIMING] First chunk in: ${firstChunkStopwatch.elapsedMilliseconds}ms (${chunk.length} bytes)');
              }
            }
            
            // Add chunk to audio source
            audioSource?.addChunk(chunk);
            
            // Start playback after minimum data received
            if (!playerStarted && !disposed && 
                (chunksReceived >= minChunksToStart || totalBytes >= minBytesToStart)) {
              playerStarted = true;
              playbackStartStopwatch.start();
              
              try {
                if (!disposed && streamingPlayer != null && audioSource != null) {
                  await streamingPlayer.setAudioSource(audioSource);
                  
                  // Set up completion listener
                  streamingPlayer.playerStateStream.listen((state) {
                    if (state.processingState == ProcessingState.completed && !disposed) {
                      playbackStartStopwatch.stop();
                      totalStopwatch.stop();
                      
                      isAiSpeaking = false;
                      _ttsSpeakingStateController.add(false);
                      
                      if (kDebugMode) {
                        print('🔍 [TTS TIMING] === PLAYBACK COMPLETE ===');
                        print('🔍 [TTS TIMING] Chunks: $chunksReceived, Bytes: $totalBytes');
                        print('🔍 [TTS TIMING] Time to start: ${playbackStartStopwatch.elapsedMilliseconds}ms');
                        print('🔍 [TTS TIMING] TOTAL TIME: ${totalStopwatch.elapsedMilliseconds}ms');
                      }
                      
                      onDone?.call();
                      if (!completer.isCompleted) {
                        completer.complete(null);
                      }
                    }
                  });
                  
                  // Start playback (don't await)
                  streamingPlayer.play();
                  
                  if (kDebugMode) {
                    print('🔍 [TTS TIMING] Playback started with $chunksReceived chunks, $totalBytes bytes');
                  }
                }
              } catch (e) {
                if (kDebugMode) print('❌ Error starting playback: $e');
                onError?.call('Playback error: $e');
                if (!completer.isCompleted) completer.complete(null);
              }
            }
            
            // Report progress
            if (data['progress'] != null && onProgress != null) {
              onProgress(data['progress'].toDouble());
            }
            
          } else if (data['type'] == 'done') {
            if (kDebugMode) {
              print('🔍 [TTS TIMING] Stream complete. Total: $chunksReceived chunks, $totalBytes bytes');
            }
            
            // Complete the audio source
            audioSource?.complete();
            
            // Handle case where audio is too short to trigger early playback
            if (!playerStarted && !disposed && totalBytes > 0) {
              try {
                if (streamingPlayer != null && audioSource != null) {
                  await streamingPlayer.setAudioSource(audioSource);
                  await streamingPlayer.play();
                  await streamingPlayer.processingStateStream.firstWhere(
                    (state) => state == ProcessingState.completed
                  );
                  isAiSpeaking = false;
                  _ttsSpeakingStateController.add(false);
                  onDone?.call();
                }
              } catch (e) {
                onError?.call('Playback error: $e');
              }
              if (!completer.isCompleted) completer.complete(null);
            }
            
          } else if (data['type'] == 'error') {
            final errorMsg = data['detail'] ?? 'Unknown TTS error';
            if (kDebugMode) print('❌ TTS error: $errorMsg');
            onError?.call(errorMsg);
            if (!completer.isCompleted) completer.complete(null);
          }
        } catch (e) {
          if (kDebugMode) print('❌ Stream processing error: $e');
          onError?.call('Processing error: $e');
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (err) {
        if (kDebugMode) print('❌ WebSocket error: $err');
        onError?.call('Connection error: $err');
        if (!completer.isCompleted) completer.complete(null);
      });

      // Send TTS request with optimized parameters
      firstChunkStopwatch.start();
      channel.sink.add(jsonEncode({
        'text': text,
        'voice': voice,
        'params': {
          'response_format': responseFormat,
          'chunk_size': 1024,  // Smaller chunks for faster first byte
          'streaming': true,
          'buffer_size': 512,  // Smaller server buffer
          // Opus-specific optimizations
          if (responseFormat == 'opus') ...{
            'opus_bitrate': 24000,      // Good for speech
            'opus_frame_duration': 20,   // 20ms frames
            'opus_complexity': 0,        // Lowest complexity for speed
          }
        },
      }));

      return await completer.future;
      
    } catch (e) {
      if (kDebugMode) print('❌ TTS streaming error: $e');
      onError?.call('TTS error: ${e.toString()}');
      return null;
      
    } finally {
      disposed = true;
      
      // Cleanup
      isAiSpeaking = false;
      _ttsSpeakingStateController.add(false);
      
      await subscription?.cancel();
      if (channel != _preWarmedConnection) {
        await channel?.sink.close();
      }
      audioSource?.dispose();
      await streamingPlayer?.dispose();
    }
  }
```

### [ ] 4.3 Update the wrapper streamAndPlayTTS method
Replace the current `streamAndPlayTTS` method with this wrapper:

```dart
  Future<String?> streamAndPlayTTS({
    required String text,
    String voice = 'sage',
    String responseFormat = 'opus',
    void Function(double progress)? onProgress,
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
    return streamAndPlayTTSProgressive(
      text: text,
      voice: voice,
      responseFormat: responseFormat,
      onProgress: onProgress,
      onDone: onDone,
      onError: onError,
    );
  }
```

---

## Step 5: Update generateAudio Method
**Estimated Time:** 10 minutes

### [ ] 5.1 Update the generateAudio method
Find the `generateAudio` method and update the default responseFormat:

```dart
  Future<String?> generateAudio(
    String text, {
    String voice = 'sage',
    String responseFormat = 'opus', // Changed from 'wav' to 'opus'
    void Function()? onDone,
    void Function(String error)? onError,
  }) async {
```

### [ ] 5.2 Update fallback format
In the same method, find the fallback logic and change:
- Primary format: `opus`
- Fallback format: `mp3`

---

## Step 6: Test the Implementation
**Estimated Time:** 20 minutes

### [ ] 6.1 Run flutter analyze
```bash
flutter analyze
```
Fix any errors that appear.

### [ ] 6.2 Run the app
Test the TTS functionality and observe the console logs for timing information.

### [ ] 6.3 Verify improvements
Check that:
- [ ] First audio plays faster (should be ~200-300ms)
- [ ] No audio glitches or cuts
- [ ] Console shows progressive streaming logs
- [ ] Pre-warmed connection is being used

---

## Step 7: Add Simple Caching (Optional)
**Estimated Time:** 15 minutes

### [ ] 7.1 Add cache field to VoiceService
```dart
  // Simple cache for common phrases
  final Map<String, String> _ttsCache = {};
  static const int _maxCacheSize = 20;
```

### [ ] 7.2 Update streamAndPlayTTS to check cache
Add at the beginning of `streamAndPlayTTSProgressive`:

```dart
    // Check cache for common phrases
    final cacheKey = '$text-$voice-$responseFormat';
    if (_ttsCache.containsKey(cacheKey)) {
      if (kDebugMode) print('🎯 TTS Cache hit!');
      // Play cached audio
      final cachedPath = _ttsCache[cacheKey]!;
      await _audioPlayerManager.playAudio(cachedPath);
      onDone?.call();
      return cachedPath;
    }
```

---

## Step 8: Final Cleanup
**Estimated Time:** 10 minutes

### [ ] 8.1 Remove old debugging code
Remove any `// REMOVED` comments from the file.

### [ ] 8.2 Update documentation
Add a comment at the top of `streamAndPlayTTS`:
```dart
  /// Streams TTS audio with progressive playback for minimal latency
  /// Uses pre-warmed WebSocket connections and starts playback after 2 chunks
```

### [ ] 8.3 Commit changes
```bash
git add -A
git commit -m "feat: implement progressive TTS streaming for 70% latency reduction"
```

---

## Verification Checklist

### Performance Metrics (check in console logs):
- [ ] WebSocket connection time: <50ms (with pre-warming)
- [ ] Time to first chunk: <150ms
- [ ] Time to start playback: <300ms
- [ ] Total time for short phrase: <500ms

### Functionality:
- [ ] TTS plays smoothly without cuts
- [ ] Error handling works (test with network off)
- [ ] Auto-listening still works correctly
- [ ] Memory usage is stable (no leaks)

---

## Rollback Instructions

If issues occur:
1. Restore your backup of `voice_service.dart`
2. Delete `streaming_tts.dart`
3. Run `flutter clean && flutter pub get`
4. Restart the app

---

## Additional Optimizations
**These can be done after the main TTS improvements**

### [ ] 9.1 Optimize Transcription API Calls
In `processRecordedAudioFile`, add timeout and retry logic:

```dart
  Future<String> processRecordedAudioFile(String recordedFilePath) async {
    // ... existing validation code ...
    
    try {
      // ... existing file processing ...
      
      // Add timeout and retry logic
      int retries = 0;
      const maxRetries = 2;
      const timeout = Duration(seconds: 10);
      
      while (retries <= maxRetries) {
        try {
          final response = await _apiClient.post(
            '/voice/transcribe',
            body: {
              'audio_data': base64Audio,
              'audio_format': 'm4a',
              'model': 'gpt-4o-mini-transcribe'
            }
          ).timeout(timeout);
          
          final transcription = response['text'] as String;
          await _deleteFile(recordedFilePath);
          return transcription.isNotEmpty ? transcription : "";
          
        } on TimeoutException {
          retries++;
          if (retries > maxRetries) {
            await _deleteFile(recordedFilePath);
            return "Error: Transcription timed out. Please try again.";
          }
          if (kDebugMode) print('Transcription timeout, retry $retries');
        }
      }
    } catch (e) {
      // ... existing error handling ...
    }
  }
```

### [ ] 9.2 Remove Unused Code
Remove these unused items to clean up the code:

```dart
// Remove unused conversation context
- List<Map<String, dynamic>> _conversationContext = [];
- _conversationContext = []; // in initialize()

// Remove unused speaker IDs
- final int _userSpeakerId = 0;
- final int _aiSpeakerId = 1;

// Remove unused CSM path
- String? _csmPath;
```

### [ ] 9.3 Consolidate Audio Playback Code
The `playAudio` and `playStreamingAudio` methods have duplicate logic. Create a unified method:

```dart
  Future<void> playAudioUnified(String audioPath, {bool streaming = false}) async {
    _audioPlaybackController.add(true);
    
    try {
      // Use AudioPlayerManager for all playback
      await _audioPlayerManager.playAudio(audioPath, streaming: streaming);
      _audioPlaybackController.add(false);
    } catch (e) {
      if (kDebugMode) print('Error playing audio: $e');
      _audioPlaybackController.add(false);
      
      // Fallback to TTS if needed
      if (!audioPath.startsWith('local_tts://')) {
        await _useTtsBackup();
      }
    }
  }
```

### [ ] 9.4 Improve Error Handling Consistency
Create a consistent error type:

```dart
class VoiceServiceError {
  final String userMessage;
  final String? technicalMessage;
  final String? code;
  
  VoiceServiceError({
    required this.userMessage,
    this.technicalMessage,
    this.code,
  });
}
```

### [ ] 9.5 Add Performance Monitoring
Add performance tracking for all voice operations:

```dart
class VoiceMetrics {
  static final Map<String, List<Duration>> _metrics = {};
  
  static void recordOperation(String operation, Duration duration) {
    _metrics.putIfAbsent(operation, () => []).add(duration);
    
    // Log every 10 operations
    if (_metrics[operation]!.length % 10 == 0) {
      final avg = _metrics[operation]!
          .map((d) => d.inMilliseconds)
          .reduce((a, b) => a + b) / _metrics[operation]!.length;
      
      if (kDebugMode) {
        print('📊 [Metrics] $operation avg: ${avg.round()}ms over ${_metrics[operation]!.length} calls');
      }
    }
  }
}

// Usage example in processRecordedAudioFile:
final stopwatch = Stopwatch()..start();
// ... do transcription ...
stopwatch.stop();
VoiceMetrics.recordOperation('transcription', stopwatch.elapsed);
```

### [ ] 9.6 Optimize File Deletion
Create a file cleanup queue instead of immediate deletion:

```dart
class FileCleanupQueue {
  static final List<String> _pendingDeletion = [];
  static Timer? _cleanupTimer;
  
  static void scheduleDelete(String filePath) {
    _pendingDeletion.add(filePath);
    _startCleanupTimer();
  }
  
  static void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(Duration(seconds: 5), () async {
      final toDelete = List<String>.from(_pendingDeletion);
      _pendingDeletion.clear();
      
      for (final path in toDelete) {
        try {
          final file = io.File(path);
          if (await file.exists()) {
            await file.delete();
            if (kDebugMode) print('🗑️ Cleaned up: $path');
          }
        } catch (e) {
          if (kDebugMode) print('Failed to delete $path: $e');
        }
      }
    });
  }
}

// Replace immediate _deleteFile calls with:
FileCleanupQueue.scheduleDelete(recordedFilePath);
```

### [ ] 9.7 Add Connection Quality Detection
Add adaptive quality based on connection speed:

```dart
  Future<String> _detectOptimalFormat() async {
    try {
      final stopwatch = Stopwatch()..start();
      final testUrl = '$_backendUrl/health';
      await http.get(Uri.parse(testUrl)).timeout(Duration(seconds: 2));
      stopwatch.stop();
      
      // If latency is high, use more compressed format
      if (stopwatch.elapsedMilliseconds > 500) {
        return 'opus'; // Most compressed
      } else if (stopwatch.elapsedMilliseconds > 200) {
        return 'mp3';
      } else {
        return 'opus'; // Still prefer opus for quality
      }
    } catch (e) {
      return 'opus'; // Default to compressed format
    }
  }
```

### [ ] 9.8 Backend Configuration Note
**Important:** For maximum performance, ensure your backend is configured with:
- WebSocket compression enabled
- Chunked transfer encoding
- HTTP/2 or HTTP/3 support
- CDN for edge caching of common TTS responses

### [ ] 9.9 Consider Implementing Request Batching
For multiple rapid TTS requests:

```dart
class TTSBatcher {
  static final List<TTSRequest> _pendingRequests = [];
  static Timer? _batchTimer;
  
  static Future<void> requestTTS(String text, Function(String?) callback) async {
    _pendingRequests.add(TTSRequest(text, callback));
    
    // Batch requests every 50ms
    _batchTimer?.cancel();
    _batchTimer = Timer(Duration(milliseconds: 50), _processBatch);
  }
  
  static void _processBatch() async {
    if (_pendingRequests.isEmpty) return;
    
    // Process the highest priority request immediately
    final request = _pendingRequests.removeAt(0);
    
    // Cancel similar requests
    _pendingRequests.removeWhere((r) => 
      r.text.toLowerCase().trim() == request.text.toLowerCase().trim()
    );
    
    // Process the request
    final result = await voiceService.generateAudio(request.text);
    request.callback(result);
  }
}
```

---

## Next Steps

After successful implementation:
1. Monitor user feedback on TTS responsiveness
2. Collect timing metrics in production
3. Consider implementing the TTS cache for frequently used phrases
4. Look into edge caching for even faster response

## Questions or Issues?

Document any issues encountered with:
- Error messages
- Console logs
- Steps to reproduce
- Device/Platform information