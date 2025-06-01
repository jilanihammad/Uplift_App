# True Streaming Architecture Implementation Plan (REVISED v2)
## LLM → TTS → Client Real-Time Pipeline

### 🎯 **Goal**
Transform current architecture from:
- ❌ **Current:** LLM (3s) → Full Response → TTS (2s) → Stream Audio = **~5s to first audio**
- ✅ **Target:** LLM chunk → TTS immediately → Audio stream = **~300-400ms to first audio**

### 📊 **Performance Targets (REVISED)**
- **Time to First Audio:** 300-400ms (vs current 3-5s) - **85-90% faster**
- **Total Response Time:** 70-80% improvement
- **User Experience:** Audio starts while AI is still "thinking"
- **Audio Quality:** No prosody breaks, consistent voice timbre

### 🔄 **PARALLEL DEVELOPMENT STRATEGY** ⭐ **CRITICAL SUCCESS FACTOR**

### **🚨 Risk Mitigation: Frontend Integration Bottleneck**
**Problem:** Sequential backend-then-frontend development creates a 6-8 week bottleneck and risks missing the 300-400ms target entirely.

**Solution:** Parallel development with mock server and clear coordination points.

### **📅 Revised Timeline: Parallel Tracks**

#### **Backend Track (Week 1-3)**
- **Week 1:** Steps 1-3 (Text Processing, Pipeline, LLM Producer)  
- **Week 2:** Steps 4-5 (TTS Processor, Client Sender)
- **Week 3:** Step 6 (WebSocket Endpoint) ⭐ **FRONTEND HANDOFF POINT**

#### **Frontend Track (Week 2-4)**  
- **Week 2:** Mock server development + Frontend Step 1 (WebSocket client)
- **Week 3:** Frontend Steps 2-3 (Debouncing fix, Audio streaming) 
- **Week 4:** Integration testing with real backend + Device testing

#### **🔗 Coordination Checkpoints**
1. **Day 3:** Mock WebSocket server spec finalized
2. **Day 10:** Backend Step 6 ready → Frontend integration begins  
3. **Day 17:** End-to-end testing with real backend
4. **Day 21:** SM S938U1 device validation

---

## 🎭 **MOCK WEBSOCKET SERVER SPECIFICATION**

### **Purpose:** Unblock frontend development while backend progresses

### **Mock Endpoint:** `/api/v1/voice/ws/tts/streaming/mock`

### **Mock Server Behavior:**
```python
# Mock streaming response simulation
import asyncio
import json

async def mock_streaming_endpoint(websocket, path):
    """Mock WebSocket server for frontend development"""
    
    # 1. Send initial format discovery frame
    init_frame = {
        "type": "init",
        "audio_format": "pcm_16000",
        "chunk_size_ms": 100,
        "jitter_buffer_size": 3,
        "expected_latency_ms": 350
    }
    await websocket.send(json.dumps(init_frame))
    
    # 2. Simulate real-time audio chunk streaming
    sentence_id = 1
    chunk_id = 0
    
    # Mock: 5 sentences, each with 4-6 audio chunks
    for sentence in range(5):
        chunks_in_sentence = 4 + (sentence % 3)  # 4-6 chunks
        
        for chunk in range(chunks_in_sentence):
            # Simulate realistic 80-120ms delays between chunks
            await asyncio.sleep(0.1)  # 100ms
            
            audio_chunk = {
                "type": "audio",
                "sentence_id": sentence_id,
                "chunk_id": chunk_id,
                "is_sentence_end": chunk == chunks_in_sentence - 1,
                "sequence": chunk_id,
                "audio_data": "base64_mock_audio_data_here",
                "timestamp": asyncio.get_event_loop().time()
            }
            
            await websocket.send(json.dumps(audio_chunk))
            chunk_id += 1
        
        sentence_id += 1
    
    # 3. Send completion frame
    completion_frame = {
        "type": "complete",
        "total_chunks": chunk_id,
        "total_sentences": sentence_id - 1
    }
    await websocket.send(json.dumps(completion_frame))
```

