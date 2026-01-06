# CLAUDE.md

Comprehensive guidance for engineers working on the Maya AI Therapist Flutter app.

## Core Commands

```bash
# Setup
flutter clean
flutter pub get

# Run app
dart run build_runner clean   # only if code-gen artifacts exist
flutter run                    # choose device or emulator

# Code quality
flutter analyze
dart format .

# Testing
flutter test                   # all unit/widget tests
flutter test integration_test  # integration tests

# Builds
flutter build apk --debug
flutter build apk --release
flutter build ios --no-codesign
```

---

## High-Level Architecture

### State Management (BLoC Pattern)
- **VoiceSessionBloc** (`lib/blocs/voice_session_bloc.dart`): Central orchestrator for voice sessions
  - Manages voice/chat mode switching
  - Coordinates TTS, recording, and auto-listening states
  - Uses generation counters (`_modeGeneration`) to prevent stale callbacks
- **Helper Managers**: TimerManager, MessageCoordinator, SessionStateManager decompose bloc complexity
- **State Flow**: Events → BLoC → State → UI rebuilds

### Dependency Injection
- **ServiceLocator** (`lib/di/service_locator.dart`): GetIt-based registration
- **DependencyContainer** (`lib/di/dependency_container.dart`): Typed service access
- **SessionScopeManager** (`lib/services/session_scope_manager.dart`): Per-session service lifecycle
  - Creates fresh AudioPlayerManager, VoiceSessionCoordinator per session
  - Disposes services on session end to prevent memory leaks

### Services Layer (`lib/services/`)
| Service | Purpose |
|---------|---------|
| `voice_service.dart` | Master orchestrator for recording, TTS, auto-listening |
| `voice_session_coordinator.dart` | Focused interface for bloc-to-service communication |
| `simple_tts_service.dart` | WebSocket TTS streaming with queue management |
| `auto_listening_coordinator.dart` | VAD-driven automatic recording triggers |
| `enhanced_vad_manager.dart` | RNNoise-based voice activity detection |
| `recording_manager.dart` | Audio recording with shared recorder access |
| `audio_player_manager.dart` | ExoPlayer/just_audio wrapper for playback |

---

## Voice Pipeline Architecture

### Audio Flow (Voice Mode)
```
┌─────────────────────────────────────────────────────────────────────┐
│                        VOICE SESSION FLOW                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. VAD Detection (EnhancedVADManager)                              │
│     └── RNNoise confidence > 0.8 threshold                          │
│     └── Min 5 speech frames (50ms) to trigger                       │
│     └── Min 30 silence frames (300ms) to end                        │
│                                                                     │
│  2. Recording (RecordingManager)                                    │
│     └── SharedRecorderAccess prevents concurrent recorder use       │
│     └── 48kHz mono M4A format                                       │
│     └── Path: /cache/recordings/{uuid}.m4a                          │
│                                                                     │
│  3. Transcription (VoiceService → Backend)                          │
│     └── POST /voice/transcribe with base64 audio                    │
│     └── 45s timeout for slow connections                            │
│                                                                     │
│  4. LLM Response (MessageProcessor → Backend)                       │
│     └── POST /ai/response with history context                      │
│     └── State machine guides conversation flow                      │
│                                                                     │
│  5. TTS Streaming (SimpleTTSService)                                │
│     └── WebSocket /ws/tts                                           │
│     └── WAV format (OPUS disabled - see Audio Format section)       │
│     └── Progressive streaming with 4KB buffer threshold             │
│                                                                     │
│  6. Playback (AudioPlayerManager)                                   │
│     └── ExoPlayer on Android, AVPlayer on iOS                       │
│     └── Natural completion triggers listening restart               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Auto-Listening State Machine
```
┌───────────────────────────────────────────────────────────────────┐
│              AutoListeningCoordinator States                       │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│   idle ──(enableAutoMode)──► listeningForVoice                    │
│     │                              │                              │
│     │                              │ (VAD speech start)           │
│     │                              ▼                              │
│     │                         userSpeaking                        │
│     │                              │                              │
│     │                              │ (VAD speech end + timeout)   │
│     │                              ▼                              │
│     │                         processing                          │
│     │                              │                              │
│     │                              │ (transcription complete)     │
│     │                              ▼                              │
│     │                         aiSpeaking                          │
│     │                              │                              │
│     │◄─────(TTS complete)─────────┘                               │
│     │                                                             │
│     │◄─────(disableAutoMode)───── any state                       │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## TTS Streaming Implementation

