# Voice Pipeline Entry Points (Pre-Controller)

This note captures the current public entry points that manipulate automatic listening and mic pipeline state. Use it as the reference “map” before migrating logic into the new `VoicePipelineController`.

## AutoListeningCoordinator

| Method | Responsibility | Typical Callers |
| --- | --- | --- |
| `initialize()` | Warm up VAD implementation and reset auto-mode. | `VoiceService.initialize()` during session bootstrap. |
| `enableAutoMode()` | Enables auto-mode using internal playback/VAD heuristics. | `VoiceService.enableAutoMode()`, `VoiceSessionBloc._onEnableAutoMode`, auto-mode reschedules after TTS. |
| `enableAutoModeWithAudioState(isAudioPlaying)` | Enables auto-mode with explicit audio-playing hint coming from bloc/UI state. | `VoiceSessionBloc._resumeDeferredVoiceAutoMode`, welcome guard completion. |
| `disableAutoMode()` | Cancels auto-mode, stops listening/recording, and resets VAD state. | `VoiceService.disableAutoMode()`, `VoiceSessionBloc._onToggleMicMute`, lifecycle guards. |
| `reset({full, preserveAutoMode})` | Clears timers, generations, and optionally disables auto-mode. | `VoiceSessionBloc._prepareVoiceMode`, `VoiceService` teardown, chat↔voice switches. |
| `triggerListening()` / `startListening()` | Manual nudges to kick VAD back into listening immediately. | `VoiceSessionBloc._triggerListening`, welcome completion, diagnostic tools. |
| `onProcessingComplete()` | Called when transcription/LLM work is done to resume listening. | `VoiceService._handleTranscriptionComplete`. |

Every public method now emits a stack trace (debug builds, controller flag off) so we can confirm actual call stacks before deleting these entry points.

## VoiceService

| Method | Description | Typical Callers |
| --- | --- | --- |
| `enableAutoMode()` | Thin proxy that forwards to coordinator. | `VoiceSessionBloc._onEnableAutoMode`, `VoiceSessionBloc._welcomeAutoModeResume`. |
| `enableAutoModeWithAudioState()` | Proxy with explicit audio state. | `VoiceSessionBloc._attemptAutoResumeAfterWelcome`. |
| `disableAutoMode()` | Disables auto-mode and logs state. | Mic mute toggles, pipeline teardown. |
| `enableAutoModeWhenPlaybackCompletes({token})` | Schedules auto-mode re-arm after AI audio playback completes. | `AudioPlayerManager.onPlaybackToken`, streaming callbacks. |

## VoiceSessionBloc & UI Entry Points

| Event / Call | Effect |
| --- | --- |
| `EnableAutoMode` event | Dispatches to `VoiceService.enableAutoMode()` and tracks `_modeGeneration` for stale callback prevention. |
| `DisableAutoMode` event | Dispatches to `VoiceService.disableAutoMode()` when mic muted, chat-mode switches, or session ends. |
| `_resumeDeferredVoiceAutoMode()` | Called after welcome TTS or playback deferrals; currently reaches into `VoiceService.enableAutoModeWithAudioState`. |
| `VoiceControlsPanel` → `ToggleMicMute` | Toggling mic fires `DisableAutoMode`/`EnableAutoMode` chain depending on current guard state. |

This inventory will be pruned as the controller subsumes responsibilities; keep it updated until the new pipeline becomes the single contract.