### **Mock Audio Data Generation:**
```python
# Generate realistic mock PCM audio data
import base64
import numpy as np

def generate_mock_audio_chunk(duration_ms=100, sample_rate=16000):
    """Generate mock PCM audio data for testing"""
    samples = int(duration_ms * sample_rate / 1000)
    
    # Generate sine wave with some noise (simulates speech)
    t = np.linspace(0, duration_ms/1000, samples)
    frequency = 440 + np.random.random() * 200  # 440-640 Hz range
    audio = np.sin(2 * np.pi * frequency * t) * 0.3
    audio += np.random.normal(0, 0.1, samples)  # Add noise
    
    # Convert to 16-bit PCM
    audio_int16 = (audio * 32767).astype(np.int16)
    return base64.b64encode(audio_int16.tobytes()).decode()
```

---

## 🛠️ **DETAILED FRONTEND FIXES**

### **🔴 Fix 1: Debouncing Solution for Duplicate Calls** ✅ **CRITICAL**

**Problem:** Bloc listener firing 2-3x per recording session
```dart
// ❌ WRONG - Fires on multiple state transitions
_recordingStateSub = voiceService.recordingState.listen((recState) {
  add(SetRecordingState(isRecording)); // Fires 2-3x per recording!
});
```

**Solution:** RxDart debouncing with state validation
```dart
// ✅ FIXED - Debounce state transitions to prevent duplicate calls
import 'package:rxdart/rxdart.dart';

class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  StreamSubscription? _recordingStateSub;
  bool _lastRecordingState = false;  // Track state changes
  
  VoiceSessionBloc() : super(VoiceSessionInitial()) {
    // Debounced listener with state validation
    _recordingStateSub = voiceService.recordingState
        .debounceTime(Duration(milliseconds: 100))
        .distinct()  // Only emit when value actually changes
        .listen((recState) {
          // Additional validation to prevent duplicate calls
          if (recState != _lastRecordingState) {
            _lastRecordingState = recState;
            add(SetRecordingState(recState));
          }
        });
  }
  
  @override
  Future<void> close() {
    _recordingStateSub?.cancel();
    return super.close();
  }
}
```

### **🔴 Fix 2: Transcription Chunk Duration Validation** 🚨 **CRITICAL**

**Problem:** Audio chunks <0.1s cause backend transcription errors
**Solution:** Minimum 0.5s chunk duration with buffering

```dart
class AudioChunkValidator {
  static const int MIN_CHUNK_DURATION_MS = 500;  // 0.5s minimum
  static const int SAMPLE_RATE = 16000;
  static const int MIN_SAMPLES = MIN_CHUNK_DURATION_MS * SAMPLE_RATE ~/ 1000;
  
  List<int> _audioBuffer = [];
  DateTime? _chunkStartTime;
  
  /// Validates and buffers audio data to ensure minimum chunk duration
  List<int>? validateChunk(List<int> audioData) {
    // Initialize timing on first chunk
    _chunkStartTime ??= DateTime.now();
    
    // Add to buffer
    _audioBuffer.addAll(audioData);
    
    // Check duration criteria
    final duration = DateTime.now().difference(_chunkStartTime!);
    final hasMinDuration = duration.inMilliseconds >= MIN_CHUNK_DURATION_MS;
    final hasMinSamples = _audioBuffer.length >= MIN_SAMPLES;
    
    // Only release chunk if both criteria met
    if (hasMinDuration && hasMinSamples) {
      final validChunk = List<int>.from(_audioBuffer);
      _audioBuffer.clear();
      _chunkStartTime = DateTime.now();
      return validChunk;
    }
    
    // Continue buffering if chunk too short
    return null;
  }
  
  /// Force flush buffer (e.g., on recording end)
  List<int>? flushBuffer() {
    if (_audioBuffer.isNotEmpty) {
      final remainingChunk = List<int>.from(_audioBuffer);
      _audioBuffer.clear();
      _chunkStartTime = null;
      
      // Only return if meets minimum sample count
      return remainingChunk.length >= MIN_SAMPLES ? remainingChunk : null;
    }
    return null;
  }
}
```

### **🔴 Fix 3: Audio Recording Service with Chunk Validation**

