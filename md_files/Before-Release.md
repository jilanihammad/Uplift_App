# Before Release Checklist

Comprehensive actions to resolve the identified Google Play release blockers and harden the Maya (Uplift) Android client before submission.

## 1. Re-enable Firebase App Check in Production
**Problem**: `UpliftApplication` disables App Check, defeating the Play Integrity protection path you already scaffolded (`AppCheckProvidersManager`).
**Status**: ✅ Completed – `UpliftApplication` now initializes App Check in all builds.

**Fix Steps**
1. Update `UpliftApplication.kt` so `onCreate()` initializes App Check every time:
   ```kotlin
   override fun onCreate() {
       super.onCreate()
       FirebaseApp.initializeApp(this)
       AppCheckProvidersManager(this).initialize()
   }
   ```
2. In `AppCheckProvidersManager`, gate the debug provider behind `BuildConfig.DEBUG` so release always uses Play Integrity:
   ```kotlin
   val providerFactory = if (BuildConfig.DEBUG) {
       AppCheckDebugProviderFactory.getInstance()
   } else {
       PlayIntegrityAppCheckProviderFactory.getInstance()
   }
   FirebaseAppCheck.getInstance().installAppCheckProviderFactory(providerFactory)
   ```
3. Regenerate/rotate debug App Check tokens if needed.
4. Verify release builds fetch valid tokens (`adb logcat | grep AppCheckManager`).
5. Confirm backend validation accepts the new token (hit a protected endpoint and verify 200s).

**Tests**
- Add an Android instrumentation test (e.g., `AppCheckSmokeTest`) that launches a release build with Firebase App Check stubbed and asserts a Play Integrity token request occurs.
- Extend backend integration tests to validate App Check tokens from the app are accepted and failures are surfaced.
- During QA, monitor logcat for `AppCheckManager` entries while signing in and launching a session.

## 2. Remove Debug-Only App Check Dependency From Release
**Problem**: `firebase-appcheck-debug` is bundled, which Play treats as non-production.
**Status**: ✅ Completed – Gradle scopes `firebase-appcheck-debug` to `debugRuntimeOnly` and CI scripts enforce it.

**Fix Steps**
1. Scope the debug provider so it never lands in release artifacts. Example in `android/app/build.gradle`:
   ```gradle
   dependencies {
       implementation platform('com.google.firebase:firebase-bom:33.12.0')
       implementation 'com.google.firebase:firebase-appcheck-playintegrity'
       debugRuntimeOnly 'com.google.firebase:firebase-appcheck-debug'
   }
   ```
2. Alternatively, wrap the existing block with `releaseImplementation`/`debugRuntimeOnly` so release doesn’t pull the debug artefact.
3. Run `./gradlew app:dependencies --configuration releaseRuntimeClasspath` to ensure the debug dependency is gone.
4. Add a Gradle `doLast` check or CI script that fails if `firebase-appcheck-debug` appears in release configs.

**Tests**
- Add a Gradle build script check (e.g., in `app/build.gradle`) that fails CI if `firebase-appcheck-debug` appears in release configurations. This can be a custom `doLast` assertion.
- Generate a release AAB and run `./gradlew :app:verifyReleaseDependencies` ensuring the debug artefact is absent; integrate this command into CI.

## 3. Restore Fatal Error Handling in Release Builds
**Problem**: `BindingBase.debugZoneErrorsAreFatal = false` masks crashes in production.
**Status**: ✅ Completed (guarded in `lib/main.dart` – Dec 2025).

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
**Status**: ✅ Completed – manifest placeholders now point release builds at `network_security_config_release.xml` (HTTPS-only) while debug retains loopback access.

**Fix Steps**
1. Split configs per build type:
   - Keep permissive config (`network_security_config_debug.xml` with `cleartextTrafficPermitted="true"`) for debug/dev only.
   - Create `network_security_config_release.xml` with `<base-config cleartextTrafficPermitted="false">` and explicit `<domain-config>` for production hosts.
