# Hybrid Startup Refactor Playbook

Goal: adopt a splash-first + lazy-load “hybrid” startup so critical services are online before the UI, while deferring the rest. This eliminates `GetIt` race conditions (e.g., `SessionScheduleService` not registered) without slowing the app launch.

---

## 1. Current Pain Points

- `setupServiceLocator()` eagerly registers almost everything, but API-dependent pieces (`IApiClient`, `SessionScheduleService`, etc.) arrive later inside `registerApiDependentServices()`.
- Widgets like `HomeScreen` request `SessionScheduleService` during `initState`, which fails if the API layer is still spinning up.
- We tried moving registrations to the lazy block, but the home screen can still run before that block finishes.

---

## 2. Target Flow

| Phase | What happens | Notes |
| --- | --- | --- |
| **Core boot** | Flutter bindings, feature flags, config, Firebase ensureInitialized, `setupServiceLocator()` | Blocks launch; only critical, deterministic work |
| **Background init** | `registerApiDependentServices()` (API client, repositories, schedule service, etc.) kicks off and calls `DependencyContainer.markReady()`/`markFailed()` | Resulting `Future` publishes readiness and errors globally |
| **Splash UI** | `MyApp` shows a splash while `backgroundInit` is in-flight | Can animate, show branding, surface retry UI on failure |
| **Main UI** | Once `backgroundInit` completes successfully, build router + home screens | All API-dependent services are now registered |
| **Lazy services** | Rare/expensive services remain `registerLazySingleton` | Created on first real use; selectively pre-warm latency-sensitive ones |

---

## 3. Step-by-Step Refactor

### Step 1 – Split startup into two phases

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final coreStopwatch = Stopwatch()..start();

  await setupCoreServices();                // wraps existing setupServiceLocator()
  coreStopwatch.stop();
  logger.info('[Startup] Core services ready in ${coreStopwatch.elapsedMilliseconds}ms');

  final backgroundInit = registerApiDependentServices(
    configService,
    apiClient,
  );                                         // returns Future<void>

  runApp(MyApp(backgroundInit: backgroundInit));
}
```

`setupCoreServices()` should house everything currently in `setupServiceLocator()` that does **not** require `IApiClient`.

Add readiness tracking to `DependencyContainer`:

```dart
class DependencyContainer {
  static final _readyCompleter = Completer<void>();

  static Future<void> whenReady() => _readyCompleter.future;

  static void markReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  static void markFailed(Object error, [StackTrace? stack]) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, stack);
    }
  }
}
```

Instrument `registerApiDependentServices()`:

```dart
Future<void> registerApiDependentServices(...) async {
  final bgStopwatch = Stopwatch()..start();
  try {
    // existing registration work
    DependencyContainer.markReady();
    bgStopwatch.stop();
    logger.info('[Startup] Background init complete in ${bgStopwatch.elapsedMilliseconds}ms');
  } catch (e, stack) {
    DependencyContainer.markFailed(e, stack);
    rethrow;
  }
}
```

### Step 2 – Adapt `MyApp`

```dart
class MyApp extends StatelessWidget {
  final Future<void> backgroundInit;
  const MyApp({required this.backgroundInit, super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: backgroundInit,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SplashScreen(
            error: snapshot.hasError ? snapshot.error : null,
            onRetry: snapshot.hasError ? () => DependencyContainer.whenReady() : null,
          );
        }
        return const MainAppRouter();
      },
    );
  }
}
```

This ensures we **never** navigate away from a splash until API-dependent services finish registration. If init fails, the splash can surface a retry button that re-listens to `DependencyContainer.whenReady()`.

### Step 3 – Keep secondary services lazy

Inside `setupServiceLocator()` leave the heavy or rarely used services as `registerLazySingleton` so they instantiate only when needed (audio pipeline, session reminders, graph analytics, etc.).

Example:
```dart
if (!serviceLocator.isRegistered<SessionScheduleService>()) {
  serviceLocator.registerLazySingleton(() => SessionScheduleService(
    apiClient: serviceLocator<IApiClient>(),      // safe now — will exist when accessed
    prefsManager: serviceLocator<PrefsManager>(),
  ));
}
```

### Step 4 – Guard interface bindings (already patched)

`ServicesModule.register()` should always check for the concrete service before exposing an interface:
```dart
if (locator.isRegistered<SessionScheduleService>() &&
    !locator.isRegistered<ISessionScheduleService>()) {
  locator.registerLazySingleton<ISessionScheduleService>(
    () => locator<SessionScheduleService>(),
  );
}
```

Prevents `GetIt` from resolving an interface whose concrete hasn’t been registered yet.

### Step 5 – Defer feature modules until ready

Wherever a widget kicks off async work that depends on API services (e.g., `_HomeScreenState._loadUserData`), gate it on `DependencyContainer.whenReady()` or the same `backgroundInit` future:

```dart
@override
void initState() {
  super.initState();
  DependencyContainer.whenReady().then((_) => _loadUserData());
}
```

Avoids fetching sessions or reminders before the HTTP auth flow has finished wiring tokens.

Pre-warm latency-sensitive lazy services while the splash is visible:

```dart
unawaited(serviceLocator<ITTSService>().prewarm());
unawaited(serviceLocator<AuthService>().refreshToken());
```

### Step 6 – Splash Experience (optional UX polish)

- Use the existing splash asset or design a branded animation.
- Optionally show status text (e.g., “Connecting to Maya…”) tied to the future progress.
- Add timeout handling (e.g., show a retry button if background init takes > 15s).

---

## 4. Testing Checklist

1. Launch the app repeatedly (hot + cold starts). Verify no `GetIt` errors.
2. Toggle network availability during splash; confirm the app shows a helpful message if `backgroundInit` fails (e.g., TimeoutException).
3. Log in/out scenarios: ensure `AuthService` remains ready before `registerApiDependentServices` runs again.
4. Validate GEMINI / OpenAI TTS still works after lazy initialization (audio pipeline should lazily wire itself).
5. Run integration tests to confirm `DependencyContainer` lookups succeed post-splash.
6. Simulate `registerApiDependentServices` failure to ensure the splash retry path works.

---

## 5. Rollout Tips

- Ship behind a feature flag (e.g., `USE_HYBRID_STARTUP`) to fall back quickly.
- Capture logs/analytics like `[Startup] Core services ready …` and `[Startup] Background init complete …` to tune cold-start performance.
- Monitor first-run crash stats after release.

---

## 6. Benefits Recap

- Eliminates race conditions (`SessionScheduleService` missing).
- Keeps startup responsive — core services ready immediately, others deferred.
- Aligns with production best practices for DI-heavy Flutter apps.

Once this refactor is in place, future service additions slot cleanly into either the “core” bucket (splash-blocking) or the “lazy” bucket without reopening startup timing bugs.

