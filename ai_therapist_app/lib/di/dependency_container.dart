// lib/di/dependency_container.dart
import 'dart:async';
import 'package:get_it/get_it.dart';
import 'interfaces/interfaces.dart';
import 'interfaces/i_audio_settings.dart';
import '../data/datasources/remote/api_client.dart';
import '../services/audio_generator.dart';
import '../services/facades/chat_voice_facade.dart';
import '../services/facades/voice_mode_facade.dart';
import '../services/facades/session_voice_facade.dart';
import '../services/vad_manager.dart';
import '../data/datasources/local/app_database.dart';
import '../utils/database_helper.dart';
import '../services/memory_manager.dart';
import '../services/config_service.dart';
import '../services/recording_manager.dart';
import '../services/user_context_service.dart';
class DependencyContainer {
  static final DependencyContainer _instance = DependencyContainer._internal();
  factory DependencyContainer() => _instance;
  DependencyContainer._internal();
  final GetIt _locator = GetIt.instance;
  bool _isInitialized = false;
  static Completer<void>? _readyCompleter;
  Future<void> initialize({bool testing = false}) async {
    if (_isInitialized) {
      return;
    }
    try {
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }
  T get<T extends Object>() {
    if (!_isInitialized) {
      if (_locator.isRegistered<T>()) {
        return _locator.get<T>();
      }
      throw StateError(
          'DependencyContainer not initialized. Call initialize() first.');
    }
    return _locator.get<T>();
  }
  bool isRegistered<T extends Object>() {
    return _locator.isRegistered<T>();
  }
  Future<void> reset() async {
    await _locator.reset();
    _isInitialized = false;
  }
  void dispose() {
  }
  static void markReady() {
    final completer = _readyCompleter ??= Completer<void>();
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
  static void markFailed(Object error, [StackTrace? stackTrace]) {
    final completer = _readyCompleter ??= Completer<void>();
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
  static void resetReady() {
    if (_readyCompleter == null || _readyCompleter!.isCompleted) {
      _readyCompleter = Completer<void>();
    }
  }
  static Future<void> whenReady() {
    _readyCompleter ??= Completer<void>();
    return _readyCompleter!.future;
  }
  IConfigService get config => get<IConfigService>();
  ConfigService get configService => get<
      ConfigService>(); // Concrete implementation for backward compatibility
  IApiClient get apiClient => get<IApiClient>();
  ApiClient get apiClientConcrete =>
      get<ApiClient>(); // Concrete implementation for backward compatibility
  IDatabase get database => get<IDatabase>();
  IAppDatabase get appDatabase => get<IAppDatabase>();
  AppDatabase get appDatabaseConcrete =>
      get<AppDatabase>(); // Concrete implementation for backward compatibility
  IDatabaseOperationManager get databaseOperationManager =>
      get<IDatabaseOperationManager>();
  DatabaseOperationManager get databaseOperationManagerConcrete =>
      get<DatabaseOperationManager>(); // Concrete implementation
  IMemoryManager get memoryManager => get<IMemoryManager>();
  MemoryManager get memoryManagerConcrete => get<
      MemoryManager>(); // Concrete implementation for backward compatibility
  IThemeService get theme => get<IThemeService>();
  IPreferencesService get preferences => get<IPreferencesService>();
  INavigationService get navigation => get<INavigationService>();
  IProgressService get progress => get<IProgressService>();
  IUserProfileService get userProfile => get<IUserProfileService>();
  IGroqService get groq => get<IGroqService>();
  ISessionRepository get sessionRepository => get<ISessionRepository>();
  IMessageRepository get messageRepository => get<IMessageRepository>();
  IUserRepository get userRepository => get<IUserRepository>();
  IAuthRepository get authRepository => get<IAuthRepository>();
  IAuthService get authService => get<IAuthService>();
  IAuthEventHandler get authEventHandler => get<IAuthEventHandler>();
  IOnboardingService get onboarding => get<IOnboardingService>();
  ITherapyService get therapy => get<ITherapyService>();
  ISessionScheduleService get sessionSchedule => get<ISessionScheduleService>();
  UserContextService get userContextService => get<UserContextService>();
  IVoiceService get voiceService => get<IVoiceService>();
  AudioGenerator get audioGenerator => get<AudioGenerator>();
  ITTSService get ttsService => get<ITTSService>();
  VADManager get vadManager => get<VADManager>();
  RecordingManager get recordingManager => get<RecordingManager>();
  IAudioSettings get audioSettings => get<IAudioSettings>();
  VoiceModeFacade get voiceModeFacade => get<VoiceModeFacade>();
  ChatVoiceFacade get chatVoiceFacade => get<ChatVoiceFacade>();
  SessionVoiceFacade get sessionVoiceFacade => get<VoiceModeFacade>();
  bool get hasLegacyServices => _isInitialized;
}
extension DependencyContainerExtension on Object {
  DependencyContainer get dependencies => DependencyContainer();
}