2. In `AndroidManifest.xml`, use manifest placeholders or Gradle `manifestPlaceholders` to point release builds at the strict XML while debug continues using the permissive one.
3. Restrict release trust anchors to system CAs only; do not honor user-added certificates.
4. Evaluate lightweight certificate pinning for the production backend domain (OkHttp `CertificatePinner` or WebSocket TLS verification) and document the rollout plan.
5. Confirm backend endpoints are HTTPS-only; remove `10.0.2.2`/`localhost` from release config.
6. Run `adb shell am instrument` (release build) to ensure API calls still succeed under the strict config.

**Tests**
- Add a unit test (e.g., using Robolectric) that loads the release network security XML and asserts `cleartextTrafficPermitted` is false and the trust anchors exclude user certificates.
- Include an integration test that attempts an HTTP call in release mode and expects failure, while HTTPS succeeds.
- Extend CI to run `./gradlew lintRelease` and fail on `SecurityConfig` issues, plus add a pin verification test if certificate pinning is enabled.

## 5. Make TTS Streaming Toggle Respect Config
**Problem**: `ttsStreamingEnabled` always returns `true`, ignoring `.env` overrides.
**Status**: ✅ Completed – `AppConfig.ttsStreamingEnabled` now honors `.env`, dart-defines, and Remote Config overrides with runtime fallbacks.

**Fix Steps**
1. Ensure the getter in `lib/config/app_config.dart` respects `.env`/dart defines (already done) and document the fallback order (Remote Config → `--dart-define` → `.env` → default true).
2. Keep the runtime override layer (`RemoteConfigService`) so Remote Config can disable streaming mid-flight and persist last-known-good values via SharedPreferences.
3. Maintain the lazy TTS config prefetch/lazy fetch path so disabling streaming doesn’t block startup.
4. Run the app with `TTS_STREAMING_ENABLED=false` locally and confirm the remote toggle can disable streaming at runtime.

**Tests**
- Add a Dart unit test for `AppConfig` verifying the getter returns true/false/falsey as expected for different env inputs.
- Introduce a Flutter integration test that disables streaming (via `--dart-define`) and verifies the voice pipeline skips streaming branches.
- Add an integration/e2e test harness that simulates a remote-config update during a session and asserts `VoiceSessionBloc` transitions to the non-streaming path without restarting the app.
- Monitor performance benchmarks to ensure the switch does not regress response times when toggled.
- Automated coverage: `test/tts_kill_switch_test.dart` validates kill-switch overrides and buffer/memory updates.

## 6. Revalidate Sensitive Android Permissions
**Problem**: Manifest requests `DISABLE_KEYGUARD`, `TURN_SCREEN_ON`, `RECEIVE_BOOT_COMPLETED`, and `POST_NOTIFICATIONS`.
**Status**: ✅ Completed – manifest only requests essential permissions (INTERNET, RECORD_AUDIO, POST_NOTIFICATIONS w/ runtime consent, VIBRATE, WAKE_LOCK) with inline comments explaining their use; no sensitive legacy permissions remain.

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
**Status**: ✅ Completed – use `tools/scan_release.sh build/app/outputs/flutter-apk/app-release.apk` to unzip and scan release APKs for common secret patterns.

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
**Status**: ✅ Completed – Settings already surfaces Privacy Policy/Terms links, in-app crisis resources, and an account deletion flow that opens `AppConfig.accountDeletionUrl`. Release signing + Crashlytics wiring verified via `tools/build_release_aab.sh` + Crashlytics upload reminder.

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
**Status**: ✅ Completed – `tools/build_release_aab.sh` enforces `--obfuscate --split-debug-info=build/symbols`; remember to run `firebase crashlytics:symbols:upload` after each build.

**Fix Steps**
1. Update release build commands to include `--obfuscate --split-debug-info=build/symbols` for both APK and AAB outputs (`flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`).
2. Ensure the CI/CD pipeline archives `build/symbols` artifacts per release build and uploads them to Crashlytics (`firebase crashlytics:symbols:upload --app=<id> build/symbols`).
3. Verify native/Java/Kotlin code does not rely on reflection of obfuscated Flutter names; adjust ProGuard rules if needed.

**Tests**
- Run `flutter build appbundle --obfuscate --split-debug-info=build/symbols` and install on a test device to confirm no runtime regressions.
- Trigger a controlled crash and confirm the stack trace can be symbolicated using the uploaded debug info.