### SimpleTTSService Architecture (`lib/services/simple_tts_service.dart`)

**Queue-Based Processing**:
- Requests queued to prevent overlapping TTS
- `hasPendingOrActiveTts` getter for race condition checks
- Generation tracking prevents stale completions

**WebSocket Connection Pooling** (lines 161-204):
```dart
// Pre-warmed connections save ~150ms per request
WebSocketChannel? _prewarmedConnection;
static const Duration _connectionTtl = Duration(seconds: 30);

Future<WebSocketChannel> _getConnection(String wsUrl) async {
  // Reuse pre-warmed connection if valid
  // Start pre-warming next connection in background
}
```

**Streaming Flow**:
1. Send `{text, voice, format}` over WebSocket
2. Receive `hello` message with mime type
3. Accumulate audio chunks until buffer threshold (4KB)
4. Start playback with LiveTtsAudioSource
5. Continue streaming remaining chunks
6. Receive `tts-done` message
7. Wait for playback completion

**Race Condition Guards** (lines 1429-1450):
```dart
// Don't reset TTS state if playback is active
@override
void resetTTSState() {
  if (_queue.isNotEmpty || _state != _State.idle || _pendingStreams > 0) {
    debugPrint('🛡️ Skipping reset - active TTS in progress');
    return;
  }
  // ... actual reset
}
```

**Lazy TTS Config Initialization** (GOLD STANDARD):
Two-layer defense for TTS config loading with zero startup blocking:

```dart
// State variables (lines 146-149)
bool _ttsConfigFetched = false;           // True if config fetch attempted
Future<void>? _configFetchInProgress;     // Deduplication for concurrent calls

// Layer 1: Opportunistic prefetch (service_locator.dart:787-825)
void _prefetchTTSConfigNonBlocking(ApiClient apiClient) {
  unawaited(() async {
    // Fire-and-forget background fetch at startup
    final config = await apiClient.fetchTtsConfig();
    if (config != null) {
      LLMConfig.applyRemoteTtsConfig(...);
      ttsService.setCachedTTSConfig();  // Mark config ready
    }
  }());
}

// Layer 2: Lazy initialization (lines 271-354)
Future<void> _ensureTTSConfig() async {
  if (_ttsConfigFetched) return;  // Fast path - already cached

  if (_configFetchInProgress != null) {
    return await _configFetchInProgress!;  // Deduplicate concurrent calls
  }

  // Lazy fetch with 5s timeout + fallback to defaults
  _configFetchInProgress = _fetchConfigWithFallback();
  await _configFetchInProgress!;
  _ttsConfigFetched = true;
}

// Called before every TTS request (line 78)
await _ensureTTSConfig();  // Ensures config ready before speak()
```

**Benefits**:
- Zero startup blocking (prefetch runs in background)
- Instant TTS if prefetch succeeds before first request
- Resilient fallback if prefetch fails
- Request deduplication prevents multiple fetches
- 5s timeout with graceful fallback to defaults

**Debug Logs**:
```
[TTS Config] Prefetch started (non-blocking)
[TTS Config] Marked as cached from prefetch  ← Success!
[TTS Config] Prefetch succeeded and applied
```

---

## VAD (Voice Activity Detection)

### EnhancedVADManager (`lib/services/enhanced_vad_manager.dart`)

**RNNoise Integration**:
- Native noise suppression via `rnnoise_flutter` plugin
- 48kHz sample rate required
- Returns VAD probability (0.0 - 1.0)

**Thresholds (tuned to reduce false positives)**:
```dart
double _speechThreshold = 0.8;      // RNNoise confidence threshold
int _minSpeechFrames = 5;           // 50ms at 10fps to start
int _minSilenceFrames = 30;         // 300ms at 10fps to end
```

**Android AudioRecord.read() Blocking Fix** (CRITICAL):

The `audio_streamer` package uses blocking `AudioRecord.read()` on Android. When stopping VAD, the worker thread can get stuck waiting for audio frames.

**Old Approach (caused 500ms timeouts)**:
```dart
await _audioSubscription!.cancel();
await _workerDone!.future.timeout(Duration(milliseconds: 500)); // BLOCKED!
```

