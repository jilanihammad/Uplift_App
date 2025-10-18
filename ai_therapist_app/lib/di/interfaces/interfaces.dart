// lib/di/interfaces/interfaces.dart

library interfaces;

/// Central export file for all dependency injection interfaces
/// This provides a single import point for all service contracts

// Core service interfaces
export 'i_auth_service.dart';
export 'i_voice_service.dart';
export 'i_therapy_service.dart';
export 'i_api_client.dart';
export 'i_config_service.dart';

// Audio service interfaces (VoiceService refactoring)
export 'i_audio_recording_service.dart';
export 'i_tts_service.dart';
export 'i_websocket_audio_manager.dart';
export 'i_audio_file_manager.dart';

// Data interfaces
export 'i_database.dart';
export 'i_app_database.dart';
export 'i_database_operation_manager.dart';
export 'i_memory_manager.dart';
export 'i_session_repository.dart';

// Repository interfaces
export 'i_auth_repository.dart';
export 'i_user_repository.dart';
export 'i_message_repository.dart';

// UI and flow interfaces
export 'i_onboarding_service.dart';
export 'i_theme_service.dart';
export 'i_preferences_service.dart';
export 'i_navigation_service.dart';
export 'i_progress_service.dart';
export 'i_user_profile_service.dart';
export 'i_groq_service.dart';
export 'i_session_schedule_service.dart';

// Event handling interfaces
export 'i_auth_event_handler.dart';

// Additional service interfaces (to be created as needed)
// export 'i_notification_service.dart';
