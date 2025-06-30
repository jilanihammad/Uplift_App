(Done) 1 · Persisted Dark / Light Theme Preference
Field	Details
Goal:	App launches in dark mode by default. If the user toggles to light or back to dark, that choice is written to local storage and applied automatically on the next launch.
Scope:	Flutter theme state management & persistence.
Suggested Approach:	
a. Add ThemeMode field to existing SettingsService (or create one if missing).
b. Persist the enum (dark, light, system) in SharedPreferences using a simple key like "pref_theme".
c. In main(), synchronously read the saved value before runApp() (use WidgetsFlutterBinding.ensureInitialized() so there’s no theme flash).
d. Update the settings screen toggle to dispatch settingsService.setTheme(ThemeMode.X) which writes & notifies listeners.
Touch-points:	settings_screen.dart, settings_service.dart, main.dart (or the root Provider).
Acceptance:	<ul><li>Fresh install ⇒ dark mode.</li><li>User switches to light ⇒ restarts app ⇒ still light.</li><li>CI widget test: mock prefs, ensure correct theme injected.</li></ul>

(done) 2 · Persist & Surface User Name
Field	Details
Goal:	Name entered during onboarding must re-appear in Settings → “Your Name” field.
Scope:	User profile storage & retrieval.
Suggested Approach:	
a. Extend the existing UserProfile model to include firstName (if not already).
b. Onboarding flow should call profileRepository.save(profile.copyWith(firstName: value)).
c. Settings screen fetches the name from the same repository/provider and populates the text field’s controller.text.
d. Add null-safety fallback ('').
Touch-points:	onboarding_name_step.dart, profile_repository.dart, settings_screen.dart.
Acceptance:	Enter “Alex” in onboarding → open settings after cold restart → field shows “Alex”.

3 · TTS Welcome-File Race Condition
Field	Details
Goal:	Prevent premature deletion of synthesized welcome audio (tts_audio_*.wav).
Scope:	AudioPlayerManager & VoiceService lifecycle.
Suggested Approach:	
a. Deletion currently occurs in onComplete() before AudioPlayerManager finishes handing off the file.
b. Move cleanup into AudioPlayerManager → after player.dispose() fires onPlayerComplete (recommended).
c. Alternatively, add a simple “in-use” flag on the file path list—delete only when not in queue and not playing.
Touch-points:	audio_player_manager.dart, voice_service.dart.
Acceptance:	No more “File not found …wav, using TTS fallback” logs after three consecutive launches with welcome TTS enabled.

4 · Remove Summary JSON Parse Warning
Field	Details
Goal:	Silence log spam when backend sends plain-text summaries.
Scope:	Session summary parsing layer.
Suggested Approach:	
a. Replace try { jsonDecode(summary); … } with a type check: if server returns Map, treat as JSON; else use raw string.
b. Update the domain model so summary can be either String or Map<String,dynamic> (if we plan to support both in future).
Touch-points:	session_repository.dart, any SummaryCard widget that assumes JSON.
Acceptance:	Run a session → summary arrives → no FormatException in debug console.

5 · Guard MemoryManager Double-Init
Field	Details
Goal:	Ensure MemoryManager initializes once.
Scope:	Singleton / service-locator pattern.
Suggested Approach:	
a. Wrap the lazy getter with if(_instance != null) return _instance!; guarded by mutex.lock() (or Dart synchronized if available) to prevent parallel awaits racing.
b. Log only on the first creation.
Touch-points:	memory_manager.dart.
Acceptance:	App start shows one “MemoryManager initialized ✓” line even with warm restarts or isolate re-creation.

General Dev Notes
Commit Hygiene – 1 PR per ticket above → easier QA & rollback.

Unit Tests first where indicated; wire to existing CI pipeline.

No scope-creep: Maya speaking user’s name will be handled in a later story once this persistence lands.