**New Non-Blocking Approach** (lines 698-800):
```dart
Future<void> stopListening() async {
  // 1. Set shutdown flags IMMEDIATELY
  _isShuttingDown = true;
  _isStreamActive = false;
  _isListening = false;

  // 2. Complete worker future IMMEDIATELY (don't wait for blocked read())
  _completeWorkerIfNeeded('shutdown signal');

  // 3. Cancel subscription without awaiting (sends stop signal to native)
  unawaited(_audioSubscription!.cancel());

  // 4. Brief delay for stop signal propagation (NOT waiting for read())
  await Future.delayed(Duration(milliseconds: 50));
}
```

**Key Insight**: The worker thread will naturally stop on its next frame because the shutdown flag checks in `_processRNNoiseAudioChunk` will return early:
```dart
if (!_isInitialized || !_isStreamActive || _isShuttingDown || !_isListening) {
  return; // Exit early - worker effectively stopped
}
```

---

## Audio Format Configuration

### AudioFormatConfig (`lib/config/audio_format_config.dart`)

**Current Settings**:
```dart
static bool get enableOpusFormat => false;  // WAV mode
static int get opusRolloutPercentage => 0;  // OPUS disabled
```

**Why OPUS is Disabled**:
The backend (OpenAI TTS) returns WAV format by default. Even when the client requests OPUS:
```
Client: format=opus
Backend Response: RIFF....WAVEfmt (WAV data!)
```

To enable OPUS, the backend would need `response_format: "opus"` in the OpenAI TTS API call.

**Audio Format Negotiator** (`lib/services/audio_format_negotiator.dart`):
- Priority: Native (Gemini Live) > Client OPUS preference > Backend format > WAV fallback
- Emergency fallback to WAV if streaming fails
- Format info logged for debugging

---

## Critical Race Conditions & Fixes

### 1. TTS Reset During Active Playback
**Problem**: `resetTTSState()` was killing AI response TTS when welcome message completed.

**Fix** (`voice_session_bloc.dart:771-784`):
```dart
if (_safeVoiceService.hasPendingOrActiveTts) {
  debugPrint('Skipping stopAudio/resetTTS - active TTS in progress');
  // Still enable auto mode but skip destructive operations
  await _safeVoiceService.enableAutoMode();
  return;
}
```

### 2. Auto Mode Desync During Mic Toggle
**Problem**: Toggling mic during TTS caused `autoModeEnabled` to desync from bloc state. When TTS finished, Maya wouldn't resume listening.

**Fix A** - Include mic state in callback (`voice_session_bloc.dart:303-307`):
```dart
voiceService.canStartListeningCallback = () =>
    state.isVoiceMode &&
    state.isInitialGreetingPlayed &&
    state.isMicEnabled &&  // CRITICAL: Include mic state
    !state.isVoiceModeSwitching;
```

**Fix B** - Re-enable auto mode on TTS completion (`voice_service.dart:1699-1714`):
```dart
if (!_autoListeningCoordinator.autoModeEnabled) {
  // If bloc says we CAN listen, re-enable auto mode
  if (canStartListeningCallback != null && canStartListeningCallback!()) {
    _autoListeningCoordinator.enableAutoMode();
    _autoListeningCoordinator.startListening();
    return;
  }
}
```

### 3. Generation Counter Pattern
Used throughout to prevent stale async callbacks:
```dart
final gen = _modeGeneration;
await someAsyncOperation();
if (gen != _modeGeneration) return; // State changed, abort
```

---

## Interfaces & Contracts

### IVoiceService (`lib/di/interfaces/i_voice_service.dart`)
Key methods for voice operations:
- `startRecording()` / `stopRecording()` / `tryStopRecording()` (idempotent)
- `enableAutoMode()` / `disableAutoMode()`
- `updateTTSSpeakingState(bool, {int? playbackToken})`
- `hasPendingOrActiveTts` - Race condition guard

### ITTSService (`lib/di/interfaces/i_tts_service.dart`)
TTS operations:
- `speak(text, {voice, format, caller})` - Queue TTS request
- `stopSpeaking()` - Cancel active TTS
- `hasPendingOrActiveTts` - Check for active/queued TTS

---

## Common Gotchas & Debugging Tips

### Don't Do This
```dart
// ❌ Don't await subscription cancel on Android (blocks on AudioRecord.read)
await _audioSubscription!.cancel();

// ❌ Don't reset TTS state without checking hasPendingOrActiveTts
_ttsService.resetTTSState(); // May kill active AI response!

// ❌ Don't call disableAutoMode without considering TTS state
disableAutoMode(); // May prevent listening restart after TTS

// ❌ Don't ignore generation counters in async callbacks
await longOperation();
emit(state); // State may have changed!
```