**File:** `ai_therapist_app/lib/services/audio_recording_service.dart`
```dart
import 'package:record/record.dart';

class AudioRecordingService {
  final Record _recorder = Record();
  final AudioChunkValidator _chunkValidator = AudioChunkValidator();
  StreamController<List<int>>? _audioStreamController;
  Timer? _chunkTimer;
  
  Future<void> startRecording() async {
    try {
      _audioStreamController = StreamController<List<int>>.broadcast();
      
      // Start recording with stream
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      
      // Process audio chunks with validation
      stream.listen((audioData) {
        final validChunk = _chunkValidator.validateChunk(audioData);
        if (validChunk != null) {
          _audioStreamController?.add(validChunk);
        }
      });
      
      // Safety timer: force chunk every 2 seconds max
      _chunkTimer = Timer.periodic(Duration(seconds: 2), (_) {
        final forcedChunk = _chunkValidator.flushBuffer();
        if (forcedChunk != null) {
          _audioStreamController?.add(forcedChunk);
        }
      });
      
    } catch (e) {
      print('Recording start failed: $e');
    }
  }
  
  Future<void> stopRecording() async {
    try {
      // Flush any remaining audio
      final finalChunk = _chunkValidator.flushBuffer();
      if (finalChunk != null) {
        _audioStreamController?.add(finalChunk);
      }
      
      await _recorder.stop();
      _chunkTimer?.cancel();
      _audioStreamController?.close();
      
    } catch (e) {
      print('Recording stop failed: $e');
    }
  }
  
  Stream<List<int>>? get audioStream => _audioStreamController?.stream;
}
```

### **🔴 Fix 4: Backend Transcription Request with Duration Check**

```dart
class TranscriptionService {
  static const int MIN_AUDIO_DURATION_MS = 500;
  
  Future<String?> transcribeAudio(List<int> audioData) async {
    // Validate audio duration before sending to backend
    final durationMs = (audioData.length / 16000) * 1000;  // 16kHz sample rate
    
    if (durationMs < MIN_AUDIO_DURATION_MS) {
      print('Audio chunk too short: ${durationMs}ms < ${MIN_AUDIO_DURATION_MS}ms');
      return null;  // Skip transcription for short chunks
    }
    
    try {
      // Convert to base64 for API transmission
      final audioBytes = Int16List.fromList(audioData);
      final base64Audio = base64.encode(audioBytes.buffer.asUint8List());
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/voice/transcribe'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: json.encode({
          'audio_data': base64Audio,
          'sample_rate': 16000,
          'duration_ms': durationMs.round(),
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['transcription'];
      }
      
    } catch (e) {
      print('Transcription failed: $e');
    }
    
    return null;
  }
}
```

### **🔴 Fix 5: Streaming WebSocket Client Implementation**

**File:** `ai_therapist_app/lib/services/tts_streaming_service.dart`
```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

class TTSStreamingService {
  WebSocketChannel? _channel;
  final String baseUrl;
  bool _isConnected = false;
  
  TTSStreamingService({required this.baseUrl});
  
  Future<void> connect(String jwtToken) async {
    try {
      // Connect to streaming endpoint with JWT auth
      final uri = Uri.parse('$baseUrl/api/v1/voice/ws/tts/streaming');
      _channel = WebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $jwtToken'}
      );
      
      _isConnected = true;
      
      // Listen for incoming audio chunks
      _channel!.stream.listen(
        _handleIncomingMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );
      
    } catch (e) {
      print('WebSocket connection failed: $e');
      _isConnected = false;
    }
  }
  
  void _handleIncomingMessage(dynamic message) {
    final data = json.decode(message);
    
    switch (data['type']) {
      case 'init':
        _handleInitFrame(data);
        break;
      case 'audio':
        _handleAudioChunk(data);
        break;
      case 'complete':
        _handleCompletion(data);
        break;
    }
  }
  
  void _handleAudioChunk(Map<String, dynamic> chunk) {
    // Decode base64 audio data
    final audioBytes = base64.decode(chunk['audio_data']);
    
    // Queue for jitter buffer (implement based on sequence)
    _audioJitterBuffer.addChunk(
      AudioChunk(
        sentenceId: chunk['sentence_id'],
        chunkId: chunk['chunk_id'],
        sequence: chunk['sequence'],
        audioData: audioBytes,
        isSentenceEnd: chunk['is_sentence_end'],
      )
    );
  }
  
  Future<void> sendMessage(String message) async {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode({
        'type': 'text',
        'message': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
    }
  }
}
```

### **🔴 Fix 6: Audio Jitter Buffer Implementation**

