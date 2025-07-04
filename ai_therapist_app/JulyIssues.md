Fix #1 – “AudioFileManager not initialized”
Your goal is to make every consumer (WebSocketAudioManager, VoiceSessionCoordinator, AudioFileManager itself, etc.) see a fully-constructed instance before they touch it. The simplest, least-risky way is to turn AudioFileManager.initialize() into an async singleton that self-initialises and then wire dependency-order guarantees into your service-locator (GetIt / Provider / Riverpod, etc.).

Below is a checklist + code‐sketch your engineer can follow. Pass it along verbatim or tweak the style as you like.

1. Refactor AudioFileManager to a “ready” singleton
dart
Copy
Edit
class AudioFileManager {
  static final AudioFileManager _instance = AudioFileManager._internal();

  /// Completes when the heavy work (permissions, directory checks…) is done.
  late final Future<void> ready;

  factory AudioFileManager() => _instance;

  AudioFileManager._internal() {
    ready = _init();                 // <- kick-off once
  }

  Future<void> _init() async {
    _cacheDir = await PathManager.instance.ensureTtsDir();
    _pruneOldFiles();                // Non-blocking housekeeping
    _isReady = true;
  }

  bool get initialized => _isReady;
  bool _isReady = false;

  // existing APIs … make sure they begin with:
  void _guard() {
    if (!_isReady) throw StateError('AudioFileManager not ready');
  }
}
Key points

The constructor immediately fires _init() into ready.

Callers that must block can await AudioFileManager().ready.

Any public method calls _guard() to keep defensive behaviour unchanged.

2. Register in GetIt (or your locator) before consumers
dart
Copy
Edit
void registerAudioServices(GetIt di) {
  // 1) AudioFileManager FIRST, as a lazy-single but with pre-warm
  di.registerLazySingleton<AudioFileManager>(() {
    final mgr = AudioFileManager();
    unawaited(mgr.ready);         // warm-up in background
    return mgr;
  });

  // 2) Things that depend on it
  di.registerSingleton<WebSocketAudioManager>(
    WebSocketAudioManager(
      audioFileManager: di<AudioFileManager>(),
      // ...
    ),
  );

  di.registerSingleton<VoiceSessionCoordinator>(
    VoiceSessionCoordinator(
      audioFileManager: di<AudioFileManager>(),
      webSocketAudioManager: di<WebSocketAudioManager>(),
      // ...
    ),
  );
}
Why this works
registerLazySingleton guarantees that every consumer gets the same instance and lets them await .ready if they need blocking readiness.

3. Update consumers
VoiceSessionCoordinator
dart
Copy
Edit
class VoiceSessionCoordinator {
  final AudioFileManager _files;

  VoiceSessionCoordinator({required AudioFileManager audioFileManager, ...})
      : _files = audioFileManager;

  Future<void> init() async {
    await _files.ready;      // Block until safe
    // … rest of old init logic
  }
}
WebSocketAudioManager (if it needs files)
Same pattern: await _files.ready inside its own init().

4. Remove the manual initialize() calls
Anything in main.dart or modules that tried

dart
Copy
Edit
await AudioFileManager().initialize();
should be deleted—initialisation is now automatic and guarded.

------------------------------------------------------------------------

🔧 Fix #2 – WAV temp files keep being written (tts_stream_tts_*.wav)
1 ▸ Reproduce & observe
Step	Expected	Actual
1. adb shell rm -rf /data/user/0/<pkg>/cache/tts/*
2. Launch voice session, speak 3–4 exchanges, then adb shell ls -lh /data/user/0/<pkg>/cache/tts/	Zero or one WAV (only if fallback triggered)	3–10 new ~1 MiB WAVs appear every turn—even when WS streaming worked (Got tts-hello / tts-done).

Add this one-liner while reproducing:

bash
Copy
Edit
watch -n1 'adb shell du -sh /data/user/0/<pkg>/cache/tts'
You’ll see the folder grow ~1 MiB / reply.

2 ▸ Root cause
scss
Copy
Edit
TTSService._onStreamDone()  -->  _saveWavToCache(bytes)  -->  AudioPlayerManager.enqueue(path)
We always buffer the full stream into RAM and dump it to a WAV “backup” file, even when the WebSocket has delivered clean PCM bytes.

The file goes through the player, then is removed only if normal completion fires.
Any interruption (quit screen, crash, user hang-up) leaves the file behind.

Disk churn + orphaned files = storage bloat & unnecessary IO latency.

3 ▸ Goal
Never touch disk unless we truly need a fallback.
All happy-path playback should use an in-memory audio source.

4 ▸ implementation option
Option: Proper streaming (recommended) – feed bytes directly to player

Scope: 
☐ Replace file-based path with an in-memory AudioSource.
* just_audio: create a StreamAudioSource or BytesAudioSource → player.setAudioSource(...).
* pure ExoPlayer (Android): implement a DataSource.Factory that wraps a ByteArrayInputStream (see code below).
☐ Keep the old file route behind a feature-flag (ttsUseFileFallback); switch off for QA.

Risk:
Medium (API surface changes)

Why:
We want to eliminate needless IO & latency permanently.

5 ▸ Suggested code (must validate for errors)

5.1 Add an in-memory data-source (Android / ExoPlayer)

kotlin:
class ByteArrayDataSource(private val data: ByteArray) : DataSource {

    private var opened = false
    private var stream: ByteArrayInputStream? = null
    private var bytesRemaining: Int = 0

    override fun open(dataSpec: DataSpec): Long {
        opened = true
        stream = ByteArrayInputStream(data)
        bytesRemaining = data.size
        return bytesRemaining.toLong()
    }

    override fun read(buffer: ByteArray, offset: Int, readLength: Int): Int {
        val read = stream?.read(buffer, offset, readLength) ?: -1
        if (read > 0) bytesRemaining -= read
        return read
    }

    override fun getUri(): Uri? = null
    override fun close() { stream?.close(); opened = false }
}
kotlin:
// When TTS stream done and you have the PCM/WAV bytes:
val factory = DataSource.Factory { ByteArrayDataSource(wavBytes) }
val mediaSource = ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri("memory://tts"))
player.setMediaSource(mediaSource)
player.prepare()
player.play()
(For Flutter just_audio, the same idea is easier – AudioSource.bytes(bytes, mimeType: 'audio/wav').)

5.2 Remove/guard the file-write
dart:
if (!kUseWavDiskFallback) {
  _audioPlayer.play(InMemoryAudioSource(bytes));
} else {
  final path = await _saveWavToCache(bytes);   // legacy fallback
  _audioPlayer.play(FileAudioSource(File(path)));
}
Use const bool kUseWavDiskFallback = false for QA; flip to true remotely if crash analytics spike.

7 ▸ Testing matrix
Scenario: Normal WS success	
Expected: 0 new files; audio plays instantly

Scenario: WS drops mid-way (simulate network loss)	
Expected:A single WAV fallback has been written, queued, played, then deleted

Scenario: User kills app mid-TTS	
Expected: On next launch, sweeper removes any stale WAVs

Scenario: Measure with du -sh cache/tts before/after.

8 ▸ Deployment order
Ship logging only (counts files in/out) to confirm leak profile in the wild.

Roll out behind remote-config flag (tts_file_fallback).

After one release cycle with no audio regressions, delete old file-path code.