### Do This Instead
```dart
// ✅ Use unawaited for subscription cancel
unawaited(_audioSubscription!.cancel());

// ✅ Check hasPendingOrActiveTts before reset
if (!_ttsService.hasPendingOrActiveTts) {
  _ttsService.resetTTSState();
}

// ✅ Check canStartListeningCallback for current bloc state
if (canStartListeningCallback?.call() ?? false) {
  _autoListeningCoordinator.enableAutoMode();
}

// ✅ Use generation counters
final gen = _generation;
await longOperation();
if (gen != _generation) return;
```

### Useful Debug Logs
```
🎯 [TTS] Starting playback     - TTS request started
✅ [TTS] Natural completion    - Playback finished normally
🛡️ [TTS] Skipping reset       - Race condition guard triggered
🛑 Enhanced VAD: Shutdown flags set - VAD stopping (non-blocking)
[VoiceService] TTS done – autoMode disabled but bloc allows listening, re-enabling
[TTS Config] Prefetch started (non-blocking) - Background config fetch started
[TTS Config] Marked as cached from prefetch - Prefetch succeeded, lazy fetch skipped
[TTS Config] Lazy fetch triggered - Prefetch missed, fetching on-demand
```

---

## File Organization

```
lib/
├── blocs/
│   └── voice_session_bloc.dart      # Main session orchestrator
├── config/
│   ├── audio_format_config.dart     # OPUS/WAV settings
│   └── llm_config.dart              # LLM provider settings
├── di/
│   ├── interfaces/                  # Service contracts
│   ├── service_locator.dart         # GetIt registration
│   └── dependency_container.dart    # Typed service access
├── services/
│   ├── voice_service.dart           # Voice orchestrator
│   ├── simple_tts_service.dart      # TTS streaming
│   ├── auto_listening_coordinator.dart  # VAD coordination
│   ├── enhanced_vad_manager.dart    # RNNoise VAD
│   ├── recording_manager.dart       # Audio recording
│   └── audio_player_manager.dart    # Playback
├── screens/
│   └── chat_screen.dart             # Main UI
└── utils/
    ├── feature_flags.dart           # Runtime toggles
    └── opus_header_utils.dart       # Audio format utilities
```

---

## Recent Updates (2025-12 to 2025-01)

### Performance Optimizations
- **Lazy TTS Config Initialization** (Gold Standard): Two-layer defense with zero startup blocking
  - Opportunistic prefetch runs in background (non-blocking)
  - Lazy fetch fallback on first TTS request (5s timeout)
  - Request deduplication prevents multiple fetches
  - Eliminates 15s blocking delay during app startup
- WebSocket connection pooling saves ~150ms per TTS request
- Reduced TTS buffer from 32KB to 4KB for faster time-to-first-audio
- AudioPlayerManager pre-warming on app startup
- Deferred RemoteConfigService initialization
- Fixed zone mismatch warning (moved WidgetsFlutterBinding initialization inside zone)

### Bug Fixes
- VAD worker thread no longer blocks on `AudioRecord.read()` (non-blocking shutdown)
- Auto mode re-enablement after TTS when mic was toggled during playback
- TTS reset race condition guard (`hasPendingOrActiveTts`)
- Generation counter pattern prevents stale async callbacks

### Audio Streaming Fixes (2025-01)

| File | Issue | Fix |
|------|-------|-----|
| `live_tts_audio_source.dart` | Audio streaming ended prematurely for MP3/WAV | Wait for all formats, not just OPUS |
| `live_tts_audio_source.dart` | Replay prevention blocking ExoPlayer retries | Return EOF/serve buffer instead of throwing |
| `live_tts_audio_source.dart` | Audio repeating multiple times | Track `_primaryStreamStarted` to prevent multiple stream generators |
| `simple_tts_service.dart` | Logging showed "WAV" for MP3 format | Added proper MP3/OPUS/WAV format detection in logs |
| `audio_format_config.dart` | `effectiveFormat` only knew OPUS/WAV | Updated to indicate format is request-dependent |
| `voice_service.dart` | 5s timeout race condition with stream subscriptions | Replaced `firstWhere()` + short timeouts with state polling at 200ms intervals (60s max) |