```dart
class AudioJitterBuffer {
  final Queue<AudioChunk> _buffer = Queue();
  final int _maxBufferSize;
  int _expectedSequence = 0;
  
  AudioJitterBuffer({int maxSize = 3}) : _maxBufferSize = maxSize;
  
  void addChunk(AudioChunk chunk) {
    _buffer.add(chunk);
    _processBuffer();
  }
  
  void _processBuffer() {
    // Sort by sequence number and play in order
    final sortedChunks = _buffer.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    
    _buffer.clear();
    
    for (final chunk in sortedChunks) {
      if (chunk.sequence == _expectedSequence) {
        _playAudioChunk(chunk.audioData);
        _expectedSequence++;
      } else {
        _buffer.add(chunk);  // Re-queue out-of-order chunks
      }
    }
    
    // Prevent buffer overflow
    while (_buffer.length > _maxBufferSize) {
      final droppedChunk = _buffer.removeFirst();
      print('Dropped audio chunk: ${droppedChunk.sequence}');
    }
  }
}
```

---

## 🔗 **COORDINATION HANDOFF POINTS**

### **🎯 Checkpoint 1: Mock Server Ready (Day 3)**
**Backend Deliverable:** Mock WebSocket server specification  
**Frontend Action:** Begin WebSocket client development  
**Acceptance:** Frontend can connect and receive mock audio chunks

### **🎯 Checkpoint 2: Backend Step 6 Complete (Day 10)**  
**Backend Deliverable:** Real `/ws/tts/streaming` endpoint with JWT auth  
**Frontend Action:** Switch from mock to real backend  
**Acceptance:** End-to-end text → audio streaming works

### **🎯 Checkpoint 3: Integration Testing (Day 17)**
**Backend Deliverable:** Production-ready streaming pipeline  
**Frontend Action:** Complete audio streaming implementation  
**Acceptance:** <400ms latency achieved in controlled testing

### **🎯 Checkpoint 4: Device Validation (Day 21)**
**Combined Deliverable:** Validated on SM S938U1 device  
**Acceptance:** Real-world performance meets targets

### **🚨 CRITICAL: Audio Chunk Validation Requirements**
**Both Teams Must Implement:**
- ✅ **Minimum 0.5s transcription chunks** (prevents backend errors)
- ✅ **Duration validation** before API calls
- ✅ **Buffer management** for short audio segments
- ✅ **Safety timer** (2s max buffer retention)

---

### ⚠️ **Critical Engineering Fixes Incorporated** ❌ PENDING
Based on technical review, this plan addresses:
1. ❌ **Prosody-preserving chunking** using LLM pause tokens
2. ❌ **Persistent TTS connections** to eliminate per-sentence handshake overhead
3. ❌ **Audio sequencing** with jitter buffer support
4. ❌ **Backpressure management** with flow control
5. ❌ **Voice consistency** across sentence boundaries

### 🔧 **Last-Mile Production Fixes (Engineer Review)** ❌ PENDING
**CRITICAL fixes to prevent production heisenbugs:**
1. ❌ **Buffer Reset:** Prevent text accumulation and duplicate audio
2. ❌ **Abbreviation Safety:** Stop prosody breaks on "Dr.", "Mr.", etc.
3. ❌ **TTS Provider Verification:** Confirm multi-utterance streaming support
4. ❌ **Flow Control Recovery:** Prevent permanent pipeline stalls
5. ❌ **Sentence-Level Metadata:** Enable clean interruption handling
6. ❌ **Jitter Buffer Guidance:** Explicit mobile dev recommendations
7. ❌ **Smart Backpressure:** Drop stale chunks on poor networks

### 🚨 **Week-2 Production Surprises (Team Review)** ❌ PENDING
**TACTICAL fixes to prevent launch-killing issues:**
1. ❌ **Cold-Start Latency:** 200-400ms cold containers destroy 300ms TTF-A budget
2. ❌ **Concurrent Session Limits:** TTS providers cap at 10-20 connections per API key
3. ❌ **WebSocket Security:** Missing authentication on new streaming endpoint
4. ❌ **Sentence-ID Collisions:** Cross-turn conflicts confuse jitter buffers
5. ❌ **Memory Pressure Limits:** RAM exhaustion during client pauses (phone calls)
6. ❌ **Observability Tracing:** Debug prosody issues with correlation IDs
7. ❌ **Client Barge-in Protocol:** Mobile devs need interruption specifications

### 🛡️ **Critical Security & Memory Fixes (Team Technical Review)** ❌ PENDING
**SECURITY & MEMORY LEAK fixes that prevent production disasters:**
1. ❌ **JWT Security Vulnerability:** Need to fix `verify=False` → proper token validation with secret key
2. ❌ **Memory Leak Prevention:** Need to fix closure-based callbacks → weakref pattern for GC safety

