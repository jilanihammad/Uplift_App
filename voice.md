# VoiceService Resource Leak Analysis 

## 🚨 CRITICAL LEAK #1: Dual Audio Player System

### The Problem:
```dart
// VoiceService has TWO separate audio player systems:
AudioPlayer? _currentPlayer;           // Used in playAudio(), stopAudio()
AudioPlayerManager _audioPlayerManager; // Used in streamAndPlayTTS()
```

### Race Condition:
```dart
// streamAndPlayTTS() - Line 495
await _audioPlayerManager.playAudio(filePath!);  // Creates codec #1

// Meanwhile, playAudio() might also be called - Line 697
_currentPlayer = AudioPlayer();                   // Creates codec #2
await _currentPlayer!.setFilePath(audioPath);
```

**Result**: Two AudioPlayer instances = Two codecs running simultaneously!

## 🚨 CRITICAL LEAK #2: Recording Manager vs VAD Recording

### The Problem:
```dart
// startRecording() delegates to RecordingManager
await _recordingManager.startRecording();  // Creates AAC encoder #1

// But VAD also starts recording (seen in AutoListeningCoordinator)
await _vadManager.startListening();        // Creates AAC encoder #2
```

**From your logs**: This explains codec #166 and codec #940 running simultaneously.

## 🚨 CRITICAL LEAK #3: WebSocket + StreamSubscription Leaks

### The Problem in streamAndPlayTTS():
```dart
final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
StreamSubscription? subscription;

subscription = channel.stream.listen((event) async {
  // Complex logic with multiple exit paths
  if (data['type'] == 'done') {
    await subscription?.cancel();     // ✅ Cancelled here
    await channel.sink.close();      // ✅ Closed here
  } else if (data['type'] == 'error') {
    await subscription?.cancel();     // ✅ Cancelled here  
    await channel.sink.close();      // ✅ Closed here
  }
}, onError: (err) async {
  await subscription?.cancel();       // ✅ Cancelled here
  await channel.sink.close();        // ✅ Closed here
});
```

**Issue**: If an exception occurs in the `listen` callback before reaching these cleanup points, the WebSocket and subscription leak!

## 🚨 CRITICAL LEAK #4: File Cleanup Race Conditions

### Multiple Deletion Attempts:
```dart
// In streamAndPlayTTS() - Line 495+
// File created here:
tempFile = io.File(filePath!);
await tempFile!.writeAsBytes(audioBuffer);

// Deleted in onDone callback (inside listen)
// ALSO deleted in finally block
if (tempFile != null && await tempFile!.exists()) {
  await tempFile!.delete();  // Could race with earlier deletion
}

// ALSO deleted in generateAudio() finally block
await _deleteFile(finalFilePath!);  // Third deletion attempt!
```

**Race Condition**: Multiple async deletion attempts can cause file system exceptions.

## 🚨 CRITICAL LEAK #5: Player Disposal Logic Issues

### In stopAudio():
```dart
// Stop and dispose current player
if (_currentPlayer != null) {
  await _currentPlayer!.stop();
  await _currentPlayer!.dispose();  // Disposes _currentPlayer
  _currentPlayer = null;
}

// ALSO stop the AudioPlayerManager
await _audioPlayerManager.stopAudio();  // But what about ITS player?
```

**Problem**: AudioPlayerManager's internal player might not be properly disposed.

## 🔧 SPECIFIC FIXES NEEDED

### ✅ Fix 1: Consolidate Audio Players - **COMPLETED**
**Status**: ✅ **SUCCESSFULLY IMPLEMENTED**
- Removed `_currentPlayer` entirely 
- Consolidated to use only `AudioPlayerManager` for all audio playback
- **Verified in logs**: No dual codec creation, clean state transitions, good TTS performance (10.5s)

### 🔄 Fix 2: WebSocket Resource Safety - **IN PROGRESS**
**Status**: ⚠️ **NEEDS DIFFERENT APPROACH** 
- Current WebSocket cleanup is embedded in callbacks
- Requires major refactoring to guarantee cleanup
- **Decision**: Skip for now, implement simpler fixes first

### 🔄 Fix 3: Single File Deletion - **IMPLEMENTING NEXT**
**Status**: 🔧 **READY TO IMPLEMENT**
- Create FileCleanupManager to prevent race conditions
- Prevent multiple deletion attempts on same file
- **Impact**: Eliminates file system exceptions from concurrent deletion

## 📊 Expected Impact

### Before Fixes:
- ❌ Dual AudioPlayer instances (codec leak)
- ❌ WebSocket/StreamSubscription leaks
- ❌ File deletion race conditions  
- ❌ Recording system conflicts
- ❌ Resource cleanup failures

### After Fixes:
- ✅ Single audio player instance
- ✅ Guaranteed WebSocket cleanup
- ✅ Safe file deletion
- ✅ Coordinated recording systems
- ✅ Proper resource lifecycle management

The dual audio player system is likely the **primary cause** of your codec leaks!