**Key Fix: Timeout Race Condition in VoiceService**

The `enableAutoModeWhenPlaybackCompletes()` method had a race condition where stream events could be missed between subscription attempts:

```dart
// Before (race condition prone):
await isTtsActuallySpeaking
    .firstWhere((speaking) => speaking == false)
    .timeout(const Duration(seconds: 5));  // Could miss events!

// After (reliable state polling):
while (DateTime.now().difference(startTime) < maxWaitDuration) {
  if (!_ttsActive && !_playbackActive) {
    playbackCleared = true;
    break;
  }
  await Future.delayed(pollInterval);  // 200ms polling
}
```

**Benefits:**
- No more spurious "timed out" warnings for long audio
- No race condition from missed stream events between subscriptions
- 60s max wait covers very long TTS responses
- State polling is more reliable than stream subscriptions for this use case

### Architecture Changes
- **SimpleTTSService**: Added lazy config initialization with state tracking (`_ttsConfigFetched`, `_configFetchInProgress`)
- **ITTSService**: Added `setCachedTTSConfig()` method for prefetch coordination
- **IApiClient**: Added `fetchTtsConfig()` method to interface for type safety
- **Service Locator**: Prefetch calls `setCachedTTSConfig()` on success to mark config ready
- `canStartListeningCallback` now includes `isMicEnabled` state
- VoiceService re-enables auto mode on TTS completion if bloc allows
- Enhanced VAD uses immediate shutdown flags instead of waiting for blocked threads

---

## Mood Tracking & Visualization

### Overview
The app includes a comprehensive mood tracking system with local persistence, backend sync, and beautiful wave visualization.

### Architecture

**Components:**
- `ProgressService` - Core service managing mood entries and aggregation
- `ProgressScreen` - UI displaying mood history with wave chart
- `HomeScreen` - Quick mood logging interface
- `MoodWavePainter` - CustomPaint widget for smooth wave visualization

### Data Flow

```
User logs mood → ProgressService.logMood()
  ├─ Save to SQLite (mood_entries table)
  ├─ Add to in-memory cache (_moodEntries)
  ├─ Rebuild aggregates (_rebuildMoodAggregates)
  │   └─ Aggregate by day with averages
  ├─ Save to SharedPreferences
  └─ Schedule backend sync (if moodPersistenceEnabled)
```

### Key Features

#### 1. Circular Buffer (3 moods/day limit)
When user logs 4th mood in a day, oldest entry is automatically replaced:
```dart
// progress_service.dart:802-826
if (todayEntries.length >= 3) {
  final oldestEntry = todayEntries.reduce((a, b) =>
    a.loggedAt.isBefore(b.loggedAt) ? a : b
  );
  await _databaseProvider.delete(_moodEntriesTable,
    where: 'client_entry_id = ?',
    whereArgs: [oldestEntry.clientEntryId],
  );
  _moodEntries.removeWhere((e) => e.clientEntryId == oldestEntry.clientEntryId);
}
```

**UX:** No error message, seamless updating of mood throughout the day.

#### 2. Mood Wave Visualization
Beautiful wave chart showing mood trends over time:

**Features:**
- Smooth Bézier curves connecting data points
- Gradient fill (green → amber → red) representing emotional range
- Emoji markers at data points with white circle backgrounds
- Smart spacing (shows ~7 emojis for clarity even with 30+ days of data)
- Y-axis mapping based on emotional valence:
  ```dart
  // progress_screen.dart:775-790
  if (moodIndex == 0) {        // Happy
    normalizedY = 0.1;          // Top 10% (High positivity)
  } else if (moodIndex == 1) { // Neutral
    normalizedY = 0.5;          // Middle 50%
  } else {                      // Sad, Anxious, Angry, Stressed
    normalizedY = 0.7 + ((moodIndex - 2) / 3.0) * 0.3;  // Bottom 70-100%
  }
  ```

**Why this mapping?**
- Happy (0) → High positivity zone
- Neutral (1) → Middle zone
- Sad/Anxious/Angry/Stressed (2-5) → Low positivity zone
- Prevents sad/anxious from appearing in neutral range

#### 3. Backend Sync
Mood entries sync to backend when `moodPersistenceEnabled` feature flag is enabled:

**Endpoints:**
- `GET /api/v1/mood_entries?limit=50&since=<timestamp>` - Fetch updates
- `POST /api/v1/mood_entries:batch_upsert` - Upload local entries

