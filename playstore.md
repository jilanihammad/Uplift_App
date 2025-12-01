# Play Store Launch Hardening Plan

Detailed remediation steps for the startup concerns observed in the SM S938U1 log capture. Execute the tasks in order so that logging, telemetry, feature flags, and backend wiring are solid before producing a release build.

---

## 1. Crashlytics Disabled in Production Builds
**Symptom**: `LoggingService` reports `Crashlytics: DISABLED` even though log level and analytics are enabled. Without Crashlytics you lose fatal-error visibility in production.

**Plan**
1. Update the logging/telemetry bootstrap to differentiate debug and release builds (e.g., via `kDebugMode` in Dart or `BuildConfig.DEBUG` on the Android shim) so Crashlytics toggles on automatically for all non-debug variants.
2. Ensure `FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true)` (Flutter) runs after Firebase initialization when `!kDebugMode`. Keep the current ability to disable via remote config if needed.
3. Remove any `FlutterError.onError` overrides that swallow exceptions in release mode. Route them to Crashlytics using `FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails)`.
4. Validate by building a `--release` APK, invoking a controlled crash, and verifying it appears in the Firebase console with symbolicated stack traces (requires uploading the `--split-debug-info` directory).

**Snippet**
```dart
final isRelease = kReleaseMode;
await FirebaseCrashlytics.instance
    .setCrashlyticsCollectionEnabled(isRelease && _remoteCrashlyticsEnabled);
FlutterError.onError = (details) {
  FlutterError.presentError(details);
  if (isRelease) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }
};
```

---

## 2. Feature Flags Initialized After Remote Overrides
**Symptom**: `[FeatureFlags] ERROR: Not initialized, cannot set memoryPersistenceEnabled` appears because remote-config overrides run before `FeatureFlags.init()` finishes.

**Plan**
1. In `main.dart`, reorder startup so `FeatureFlags.init()` completes before applying cached remote-config overrides. This usually means awaiting `FeatureFlags.initialize()` immediately after setting up shared preferences.
2. Wrap any `FeatureFlags.setFlag(...)` calls in a helper that early-returns if the store is not ready; log once to avoid log spam.
3. Add a unit test covering the scenario where cached remote config values exist so you know initialization order regressions fail locally.

**Snippet**
```dart
await FeatureFlags.instance.initialize(prefs);
await _applyCachedRemoteOverrides(); // no errors now
```

---

## 3. Duplicate Firebase Initialization
**Symptom**: Startup logs show `Firebase is not yet initialized...Error initializing Firebase: [core/duplicate-app]` before falling back to the existing `[DEFAULT]` instance.

**Plan**
1. Gate the initialization with `if (Firebase.apps.isEmpty)` (FlutterFire) or rely on the native `FirebaseApp.initializeApp()` being called exactly once in `Application#onCreate`.
2. Extract initialization into `FirebaseInitializer.ensureInitialized()` so both Android/iOS entry points and the Flutter bootstrap call the same guard.
3. Add a debug assertion that fails if duplicate initialization is attempted so the issue doesn’t regress.

**Snippet**
```dart
Future<FirebaseApp> ensureFirebaseInitialized() async {
  final apps = Firebase.apps;
  if (apps.isNotEmpty) {
    return Firebase.app();
  }
  return Firebase.initializeApp();
}
```

---

## 4. SQLite PRAGMA `journal_mode=WAL` Failure
**Symptom**: `DatabaseException ... PRAGMA journal_mode = WAL;` indicates the builder is executing the PRAGMA via an API that sqflite rejects.

**Plan**
1. Switch to `await db.rawQuery('PRAGMA journal_mode=WAL');` or `await db.execute('PRAGMA journal_mode=WAL');` depending on the driver you use (Drift vs plain sqflite). Sqflite requires `rawQuery` for PRAGMAs.
2. Only attempt WAL when `singleInstance=true`; otherwise skip to avoid repeated warnings.
3. Log the actual journal mode returned so QA can confirm WAL is active after open.
4. Add an instrumentation test that opens the DB and asserts `PRAGMA journal_mode` returns `wal` in release, ensuring reliability.

**Snippet**
```dart
if (!_journalModeChecked) {
  final result = await db.rawQuery('PRAGMA journal_mode=WAL;');
  _logger.debug('SQLite journal_mode => ${result.first.values.first}');
  _journalModeChecked = true;
}
```

---

## 5. Missing Backend Endpoints (`/system/tts-config`, `/mood_entries`)
**Symptom**: Startup fires GETs to `/system/tts-config` and `/mood_entries?limit=50`, both returning 404 which spams logs and may block mood syncing.

**Plan**
1. Confirm with backend whether these endpoints exist. If not, either disable the calls behind feature flags or point them to the correct `/api/v1/...` routes.
2. Add defensive handling in `ApiClient.get` so a 404 for optional bootstrap endpoints downgrades to `LogLevel.warn` and fails silently instead of throwing an exception that bubbles to the UI.
3. For mood persistence, ensure the client falls back to local cache if the remote endpoint is disabled. Queue unsynced entries and expose a `status` so QA knows sync is pending.
4. Once backend routes are available, update `api_client.dart` constants and add integration tests that mock the 404 vs 200 responses to guarantee graceful handling.

**Snippet**
```dart
try {
  final config = await _apiClient.get('/api/v1/system/tts-config');
  _applyRemoteTtsConfig(config);
} on ApiException catch (e) {
  if (e.statusCode == 404) {
    _logger.info('Remote TTS config unavailable; using defaults');
  } else {
    rethrow;
  }
}
```

---

## 6. Session Date Parsing Failure
**Symptom**: `FormatException: Invalid date format ... 2025-10-20T02:54:43.543280+00:00Z` occurs because the backend emits both an explicit offset and a trailing `Z`, which `DateTime.parse` rejects.

**Plan**
1. Fix the backend serializer to emit RFC 3339 data once (either `2025-10-20T02:54:43.543280Z` or `2025-10-20T02:54:43.543280+00:00`). For FastAPI/Pydantic, use `datetime.isoformat()` without manually appending `Z`.
2. Add a client-side fallback that normalizes bad inputs, e.g., replacing `+00:00Z` with `Z` before parsing so existing data doesn’t break the UI.
3. Write a regression test that feeds the problematic string into the parsing helper to ensure the fix holds.

**Snippet**
```dart
DateTime parseIso8601(String value) {
  final normalized = value.replaceFirst('+00:00Z', 'Z');
  return DateTime.parse(normalized);
}
```

---

## Validation Checklist
- [ ] Build `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols` and verify Crashlytics captures a forced crash.
- [ ] Run `flutter test` + widget test for feature-flag initialization order.
- [ ] Attach a debugger to confirm Firebase initializes only once.
- [ ] Inspect `logcat` for absence of PRAGMA and 404 warnings during cold start.
- [ ] Run backend integration tests for `/sessions`, `/system/tts-config`, and `/mood_entries`.
- [ ] Re-run the SM S938U1 scenario; startup logs should be clean aside from INFO-level service registrations.
