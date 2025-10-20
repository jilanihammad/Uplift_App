# Before Release Checklist

Comprehensive actions to resolve the identified Google Play release blockers and harden the Maya (Uplift) Android client before submission.

## 1. Re-enable Firebase App Check in Production
**Problem**: `UpliftApplication` disables App Check, defeating the Play Integrity protection path you already scaffolded (`AppCheckProvidersManager`).

**Fix Steps**
1. Update `UpliftApplication.kt` to delegate to `AppCheckProvidersManager.initialize()` instead of skipping App Check.
   ```kotlin
   override fun onCreate() {
       super.onCreate()
       FirebaseApp.initializeApp(this)
       AppCheckProvidersManager(this).initialize()
   }
   ```
2. Guard the fallback debug provider so it is only used for dev builds (`BuildConfig.DEBUG`).
3. Regenerate or rotate debug App Check tokens if you intend to keep debug testing.
4. Verify release builds fetch valid App Check tokens (`adb logcat | grep AppCheckManager`).
5. Confirm backend validation accepts the new Play Integrity token.

**Tests**
- Add an Android instrumentation test (e.g., `AppCheckSmokeTest`) that launches a release build with Firebase App Check stubbed and asserts a Play Integrity token request occurs.
- Extend backend integration tests to validate App Check tokens from the app are accepted and failures are surfaced.
- During QA, monitor logcat for `AppCheckManager` entries while signing in and launching a session.

## 2. Remove Debug-Only App Check Dependency From Release
**Problem**: `firebase-appcheck-debug` is bundled, which Play treats as non-production.

**Fix Steps**
1. In `android/app/build.gradle` remove the debug provider from release builds:
   ```gradle
   dependencies {
       releaseImplementation platform('com.google.firebase:firebase-bom:33.12.0')
       releaseImplementation 'com.google.firebase:firebase-appcheck-playintegrity'
       debugImplementation 'com.google.firebase:firebase-appcheck-debug'
   }
   ```
2. If you prefer a single block, use `implementation` + `debugRuntimeOnly` to keep it out of the release APK.
3. Run `./gradlew app:dependencies --configuration releaseRuntimeClasspath` to ensure the debug dependency is gone.

**Tests**
- Add a Gradle build script check (e.g., in `app/build.gradle`) that fails CI if `firebase-appcheck-debug` appears in release configurations. This can be a custom `doLast` assertion.
- Generate a release AAB and run `./gradlew :app:verifyReleaseDependencies` ensuring the debug artefact is absent; integrate this command into CI.

## 3. Restore Fatal Error Handling in Release Builds
**Problem**: `BindingBase.debugZoneErrorsAreFatal = false` masks crashes in production.

**Fix Steps**
1. Wrap that assignment in a debug guard:
   ```dart
   if (kDebugMode) {
     BindingBase.debugZoneErrorsAreFatal = false;
   }
   ```
2. Audit other `debugPrint` / `print` usage in release-only paths; swap for structured logging that respects release privacy settings.
3. Re-run instrumentation / smoke tests to confirm no hard crashes occur after removing the suppression.

**Tests**
- Add a Flutter widget test that triggers an intentional exception and asserts it bubbles up only in debug mode (`expect(() => runZonedGuarded(...), throwsA(...))`).
- Run existing integration tests in release mode (`flutter drive --flavor release`) to ensure no silent failures surface.

## 4. Lock Down Cleartext Network Access
**Problem**: `network_security_config.xml` allows HTTP traffic to production and localhost, which Play security review often flags.

**Fix Steps**
1. Split configs per build type:
   - Keep permissive config (`cleartextTrafficPermitted="true"`) for debug/dev.
   - Create a stricter release config that only permits HTTPS domains.
2. In `AndroidManifest.xml` set `android:networkSecurityConfig` via product flavors/build types so release points to the strict file.
3. Restrict release trust anchors to system CAs only; do not honor user-added certificates.
4. Evaluate lightweight certificate pinning for the production backend domain (OkHttp/HTTP client pinning or WebSocket verification) and document the rollout plan.
5. Confirm backend endpoints are HTTPS-only; remove `10.0.2.2`/`localhost` from release config.
6. Run `adb shell am instrument` to ensure API calls still succeed in release mode.

**Tests**
- Add a unit test (e.g., using Robolectric) that loads the release network security XML and asserts `cleartextTrafficPermitted` is false and the trust anchors exclude user certificates.
- Include an integration test that attempts an HTTP call in release mode and expects failure, while HTTPS succeeds.
- Extend CI to run `./gradlew lintRelease` and fail on `SecurityConfig` issues, plus add a pin verification test if certificate pinning is enabled.

## 5. Make TTS Streaming Toggle Respect Config
**Problem**: `ttsStreamingEnabled` always returns `true`, ignoring `.env` overrides.

**Fix Steps**
1. Update the getter in `lib/config/app_config.dart` to respect the env default:
   ```dart
   bool get ttsStreamingEnabled =>
       dotenv.env['TTS_STREAMING_ENABLED']?.toLowerCase() == 'true';
   ```
   Provide an explicit default if needed (e.g., `?? false`).