**Features:**
- Offline queue with pending entries
- Debounced sync (500-3000ms jitter)
- Automatic retry on network errors
- 60-day retention with automatic purging

#### 4. Data Aggregation
Mood entries are stored individually but aggregated by day for visualization:

```dart
// _rebuildMoodAggregates() creates two structures:
// 1. _moodHistory: Map<String, List<Map>> - All entries grouped by day
// 2. UserProgress.moodHistory: Map<DateTime, int> - Daily averages
```

**Example:**
- 3 entries on 12/1: Happy, Neutral, Happy
- Average: (0 + 1 + 0) / 3 = 0.33 ≈ 0 (Happy)
- Chart shows single "Happy" emoji for 12/1

### Mood Enum
```dart
enum Mood { happy, neutral, sad, anxious, angry, stressed }
// Indices: 0=happy, 1=neutral, 2=sad, 3=anxious, 4=angry, 5=stressed
```

### Important Metrics

**Three Different Counts:**
1. **Individual Entries** (`getTotalMoodEntriesCount()`) - Total mood logs ever
2. **Days with Data** (`moodHistory.length`) - Number of unique days
3. **Days This Week** (`moodLogsThisWeek`) - Days in last 7 days with mood data

### Database Schema
```sql
CREATE TABLE mood_entries (
  id TEXT PRIMARY KEY,
  client_entry_id TEXT UNIQUE,
  user_id TEXT,
  mood INTEGER,
  logged_at TEXT,
  notes TEXT,
  is_pending INTEGER,
  sync_error TEXT
);
```

### Debug Logging
Comprehensive logging for troubleshooting:
```dart
[ProgressService] logMood called with mood: Happy
[ProgressService] Mood cache loaded. Total entries: 33
[ProgressService] Offline status: false
[ProgressService] Current date/time: 2025-12-02 21:44:00.000
[ProgressService] Today's entries count: 2
[ProgressService] _rebuildMoodAggregates called with 33 entries
[ProgressService] After aggregation: 12 days in moodHistory
[ProgressService] ✅ Mood logged successfully
```

### Common Issues

**Issue: Mood chart shows fewer emojis than total entries**
- **Why:** Chart shows ~7 emojis for clarity (line 888: `step = (points.length / 7).ceil()`)
- **Fix:** Not a bug - prevents crowding on small screens

**Issue: "You've logged mood 12 times" but 33 entries**
- **Why:** Was counting days, not entries (now fixed)
- **Fix:** Use `getTotalMoodEntriesCount()` not `moodHistory.length`

**Issue: Sad/Anxious showing in neutral range**
- **Why:** Linear mapping treated all 6 moods equally
- **Fix:** Emotional valence mapping (Happy=High, Neutral=Mid, Others=Low)

---

## Testing Checklist for Voice Features

Before merging voice pipeline changes:
- [ ] Start voice session, let Maya speak welcome message
- [ ] User speaks, Maya responds (full cycle)
- [ ] Toggle mic ON/OFF during TTS - Maya should resume listening after TTS
- [ ] End session during TTS - TTS should stop cleanly
- [ ] Background app during TTS - audio should continue
- [ ] Check logs for race condition warnings (`🛡️`, `⚠️`)
- [ ] No "Worker completion timeout" warnings in logs
- [ ] `flutter analyze` passes

---

## Testing Checklist for Mood Features

Before merging mood tracking changes:
- [ ] Log mood from home screen - should show success message
- [ ] Log 3 moods in one day - all should succeed
- [ ] Log 4th mood same day - should replace oldest, no error
- [ ] Check home screen "Days Logged" count is correct
- [ ] Navigate to Progress → Mood tab
- [ ] Verify mood wave chart displays with smooth curves
- [ ] Verify emoji markers show correct moods (Happy at top, Sad/Anxious at bottom)
- [ ] Check "You've logged mood X times" matches actual total entries
- [ ] Test offline: log mood, verify "Saved locally" message
- [ ] Go back online, verify sync happens automatically
- [ ] Check logs for mood aggregation: `[ProgressService] After aggregation: X days`
- [ ] `flutter analyze` passes

---

## Contributing

1. Read this document thoroughly before making voice pipeline changes
2. Use generation counters for all async operations that modify state
3. Check `hasPendingOrActiveTts` before any TTS reset/stop operations
4. Test mic toggle during TTS playback
5. Update this document when adding new patterns or fixing bugs