**Before (DANGEROUS):**
```python
# 🚨 SECURITY HOLE - Anyone can forge tokens!
decoded_token = jwt.decode(auth, verify=False)  

# 🚨 MEMORY LEAK - Closure holds references preventing GC
def update_memory_on_consume():
    self.current_queue_bytes -= audio_size
audio_packet['_memory_callback'] = update_memory_on_consume
```

**After (PRODUCTION SAFE):**
```python
# ✅ SECURE - Proper JWT validation
decoded_token = jwt.decode(auth, JWT_SECRET, algorithms=[JWT_ALGORITHM])

# ✅ GC SAFE - No closure references, simple size tracking
async def put_with_memory_tracking(packet, size_bytes):
    packet['_memory_size'] = size_bytes  # Tracked in client_sender
    await queue.put(packet)
```

---

## 🏗️ **BACKEND Implementation Steps (REVISED v2)** ❌ ALL PENDING

### **Step 1: Smart Sentence Boundary Detection** ❌ PENDING ❌ NOT TESTED
**Duration:** ❌ PENDING
**Files:** `ai_therapist_backend/app/utils/text_processor.py` (needs to be created)

**❌ Acceptance Criteria PENDING:**
- ❌ **Buffer properly reset after each sentence emission**
- ❌ **Abbreviation safe-list prevents "Dr." prosody breaks**
- ❌ **Uses LLM pause tokens for natural breaks**
- ❌ **Preserves prosody and speech flow**
- ❌ **Character-based limits as safety valve**
- ❌ **Memory tracking included**
- ❌ **Unit tests passing**
- ❌ **Performance: <5ms per chunk processing**

### **Step 2: Enhanced Async Pipeline with Backpressure** ❌ PENDING ❌ NOT TESTED
**Duration:** ❌ PENDING
**Files:** `ai_therapist_backend/app/services/streaming_pipeline.py` (needs to be created)

**❌ Acceptance Criteria PENDING:**
- ❌ **Jitter buffer guidance included in init frame**
- ❌ **Smart backpressure timing for stale chunk detection**
- ❌ **Enhanced backpressure with timeout fallback**
- ❌ **Flow control pauses upstream when queues full**
- ❌ **Format discovery initial JSON frame**
- ❌ **Proper cleanup and resource management**
- ❌ **Error isolation between components**

### **Step 3: LLM Producer with Flow Control** ❌ PENDING ❌ NOT TESTED
**Duration:** ❌ PENDING
**Files:** `streaming_pipeline.py`, `llm_manager.py` (need updates)

**❌ Acceptance Criteria PENDING:**
- ❌ **Sentence-level metadata for clean interruption**
- ❌ **Pause-token parsing using LLM's natural boundaries**
- ❌ **Flow control integration**
- ❌ **Voice consistency with seed parameters**
- ❌ **Sequence tracking with monotonic IDs**
- ❌ **Backpressure handling with non-blocking puts**
- ❌ **Integration with existing LLMManager.stream_chat_completion()**
- ❌ **Provider-agnostic implementation using LLMConfig**

### **Step 4: Streaming TTS Processor** ❌ PENDING ❌ NOT TESTED ⭐ **CRITICAL**
**Duration:** ❌ PENDING
**Files:** `streaming_pipeline.py`, `voice_service.py` (need updates)

**❌ Acceptance Criteria PENDING:**
- ❌ **Flow control properly resets when queue space available**
- ❌ **Sentence metadata included for interruption handling**
- ❌ **Smart stale chunk dropping on poor networks**
- ❌ **TTS provider streaming capability verified**
- ❌ **Voice consistency with seed parameters**
- ❌ **Sequence preservation and jitter buffer support**
- ❌ **Graceful TTS error handling**
- ❌ **Integration with existing LLMManager.stream_text_to_speech()**
- ❌ **Uses LLMConfig.get_active_model_config(ModelType.TTS)**
- ❌ **Supports all configured TTS providers (OpenAI, Groq, etc.)**

### **Step 5: Client Sender with Jitter Buffer Support** ❌ PENDING ❌ NOT TESTED
**Duration:** ❌ PENDING
**Files:** `streaming_pipeline.py` (need updates)