2. Introduce a runtime override layer (Firebase Remote Config or a signed `/config` endpoint) that updates `AppConfig` values after startup. Fallback order: remote config → `--dart-define` → `.env` → hardcoded default.
3. Expose a remote kill switch for streaming/TTS that can be toggled without a rebuild and persists the last known good value locally for offline safety.
4. Document the expected `.env` keys, remote-config parameter names, and staging defaults.
5. Run the app with `TTS_STREAMING_ENABLED=false` locally and confirm the remote toggle can disable streaming at runtime.

**Tests**
- Add a Dart unit test for `AppConfig` verifying the getter returns true/false/falsey as expected for different env inputs.
- Introduce a Flutter integration test that disables streaming (via `--dart-define`) and verifies the voice pipeline skips streaming branches.
- Add an integration/e2e test harness that simulates a remote-config update during a session and asserts `VoiceSessionBloc` transitions to the non-streaming path without restarting the app.
- Monitor performance benchmarks to ensure the switch does not regress response times when toggled.
- Automated coverage: `test/tts_kill_switch_test.dart` validates kill-switch overrides and buffer/memory updates.

## 6. Revalidate Sensitive Android Permissions
**Problem**: Manifest requests `DISABLE_KEYGUARD`, `TURN_SCREEN_ON`, `RECEIVE_BOOT_COMPLETED`, and `POST_NOTIFICATIONS`.

**Fix Steps**
1. Confirm each permission is essential. If not required, delete it.
2. For required ones, ensure runtime consent flows exist (e.g., notifications on Android 13+).
3. Prepare Play Console answers explaining usage (Data Safety + sensitive permissions questionnaire).
4. Run `./gradlew app:lintRelease` to catch missing permission justifications (e.g., `QUERY_ALL_PACKAGES`).

**Tests**
- Add automated UI tests (Espresso/Flutter integration) covering notification opt-in flows and wake-lock toggling.
- After removing any permission, run regression cases that rely on the affected capability (e.g., background wakeup, notification delivery) in integration tests.

## 7. Remove Secrets and Debug Artefacts From the APK
**Problem**: Plain-text secrets (`Groq API key.txt`, `.env`) and verbose logs risk leaking sensitive info.

**Fix Steps**
1. Ensure `.env` and any credentials are excluded from the packaged assets. For release, embed only the necessary constants via `--dart-define`.
2. Delete or move `Groq API key.txt` and similar files out of the project/workspace before building.
3. Replace `print`/`Log.d` statements that log PII with guarded or redacted logging.
4. Re-run a release build (`flutter build apk --release`) and inspect the resulting APK (`apktool`, `aapt dump strings`) to verify no secrets remain.

**Tests**
- Add a CI step that explodes the release AAB/APK and scans for known secret patterns (use a script or `trufflehog`-style check).
- Ensure unit tests for logging components redact sensitive data; add assertions where necessary.
- Incorporate a regression test that verifies env-configured API keys resolve from runtime configuration, not static assets.

## 8. Compliance & Store Review Preparation
**Problem**: Play review requires validated privacy, crash reporting, and analytics behaviour.

**Fix Steps**
1. Confirm Firebase Analytics usage matches declared privacy policy; offer opt-out if mandated by locale.
2. Add or update the in-app privacy policy link if required by Play (Settings/About screens).
3. Provide in-app disclosures that the conversations are AI-assisted and not a substitute for licensed care; surface region-specific crisis hotline links from the chat screen.
4. Implement an in-app account deletion request flow that calls the backend (or deep-links to an authenticated deletion page) and document the backend purge path.
5. Prepare Data Safety form responses (collects audio, stores transcripts). Align with actual persistence in `memory_manager` and backend DB.
6. Validate release signing setup (`key.properties` external to source control) and run `./gradlew bundleRelease` to produce an optimized AAB for upload.

**Tests**
- Add an integration/UI test validating the privacy policy and AI disclosure links are visible, tappable, and open the correct destinations.
- Add automated coverage to ensure the account deletion entry is reachable, triggers the deletion API, and surfaces success/failure states.
- Run backend integration tests ensuring data retention policies (session memory, audio logs) honor user opt-out requests and purge flows.
- Perform load/performance tests after final optimizations to confirm no regressions in latency or startup times.

## 9. Enable Flutter Obfuscation & Symbol Management
**Problem**: Without obfuscation, shipped binaries expose symbol names; missing debug symbols makes crash triage harder.

**Fix Steps**
1. Update release build commands to include `--obfuscate --split-debug-info=build/symbols` for both APK and AAB outputs.
2. Ensure the CI/CD pipeline archives `build/symbols` artifacts per release build and uploads them to your crash-reporting backend (Firebase Crashlytics or Sentry) for de-obfuscation.
3. Verify native/Java/Kotlin code does not rely on reflection of obfuscated Flutter names; adjust ProGuard rules if needed.

