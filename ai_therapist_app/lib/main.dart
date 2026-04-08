// lib/main.dart
// Trivial change to trigger linter
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart' show BindingBase, kDebugMode, kReleaseMode;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ai_therapist_app/config/routes.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/blocs/auth/auth_bloc.dart';
import 'package:ai_therapist_app/blocs/auth/auth_events.dart';
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';
import 'package:ai_therapist_app/services/user_profile_service.dart';
import 'package:ai_therapist_app/services/onboarding_service.dart';
import 'package:ai_therapist_app/services/auth_coordinator.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/audio_player_manager.dart';
import 'package:ai_therapist_app/utils/app_logger.dart';
import 'package:ai_therapist_app/services/remote_config_service.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/services/firebase_service.dart';
import 'package:ai_therapist_app/config/theme.dart';
import 'package:ai_therapist_app/config/app_config.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/utils/error_handling.dart';
import 'package:ai_therapist_app/services/theme_service.dart';
import 'package:ai_therapist_app/data/datasources/local/database_provider.dart';
import 'services/path_manager.dart';
import 'services/foreground_audio_guard.dart';
import 'package:ai_therapist_app/utils/firebase_init.dart';
import 'package:ai_therapist_app/utils/logging_service.dart';
import 'utils/logging_config.dart';
import 'utils/database_helper.dart';
import 'utils/feature_flags.dart';
ConfigService? _configService;
ApiClient? _apiClient;
bool _crashlyticsEnabled = false;
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await ensureFirebaseInitialized();
}
class SimpleBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
  }
}
void _handleGlobalError(dynamic error, StackTrace stack) {
  logger.error(
    'Uncaught global error',
    error: error,
    stackTrace: stack,
    tag: 'GLOBAL',
  );
  String errorMessage = 'An unexpected error occurred';
  if (error is SocketException) {
    errorMessage =
        'Network connection error. Please check your internet connection and try again.';
  } else if (error is TimeoutException) {
    errorMessage = 'Connection timed out. Please try again later.';
  } else if (error is ApiException) {
    errorMessage = error.message;
  } else if (error.toString().contains('semaphore timeout')) {
    errorMessage = 'Server connection timed out. Please try again later.';
  }
  logger.warning('Error message for user: $errorMessage', tag: 'USER_ERROR');
  if (_crashlyticsEnabled) {
    FirebaseCrashlytics.instance
        .recordError(error, stack, reason: 'Global error', fatal: false);
  }
}
Future<void> setupCoreServices() async {
  logger.info('[Main] Starting app initialization.');
  // Note: WidgetsFlutterBinding.ensureInitialized() now called in main()
  logger.info('[Main] Setting up core services...');
  await AppConfig.initialize();
  AppConfig().logConfig();
  logger.info('[Main] AppConfig initialized with environment variables.');
  await FeatureFlags.init();
  FeatureFlags.debugPrintFlags();
  logger.info('[Main] FeatureFlags initialized with SharedPreferences.');
  await RemoteConfigService().preloadCachedOverrides();
  logger.info('[Main] Applied cached remote-config overrides.');
  final firebaseApp = await ensureFirebaseInitialized();
  if (firebaseApp != null) {
    logger.info(
        '[Main] Firebase initialized successfully via ensureFirebaseInitialized(): ${firebaseApp.name}');
    await _configureCrashlytics();
    // NOTE: RemoteConfigService().initialize() moved to background init
    logger.info('[Main] Remote config network fetch deferred to background.');
  } else {
    logger.warning(
        '[Main] Could not initialize Firebase via ensureFirebaseInitialized(), some features may be limited');
  }
  try {
    Firebase.app();
    FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler);
    logger.info('[Main] Background messaging handler registered.');
  } catch (e) {
    logger.warning(
        '[Main] Firebase not available for background messaging handler registration or error: $e');
  }
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    final stack = details.stack ?? StackTrace.current;
    _handleGlobalError(details.exception, stack);
    if (_crashlyticsEnabled) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    _handleGlobalError(error, stack);
    if (_crashlyticsEnabled) {
      FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: true, reason: 'Platform error');
    }
    return false;
  };
  final useNewVoicePipeline = FeatureFlags.useNewVoicePipeline;
  logger.info(
      '[Main] Feature flag useRefactoredVoicePipeline = $useNewVoicePipeline');
  try {
    await setupServiceLocator(
      useRefactoredVoicePipeline: useNewVoicePipeline,
    );
    logger.info('[Main] Service locator setup complete.');
    ForegroundAudioGuard();
  } catch (e) {
    logger.error('[Main] ERROR during service locator setup', error: e);
  }
  logger.info('[Main] Initializing app database connection...');
  try {
    final appDatabase = DependencyContainer().appDatabaseConcrete;
    await appDatabase.database;
    logger.info('[Main] Database connection established.');
  } catch (e) {
    logger.error('[Main] ERROR initializing database connection', error: e);
  }
}
Future<void> _startBackgroundInitialization() async {
  DependencyContainer.resetReady();
  final bgStopwatch = Stopwatch()..start();
  try {
    try {
      await RemoteConfigService().initialize();
      logger.info('[Main] Remote config fetched and applied in background.');
    } catch (e) {
      logger.warning('[Main] Remote config background fetch failed: $e');
    }
    await _initializeFirebaseServices();
    await _initializeConfigAndApi();
    try {
      if (serviceLocator.isRegistered<AudioPlayerManager>()) {
        final audioPlayer = serviceLocator<AudioPlayerManager>();
        await audioPlayer.prewarmPlayer();
      }
    } catch (e) {
      logger.warning('[Main] Audio player prewarm failed (non-fatal): $e');
    }
    bgStopwatch.stop();
    logger.info('[Startup] Background init pipeline finished in '
        '${bgStopwatch.elapsedMilliseconds}ms');
  } catch (e, stack) {
    bgStopwatch.stop();
    logger.error('[Startup] Background init failed',
        error: e, stackTrace: stack);
    DependencyContainer.markFailed(e, stack);
    rethrow;
  }
}
Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.initialize();
    await PathManager.instance.init();
    _initializeLogging();
    final coreStopwatch = Stopwatch()..start();
    await setupCoreServices();
    coreStopwatch.stop();
    logger.info(
        '[Startup] Core services ready in ${coreStopwatch.elapsedMilliseconds}ms');
    final backgroundInitFuture = _startBackgroundInitialization();
    runApp(AiTherapistApp(
      initialBackgroundInit: backgroundInitFuture,
      backgroundInitBuilder: _startBackgroundInitialization,
    ));
  }, (error, stack) {
    logger.error('[Main] Uncaught error in runZonedGuarded');
    _handleGlobalError(error, stack);
    if (_crashlyticsEnabled) {
      FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: true, reason: 'Zone error');
    }
  });
}
void _initializeLogging() {
  loggingConfig.init(
    enableVerboseLogsInRelease: false,
    enableVerboseDebug: false,
  );
  logger
      .info('Logging initialized with level: ${loggingConfig.currentLogLevel}');
  logger.debug(
      'Debug logging is ${loggingConfig.isDebugEnabled ? 'enabled' : 'disabled'}');
}
Future<void> _configureCrashlytics() async {
  final shouldEnable = kReleaseMode;
  try {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(shouldEnable);
    _crashlyticsEnabled = shouldEnable;
    logger.setCrashlyticsEnabled(shouldEnable);
  } catch (e) {
    _crashlyticsEnabled = false;
    logger.warning('Failed to configure Crashlytics: $e',
        tag: 'CRASHLYTICS_INIT');
  }
}
Future<void> _requestNotificationPermissions() async {
  try {
    if (!serviceLocator.isRegistered<FirebaseService>()) {
      return;
    }
    await safeOperation(
      () async {
        final firebaseService = serviceLocator<FirebaseService>();
        await firebaseService.initMessaging();
      },
      timeoutSeconds: 12, // Increased from 8
      operationName: 'Notification permissions setup',
    );
  } catch (e) {}
}
class AiTherapistApp extends StatefulWidget {
  final Future<void> initialBackgroundInit;
  final Future<void> Function() backgroundInitBuilder;
  const AiTherapistApp({
    super.key,
    required this.initialBackgroundInit,
    required this.backgroundInitBuilder,
  });
  @override
  State<AiTherapistApp> createState() => _AiTherapistAppState();
}
class _AiTherapistAppState extends State<AiTherapistApp> {
  late ThemeService _themeService;
  late Future<void> _backgroundInit;
  bool _postInitScheduled = false;
  bool _showMainApp = false;
  Timer? _completionDelayTimer;
  @override
  void initState() {
    super.initState();
    _backgroundInit = widget.initialBackgroundInit;
    try {
      if (serviceLocator.isRegistered<ThemeService>()) {
        _themeService = serviceLocator<ThemeService>();
        _initTheme();
      } else {
        _themeService = ThemeService();
        _initTheme();
      }
    } catch (e) {
      _themeService = ThemeService();
    }
  }
  Future<void> _initTheme() async {
    try {
      await _themeService.init();
      if (mounted) setState(() {});
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _backgroundInit,
      builder: (context, snapshot) {
        final bool isDone = snapshot.connectionState == ConnectionState.done;
        if (isDone && snapshot.hasError) {
          _completionDelayTimer?.cancel();
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: HybridStartupSplash(
              key: const ValueKey('startup-error'),
              error: snapshot.error,
              onRetry: () {
                logger.info('Startup retry requested from splash');
                _restartBackgroundInit();
              },
            ),
          );
        }
        if (isDone && !_showMainApp) {
          _schedulePostInit();
          _scheduleCompletionReveal();
        }
        final bool showSplash = !isDone || !_showMainApp;
        final Widget target = showSplash
            ? HybridStartupSplash(
                key: ValueKey(isDone ? 'startup-finishing' : 'startup-loading'),
                isFinishing: isDone,
              )
            : _buildMainAppWithKey();
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: target,
        );
      },
    );
  }
  @override
  void dispose() {
    _completionDelayTimer?.cancel();
    _cleanupResources();
    super.dispose();
  }
  Future<void> _cleanupResources() async {
    try {
      if (serviceLocator.isRegistered<AppDatabase>()) {
        final appDatabase = DependencyContainer().appDatabaseConcrete;
        await appDatabase.close();
      }
      if (serviceLocator.isRegistered<AuthBloc>()) {
        try {
          final authBloc = serviceLocator<AuthBloc>();
          await authBloc.close();
          logger.info('[AiTherapistApp] AuthBloc closed successfully');
        } catch (e) {
          logger.debug('[AiTherapistApp] Could not close AuthBloc: $e');
        }
      }
    } catch (_) {}
  }
  void _schedulePostInit() {
    if (_postInitScheduled) return;
    _postInitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initializeHeavyServices();
    });
  }
  void _scheduleCompletionReveal() {
    _completionDelayTimer?.cancel();
    _completionDelayTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() {
        _showMainApp = true;
      });
    });
  }
  void _restartBackgroundInit() {
    DependencyContainer.resetReady();
    _completionDelayTimer?.cancel();
    setState(() {
      _postInitScheduled = false;
      _showMainApp = false;
      _backgroundInit = widget.backgroundInitBuilder();
    });
  }
  Widget _buildMainAppWithKey() {
    return KeyedSubtree(
      key: const ValueKey('main-app'),
      child: _buildMainApp(),
    );
  }
  Widget _buildMainApp() {
    return ErrorBoundary(
      child: ChangeNotifierProvider.value(
        value: _themeService,
        child: Consumer<ThemeService>(
          builder: (context, themeService, _) {
            return MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>(
                  create: (context) {
                    try {
                      if (serviceLocator.isRegistered<AuthService>()) {
                        final authBloc = AuthBloc(
                          authService: serviceLocator<AuthService>(),
                        )..add(CheckAuthStatusEvent());
                        return authBloc;
                      } else {
                        final authBloc = AuthBloc(
                          authService: AuthService(
                            userProfileService: UserProfileService(),
                            authEventHandler: AuthCoordinator(
                              onboardingService: OnboardingService(),
                            ),
                          ),
                        );
                        if (!serviceLocator.isRegistered<AuthBloc>()) {
                          serviceLocator.registerSingleton<AuthBloc>(authBloc);
                          logger.debug(
                              '[AiTherapistApp] Minimal AuthBloc registered in service locator');
                        }
                        return authBloc;
                      }
                    } catch (e) {
                      final authBloc = AuthBloc(
                        authService: AuthService(
                          userProfileService: UserProfileService(),
                          authEventHandler: AuthCoordinator(
                            onboardingService: OnboardingService(),
                          ),
                        ),
                      );
                      if (!serviceLocator.isRegistered<AuthBloc>()) {
                        serviceLocator.registerSingleton<AuthBloc>(authBloc);
                        logger.debug(
                            '[AiTherapistApp] Fallback AuthBloc registered in service locator');
                      }
                      return authBloc;
                    }
                  },
                ),
              ],
              child: MaterialApp.router(
                title: 'Maya',
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeService.themeMode,
                debugShowCheckedModeBanner: false,
                routerConfig: AppRouter.router,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [
                  Locale('en', ''), // English
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  const ErrorBoundary({super.key, required this.child});
  @override
  _ErrorBoundaryState createState() => _ErrorBoundaryState();
}
class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  dynamic _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasError = false;
    _error = null;
  }
  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      final errorTheme = ThemeData(
        primaryColor: Colors.red,
        primarySwatch: Colors.red,
        colorScheme: const ColorScheme.light(primary: Colors.red),
      );
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: errorTheme,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', ''), // English
        ],
        home: Scaffold(
          appBar: AppBar(
            title: const Text('App Error'),
            backgroundColor: Colors.red,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 60,
                ),
                const SizedBox(height: 16),
                const Text(
                  'An unexpected error occurred',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _error?.toString() ?? 'Unknown error',
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _error = null;
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _hasError = true;
          _error = errorDetails.exception;
        });
      });
      return Container();
    };
    return widget.child;
  }
}
class HybridStartupSplash extends StatefulWidget {
  final Object? error;
  final VoidCallback? onRetry;
  final bool isFinishing;
  const HybridStartupSplash({
    super.key,
    this.error,
    this.onRetry,
    this.isFinishing = false,
  });
  @override
  State<HybridStartupSplash> createState() => _HybridStartupSplashState();
}
class _HybridStartupSplashState extends State<HybridStartupSplash>
    with SingleTickerProviderStateMixin {
  static const _logoAsset = 'assets/icons/app_icon.png';
  bool _contentVisible = false;
  bool _animationReady = false;
  bool _retryEnabled = false;
  bool _reduceMotion = false;
  bool _assetsCached = false;
  late final AnimationController _breathController;
  late final Animation<double> _breathScale;
  Timer? _animationGateTimer;
  Timer? _retryEnableTimer;
  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _breathScale = Tween<double>(begin: 0.92, end: 1.04).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );
    _animationGateTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _animationReady = true;
      });
      _restartAnimationIfNeeded();
    });
    if (widget.error != null) {
      _scheduleRetryEnable();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _contentVisible = true;
      });
    });
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_assetsCached) {
      unawaited(precacheImage(const AssetImage(_logoAsset), context));
      _assetsCached = true;
    }
    _updateReduceMotion();
    _restartAnimationIfNeeded();
  }
  @override
  void didUpdateWidget(HybridStartupSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.error != oldWidget.error && widget.error != null) {
      _scheduleRetryEnable();
    }
    if (widget.error == null && oldWidget.error != null) {
      _retryEnableTimer?.cancel();
      _retryEnabled = false;
    }
  }
  @override
  void dispose() {
    _breathController.dispose();
    _animationGateTimer?.cancel();
    _retryEnableTimer?.cancel();
    super.dispose();
  }
  void _updateReduceMotion() {
    final mediaQuery = MediaQuery.maybeOf(context);
    _reduceMotion = mediaQuery?.disableAnimations ?? false;
  }
  void _restartAnimationIfNeeded() {
    if (!mounted) return;
    if (_animationReady && !_reduceMotion) {
      if (!_breathController.isAnimating) {
        _breathController.repeat(reverse: true);
      }
    } else {
      _breathController.stop();
    }
  }
  void _scheduleRetryEnable() {
    _retryEnabled = false;
    _retryEnableTimer?.cancel();
    _retryEnableTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _retryEnabled = true;
      });
    });
  }
  void _handleRetryPressed() {
    if (!_retryEnabled || widget.onRetry == null) {
      return;
    }
    logger.info('Startup retry button tapped');
    widget.onRetry!.call();
    _scheduleRetryEnable();
  }
  Color _softenAccent(Color color, bool isDark) {
    return Color.lerp(color, isDark ? Colors.white : Colors.black, isDark ? 0.3 : 0.2) ?? color;
  }
  Color _withAlpha(Color color, double alpha) => color.withValues(alpha: alpha);
  @override
  Widget build(BuildContext context) {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final themeMode = brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', '')],
      home: Builder(
        builder: (context) => _buildContent(context),
      ),
    );
  }
  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bool hasError = widget.error != null;
    final String primaryText = hasError
        ? 'We hit a bump connecting to Maya.'
        : (widget.isFinishing ? 'Almost ready…' : 'Preparing Maya for you…');
    final String secondaryText = hasError
        ? 'Couldn\'t reach our servers. Please check your connection.'
        : 'A moment of calm while we get ready.';
    final String semanticsLabel = hasError
        ? 'Startup error. Please try again.'
        : 'Preparing Maya for you';
    final Color accent = _softenAccent(colorScheme.primary, isDark);
    final Color gradientStart = Color.alphaBlend(
      _withAlpha(accent, isDark ? 0.16 : 0.12),
      colorScheme.surface,
    );
    final Color gradientEnd = colorScheme.surface;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Semantics(
        label: semanticsLabel,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [gradientStart, gradientEnd],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    opacity: _contentVisible ? 1 : 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLogo(theme, accent, isDark),
                        const SizedBox(height: 32),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeOut,
                          child: Column(
                            key: ValueKey<String>(primaryText + secondaryText),
                            children: [
                              Text(
                                primaryText,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                secondaryText,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        _buildLoader(accent, isDark),
                        if (widget.error != null && widget.onRetry != null) ...[
                          const SizedBox(height: 32),
                          _buildRetryButton(theme),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildLogo(ThemeData theme, Color accent, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.35 : 0.75,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _withAlpha(accent, isDark ? 0.35 : 0.18),
            blurRadius: 38,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          _logoAsset,
          width: 128,
          height: 128,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
  Widget _buildLoader(Color accent, bool isDark) {
    final base = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _withAlpha(accent, isDark ? 0.18 : 0.12),
        border: Border.all(color: _withAlpha(accent, 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _withAlpha(accent, isDark ? 0.3 : 0.18),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
    final bool canAnimate = _animationReady && !_reduceMotion;
    if (!canAnimate) {
      return base;
    }
    return AnimatedBuilder(
      animation: _breathController,
      builder: (context, child) {
        return Transform.scale(
          scale: _breathScale.value,
          child: child,
        );
      },
      child: base,
    );
  }
  Widget _buildRetryButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _retryEnabled ? _handleRetryPressed : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
    );
  }
}
Future<void> _initializeFirebaseServices() async {
  try {
    logger.debug(
        'Initializing FirebaseService with existing Firebase instance...');
    final firebaseService = serviceLocator<FirebaseService>();
    logger.info(
        '[Main] IMPORTANT: App Check is DISABLED in this build to avoid authentication issues');
    await firebaseService.init();
    logger.info('[Main] FirebaseService initialized successfully');
  } catch (e) {
    logger.error('[Main] Error initializing FirebaseService', error: e);
  }
}
Future<void> _initializeConfigAndApi() async {
  try {
    logger.debug('[Main] Initializing ConfigService...');
    _configService = ConfigService();
    await _configService!.init();
    logger.debug('ConfigService initialized successfully');
    logger.debug('[Main] Creating ApiClient with ConfigService');
    _apiClient = ApiClient(configService: _configService!);
    await registerApiDependentServices(_configService!, _apiClient!);
    logger.debug('[Main] Database health check deferred to background initialization');
    logger.debug(
        '[Main] Initializing refactored service components sequentially...');
    try {
      logger.debug('[Main] Initializing VoiceService...');
      final voiceService = serviceLocator<
          VoiceService>(); // Keep legacy VoiceService for initialization
      await voiceService.initialize();
      logger.debug('[Main] VoiceService initialized ✓');
    } catch (e) {
      logger.error('[Main] Error initializing VoiceService', error: e);
    }
    logger.debug('[Main] Database-dependent services will initialize lazily on first use');
    if (serviceLocator.isRegistered<TherapyService>()) {
      final therapyService = serviceLocator<TherapyService>();
      await therapyService.init();
      logger.debug('[Main] TherapyService initialized successfully');
    }
    try {
      logger.debug('[Main] Initializing UserProfileService...');
      final userProfileService = serviceLocator<UserProfileService>();
      await userProfileService.init();
      logger.debug('[Main] UserProfileService initialized ✓');
    } catch (e) {
      logger.error('[Main] Error initializing UserProfileService', error: e);
    }
    final allDepsValid = validateDependencies();
    logger.info(
        '[Main] All required dependencies validated successfully ${allDepsValid ? '✅' : '❌'}');
  } catch (e) {
    logger.error('[Main] Error initializing config and API',
        error: e, stackTrace: StackTrace.current);
  }
}
Future<void> initializeHeavyServices() async {
  logger.info('[Main] Initializing heavy services in background...');
  try {
    await DependencyContainer.whenReady();
    try {
      final appDatabase = DependencyContainer().appDatabaseConcrete;
      if (serviceLocator.isRegistered<DatabaseOperationManager>()) {
        logger.debug('[Main] Checking database health...');
        final dbManager =
            DependencyContainer().databaseOperationManagerConcrete;
        final isHealthy =
            await dbManager.checkAndRepairDatabaseHealth(appDatabase);
        if (isHealthy) {
          logger.info('[Main] Database health check passed ✅');
        } else {
          logger
              .warning('[Main] Database health check failed, attempted repair');
        }
      }
      logger.debug('[Main] Verifying database tables...');
      final databaseProvider = serviceLocator<DatabaseProvider>();
      final requiredTables = [
        'sessions',
        'messages',
        'conversation_memories',
        'therapy_insights',
        'emotional_states'
      ];
      final missingTables = <String>[];
      for (final table in requiredTables) {
        final exists = await databaseProvider.tableExists(table);
        if (!exists) {
          missingTables.add(table);
          logger.warning('[Main] Table $table not found in database');
        }
      }
      if (missingTables.isEmpty) {
        logger.info(
            '[Main] All required database tables verified successfully ✅');
      } else {
        logger.warning('[Main] Missing tables: ${missingTables.join(', ')}');
        logger.warning(
            '[Main] Will attempt to create missing tables during service initialization');
      }
      if (serviceLocator.isRegistered<DatabaseOperationManager>()) {
        Future.delayed(const Duration(seconds: 3), () {
          final dbManager =
              DependencyContainer().databaseOperationManagerConcrete;
          dbManager.optimizeDatabase(appDatabase).then((_) {
            logger.debug('[Main] Database optimization completed');
          });
        });
      }
    } catch (e) {
      logger.error('[Main] ERROR in deferred database checks', error: e);
    }
    try {
      await _initializeFirebaseServices();
    } catch (e) {
      logger.error('[Main] ERROR initializing Firebase services', error: e);
    }
    try {
      await _requestNotificationPermissions();
    } catch (e) {
      logger.error('[Main] ERROR requesting notification permissions',
          error: e);
    }
    logger.info('[Main] Heavy services initialized in background.');
  } catch (e) {
    logger.error('[Main] ERROR in initializeHeavyServices', error: e);
  }
}