**❌ Acceptance Criteria PENDING:**
- ❌ **Flow control reset in client sender**
- ❌ **Sentence ID included for clean interruption**
- ❌ **Sequence preservation metadata**
- ❌ **Progress tracking with counters**
- ❌ **Checkpoint frames for sequence validation**
- ❌ **Clean WebSocket disconnection handling**
- ❌ **Performance logging with timing metrics**

### **Step 6: WebSocket Endpoint Integration** ❌ PENDING ❌ NOT TESTED
**Duration:** ❌ PENDING
**Files:** `ai_therapist_backend/app/api/endpoints/voice.py` (need updates)

**❌ Acceptance Criteria PENDING:**
- ❌ **Cold-start prevention with /ping endpoint**
- ❌ **Connection pooling with graceful degradation**
- ❌ **WebSocket JWT authentication**
- ❌ **Unique sentence IDs across conversation turns**
- ❌ **Memory pressure monitoring and limits**
- ❌ **Comprehensive tracing and observability**
- ❌ **Client barge-in protocol specification**
- ❌ **New streaming endpoint: `/api/v1/voice/ws/tts/streaming`**
- ❌ **Backward compatibility maintained**
- ❌ **Performance monitoring and cleanup**
- ❌ **Provider-agnostic: Works with any LLMConfig provider**
- ❌ **Uses existing LLMManager instance**

### **Steps 7-10: Error Handling, Optimization, Testing, Deployment** ❌ PENDING ❌ NOT TESTED
**Duration:** ❌ PENDING
**Files:** Multiple files need to be updated

---

## 🚨 **CRITICAL FRONTEND INTEGRATION REQUIRED** ❌ PENDING

### **🔴 ISSUE 1: TTS Latency (6172ms → 300-400ms target)**
**Root Cause:** Mobile app using legacy REST flow instead of new streaming WebSocket

**Current Frontend Flow (WRONG):**
```
Mobile → /ai/response → /voice/synthesize → Download complete file → Play = 6-7s
```

**Required Frontend Flow (CORRECT):**
```
Mobile → /ws/tts/streaming → Real-time audio chunks → Stream & play = 300-400ms
```

### **🔴 ISSUE 2: Duplicate LLM/TTS Calls**
**Root Cause:** Bloc listener firing multiple times on state transitions

**Current Problem:**
```dart
// ❌ WRONG - Fires on multiple state transitions
_recordingStateSub = voiceService.recordingState.listen((recState) {
  add(SetRecordingState(isRecording)); // Fires 2-3x per recording!
});
```

---

## 📱 **FRONTEND INTEGRATION STEPS (CRITICAL)**

### **Frontend Step 1: Fix TTS Streaming Endpoint** 🚨 CRITICAL
**Duration:** 2-3 hours
**Files to modify:** `ai_therapist_app/lib/services/tts_streaming_service.dart`

### **Frontend Step 2: Fix Duplicate Call Logic** 🚨 CRITICAL
**Duration:** 1-2 hours
**Files to modify:** `ai_therapist_app/lib/blocs/voice_session_bloc.dart`

### **Frontend Step 3: Implement Real-Time Audio Streaming** 🚨 CRITICAL
**Duration:** 2-3 hours
**Files to modify:** Multiple frontend audio handling files

### **Frontend Step 4: Test on SM S938U1 Device** 🚨 CRITICAL
**Duration:** 1 hour
**Target:** Verify <400ms latency and no duplicate calls

---

## 📋 **IMPLEMENTATION CHECKLIST (UPDATED)**

### **🔴 BACKEND - Critical Launch-Blocking Fixes** ❌ ALL PENDING
- ❌ **Step 1:** Buffer reset after sentence emission *(prevents duplicate audio)*
- ❌ **Step 1:** Abbreviation safe-list implementation *(prevents prosody breaks)*
- ❌ **Step 4:** TTS provider streaming capability verification *(validates 120ms savings)*
- ❌ **Step 6:** Cold-start prevention with /ping endpoint *(prevents 200-400ms penalty)*
- ❌ **Step 6:** Connection pooling for TTS provider limits *(prevents 429 errors)*
- ❌ **Step 6:** WebSocket JWT authentication *(security requirement)*