**Tests**
- Run `flutter build appbundle --obfuscate --split-debug-info=build/symbols` and install on a test device to confirm no runtime regressions.
- Trigger a controlled crash and confirm the stack trace can be symbolicated using the uploaded debug info.

## 10. Split Per-ABI & Optimize Package Size
**Problem**: Single-universal APKs increase download size and install time.

**Fix Steps**
1. Enable ABI splits in `android/app/build.gradle` (armeabi-v7a, arm64-v8a, x86_64) with `universalApk false`.
2. Keep `minifyEnabled true` and `shrinkResources true`; audit ProGuard rules to ensure only required keep rules are present.
3. Update release build scripts to publish the generated AAB (which already supports ABI splits) and, if distributing APKs, upload the per-ABI variants.

**Tests**
- Build the release variant and inspect generated outputs to ensure per-ABI APKs are produced when desired.
- Install each ABI build on representative hardware (or emulator) to confirm startup latency and audio streaming remain unaffected.

## 11. Foreground Service Compliance for Android 14+
**Problem**: Android 14 requires explicit foreground service types when recording or playing audio in the background.

**Fix Steps**
1. Audit whether recording or playback can occur while the app is backgrounded. If yes, declare a foreground service with `android:foregroundServiceType="microphone|mediaPlayback"` (or limit behavior to foreground-only).
2. Ensure the service posts an ongoing notification when active and stops immediately once recording/playback ends or the app returns to foreground-only mode.
3. Review lifecycle callbacks to guarantee recording stops when backgrounded if foreground service is not used.

**Tests**
- Add instrumentation tests simulating home-button/background transitions while recording to confirm compliance (service starts/stops, notification shown, no policy violations).
- Manually test on Android 14 hardware/emulators to verify system warnings are not raised.

## 12. Protect Data at Rest & Backup Policies
**Problem**: Auth tokens and session data stored in plain SharedPreferences/SQLite risk compromise if the device is rooted or backed up.

**Fix Steps**
1. Store sensitive values (JWTs, refresh tokens, long-lived anchors) in encrypted storage—e.g., Android Jetpack Security via a small platform channel, or wrap Drift with SQLCipher.
2. Set `android:allowBackup="false"` (or provide a scoped `data-extraction-rules.xml`) to prevent automatic cloud/device backups of therapy transcripts.
3. Document key rotation and logout flows that wipe encrypted storage.

**Tests**
- Add unit tests around the storage abstraction to confirm values are encrypted and decrypted correctly, with corruption handling.
- Run instrumentation tests verifying data is cleared on logout/account deletion.
- Use `adb backup` (legacy) or `adb shell bmgr` checks to ensure data is excluded when backups are disabled/scoped.

## 13. Audio Focus & Interrupt Regression Coverage
**Problem**: Audio routes (Bluetooth, phone calls, notifications) can regress the streaming flow if not exhaustively tested.

**Fix Steps**
1. Use integration tests or scripted manual runs to cover Bluetooth headset connect/disconnect, phone call interruptions, and notification ducking scenarios.
2. Ensure the interrupt acknowledgment pipeline cancels active TTS playback, resets VAD, and resumes correctly after the interruption.
3. Verify wakelock handling only holds locks during active capture/playback and releases them on lifecycle changes.

**Tests**
- Add automated tests (where feasible) leveraging Android instrumentation APIs to simulate audio focus changes and assert correct state transitions in `VoiceSessionBloc`.
- Expand manual QA scripts to include headset and call scenarios with logging verification.

## 14. Post-Release Safeguards & Hardening Tasks
**Problem**: Feature flags and networking need ongoing hygiene to avoid stale states and dropped connections.

**Fix Steps**
1. Migrate stored feature flags on upgrade to keep users aligned with current defaults and prevent stale experimental paths.
2. Configure WebSocket ping/pong intervals on both client and server to maintain long-lived streaming sessions on flaky networks.
3. Add or confirm ProGuard keep rules for any Java/Kotlin classes invoked through method channels or reflection (`-keep class com.maya.uplift.** { *; }`).

**Tests**
- Add regression tests to ensure feature flag migrations work across multiple app versions.
- Include integration tests verifying WebSocket ping/pong handlers keep the connection alive and recover from temporary drops.
- Run a release build with `./gradlew app:lintRelease` and inspect the mapping to confirm no required classes were stripped.

---

**Validation Run**
- Build: `flutter clean && flutter pub get` then `flutter build appbundle --obfuscate --split-debug-info=build/symbols` (and per-ABI APKs if required).
- Tests: `flutter test`, `flutter analyze`, remote-config kill switch integration test, WebSocket stability tests, `./gradlew lintRelease`, `./gradlew app:dependencies --configuration releaseRuntimeClasspath`, backend smoke tests.
- Security/Compliance: secret scan on release artifacts, account deletion flow test, network security XML unit tests, certificate pinning validation (if enabled).
- Final manual QA: voice session, onboarding, notification flow, background resume, audio focus scenarios (Bluetooth/call), crisis hotline links, account deletion request.