## 10. Split Per-ABI & Optimize Package Size
**Problem**: Single-universal APKs increase download size and install time.
**Status**: ✅ Completed – Gradle `splits { abi { ... } }` already generates ABI-specific APKs for release/profile builds while keeping `minifyEnabled`/`shrinkResources` true.

**Fix Steps**
1. Enable ABI splits in `android/app/build.gradle` (armeabi-v7a, arm64-v8a, x86_64) with `universalApk false`.
2. Keep `minifyEnabled true` and `shrinkResources true`; audit ProGuard rules to ensure only required keep rules are present.
3. Update release build scripts to publish the generated AAB (which already supports ABI splits) and, if distributing APKs, upload the per-ABI variants. Document which APK maps to which ABI for QA.

**Tests**
- Build the release variant and inspect generated outputs to ensure per-ABI APKs are produced when desired.
- Install each ABI build on representative hardware (or emulator) to confirm startup latency and audio streaming remain unaffected.

## 11. Foreground Service Compliance for Android 14+
**Problem**: Android 14 requires explicit foreground service types when recording or playing audio in the background.
**Status**: 🚧 Pending – service declarations/notifications still need to be audited.

**Fix Steps**
1. Audit whether recording or playback can occur while the app is backgrounded. If yes, declare a foreground service with `android:foregroundServiceType="microphone|mediaPlayback"` (or limit behavior to foreground-only).
2. Ensure the service posts an ongoing notification when active (e.g., `NotificationCompat.Builder` with `setOngoing(true)`) and stops immediately once recording/playback ends or the app returns to foreground-only mode.
3. Review lifecycle callbacks to guarantee recording stops when backgrounded if foreground service is not used.

**Tests**
- Add instrumentation tests simulating home-button/background transitions while recording to confirm compliance (service starts/stops, notification shown, no policy violations).
- Manually test on Android 14 hardware/emulators to verify system warnings are not raised.

## 12. Protect Data at Rest & Backup Policies
**Problem**: Auth tokens and session data stored in plain SharedPreferences/SQLite risk compromise if the device is rooted or backed up.
**Status**: ✅ Completed – auth tokens now live in `FlutterSecureStorage` (AES), and `android:allowBackup="false"` blocks OS backups.

**Fix Steps**
1. Store sensitive values (JWTs, refresh tokens, long-lived anchors) in encrypted storage—e.g., Android Jetpack Security (via platform channel) or `flutter_secure_storage` with AES.
2. Set `android:allowBackup="false"` (or provide a scoped `data-extraction-rules.xml`) to prevent automatic cloud/device backups of therapy transcripts.
3. Document key rotation and logout flows that wipe encrypted storage; ensure logout clears secure storage + local DB rows.

**Tests**
- Add unit tests around the storage abstraction to confirm values are encrypted and decrypted correctly, with corruption handling.
- Run instrumentation tests verifying data is cleared on logout/account deletion.
- Use `adb backup` (legacy) or `adb shell bmgr` checks to ensure data is excluded when backups are disabled/scoped.

## 13. Audio Focus & Interrupt Regression Coverage
**Problem**: Audio routes (Bluetooth, phone calls, notifications) can regress the streaming flow if not exhaustively tested.
**Status**: 🚧 Pending – more instrumentation/manual coverage required.

**Fix Steps**
1. Use integration tests or scripted manual runs to cover Bluetooth headset connect/disconnect, phone call interruptions, and notification ducking scenarios.
2. Ensure the interrupt acknowledgment pipeline cancels active TTS playback, resets VAD, and resumes correctly after the interruption.
3. Verify wakelock handling only holds locks during active capture/playback and releases them on lifecycle changes.

**Tests**
- Add automated tests (where feasible) leveraging Android instrumentation APIs to simulate audio focus changes and assert correct state transitions in `VoiceSessionBloc`.
- Expand manual QA scripts to include headset and call scenarios with logging verification.

## 14. Post-Release Safeguards & Hardening Tasks
**Problem**: Feature flags and networking need ongoing hygiene to avoid stale states and dropped connections.
**Status**: ⚠️ Partially complete – feature-flag initialization improvements landed, but migration scripts, ping/pong hardening, and keep rules still need work.

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