### **🔴 BACKEND - Production Quality Hardening** ❌ ALL PENDING
- ❌ **Step 2/3/4/5:** Flow control recovery implementation *(prevents deadlocks)*
- ❌ **Step 3/4/5:** Sentence-level metadata for clean interruption *(mobile UX)*
- ❌ **Step 4:** Smart backpressure with stale chunk dropping *(poor network handling)*
- ❌ **Step 2:** Jitter buffer guidance documentation *(mobile optimization)*
- ❌ **Pipeline:** Sentence-ID uniqueness across conversation turns *(prevents conflicts)*
- ❌ **Pipeline:** Memory pressure limits (1MiB hard ceiling) *(prevents RAM exhaustion)*
- ❌ **Pipeline:** Comprehensive tracing with correlation IDs *(debugging support)*

### **🔴 BACKEND - Standard Implementation** ❌ ALL PENDING
- ❌ **Step 1:** Smart Sentence Boundary Detection (pause-token based)
- ❌ **Step 2:** Enhanced Async Pipeline with Backpressure
- ❌ **Step 3:** LLM Producer with Flow Control
- ❌ **Step 4:** Persistent TTS Processor ⭐ **CRITICAL PERFORMANCE WIN**
- ❌ **Step 5:** Client Sender with Jitter Buffer Support
- ❌ **Step 6:** WebSocket Endpoint Integration (enhanced)
- ❌ **Step 7:** Error Handling & Fallbacks
- ❌ **Step 8:** Performance Optimization
- ❌ **Step 9:** Testing & Validation (enhanced)
- ❌ **Step 10:** Deployment & Monitoring (enhanced)

### **🚨 FRONTEND - Critical Fixes Required** ❌ PENDING
- ❌ **Frontend Step 1:** Switch to `/api/v1/voice/ws/tts/streaming` endpoint
- ❌ **Frontend Step 2:** Add debouncing to prevent duplicate calls
- ❌ **Frontend Step 3:** Implement binary audio chunk streaming
- ❌ **Frontend Step 4:** Test on SM S938U1 device (<400ms target)

---

## 🏆 **BACKEND STATUS: READY TO START DEVELOPMENT** ❌
**All backend implementation steps have been reset to pending.**
**Ready to begin fresh implementation of streaming TTS architecture.**

### 🔧 **PROVIDER-AGNOSTIC IMPLEMENTATION REQUIREMENTS**

### **🎯 Core Principle: Use Existing LLMManager & LLMConfig**
The streaming implementation must respect your flexible model provider system:

```python
# ✅ CORRECT - Use existing LLMManager
from app.services.llm_manager import LLMManager
from app.core.llm_config import LLMConfig, ModelType

class StreamingPipeline:
    def __init__(self):
        self.llm_manager = LLMManager()
        
    async def get_llm_stream(self, message: str, **kwargs):
        """Use existing LLMManager for streaming responses"""
        async for chunk in self.llm_manager.stream_chat_completion(
            message=message, **kwargs
        ):
            yield chunk
    
    async def get_tts_audio(self, text: str, **kwargs):
        """Use existing LLMManager for TTS (provider-agnostic)"""
        # Get active TTS config
        tts_config = LLMConfig.get_active_model_config(ModelType.TTS)
        if not tts_config:
            raise ValueError("No TTS provider configured")
            
        # Use LLMManager's TTS method
        return await self.llm_manager.stream_text_to_speech(
            text=text, **kwargs
        )
```

### **🚨 AVOID: Hardcoded Provider Assumptions**
```python
# ❌ WRONG - Don't hardcode providers
client = OpenAI(api_key="...")  # Bad!
anthropic_client = Anthropic()  # Bad!

# ✅ CORRECT - Use LLMManager
llm_manager = LLMManager()  # Automatically uses configured provider
```

### **🔄 Provider Compatibility Matrix**
Based on your `LLMConfig`, streaming TTS must work with:

| Provider | LLM Streaming | TTS Support | Transcription |
|----------|---------------|-------------|---------------|
| OpenAI | ✅ | ✅ | ✅ |
| Groq | ✅ | ✅ | ✅ |
| Anthropic | ✅ | ❌ (Use fallback) | ❌ |
| Google | ✅ | ❌ (Use fallback) | ❌ |
| Azure OpenAI | ✅ | ✅ | ✅ |
| DeepSeek | ✅ | ❌ (Use fallback) | ❌ |

**Implementation Strategy:**
- For providers without TTS: Use OpenAI as TTS fallback
- Maintain voice consistency across provider switches
- Test provider switching mid-conversation