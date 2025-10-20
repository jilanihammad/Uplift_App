import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Handles runtime configuration overlays sourced from Firebase Remote Config.
/// Provides a kill switch for TTS streaming and related tuning knobs with
/// deterministic fallbacks (remote config → dart define → .env → defaults).
class RemoteConfigService {
  RemoteConfigService._internal();
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;

  static const String _ttsStreamingKey = 'tts_streaming_enabled';
  static const String _ttsBufferKey = 'tts_streaming_buffer_size';
  static const String _ttsMaxMemoryKey = 'tts_max_memory_duration_seconds';

  static const String _cacheTtsKey =
      'remote_config_cache_tts_streaming_enabled';
  static const String _cacheBufferKey =
      'remote_config_cache_tts_streaming_buffer_size';
  static const String _cacheMaxMemoryKey =
      'remote_config_cache_tts_max_memory_duration_seconds';

  FirebaseRemoteConfig get _remoteConfig => FirebaseRemoteConfig.instance;

  /// Apply cached overrides without touching Firebase Remote Config (usable
  /// before Firebase initialization completes).
  Future<void> preloadCachedOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await _applyCachedOverrides(prefs);
  }

  /// Load cached overrides first (ensures offline kill switch), then fetch the
  /// latest values from Remote Config.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 5),
      minimumFetchInterval:
          kDebugMode ? const Duration(minutes: 1) : const Duration(hours: 1),
    ));

    await _remoteConfig.setDefaults({
      _ttsStreamingKey: AppConfig().ttsStreamingEnabled,
      _ttsBufferKey: AppConfig().ttsStreamingBufferSize,
      _ttsMaxMemoryKey: AppConfig().ttsMaxMemoryDurationSeconds,
    });

    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint('[RemoteConfigService] Failed to fetch remote config: $e');
    }

    await _cacheAndApplyOverrides(prefs,
        ttsStreamingEnabled: _remoteConfig.getBool(_ttsStreamingKey),
        bufferSize: _remoteConfig.getInt(_ttsBufferKey),
        maxMemorySeconds: _remoteConfig.getInt(_ttsMaxMemoryKey));
  }

  /// Force-refresh remote config (useful for manual toggles or diagnostics).
  Future<void> refresh() async {
    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint('[RemoteConfigService] Refresh failed: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await _cacheAndApplyOverrides(prefs,
        ttsStreamingEnabled: _remoteConfig.getBool(_ttsStreamingKey),
        bufferSize: _remoteConfig.getInt(_ttsBufferKey),
        maxMemorySeconds: _remoteConfig.getInt(_ttsMaxMemoryKey));
  }

  /// Directly apply an override (used for integration tests and manual
  /// diagnostics without waiting for remote fetch).
  Future<void> forceOverride({
    bool? ttsStreamingEnabled,
    int? bufferSize,
    int? maxMemorySeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _cacheAndApplyOverrides(prefs,
        ttsStreamingEnabled: ttsStreamingEnabled,
        bufferSize: bufferSize,
        maxMemorySeconds: maxMemorySeconds);
  }

  Future<void> _applyCachedOverrides(SharedPreferences prefs) async {
    final bool? cachedTts =
        prefs.containsKey(_cacheTtsKey) ? prefs.getBool(_cacheTtsKey) : null;
    final int? cachedBuffer = prefs.containsKey(_cacheBufferKey)
        ? prefs.getInt(_cacheBufferKey)
        : null;
    final int? cachedMaxMemory = prefs.containsKey(_cacheMaxMemoryKey)
        ? prefs.getInt(_cacheMaxMemoryKey)
        : null;

    if (cachedTts != null || cachedBuffer != null || cachedMaxMemory != null) {
      AppConfig().applyRuntimeOverrides(
        ttsStreamingEnabled: cachedTts,
        ttsStreamingBufferSize: cachedBuffer,
        ttsMaxMemoryDurationSeconds: cachedMaxMemory,
      );
    }
  }

  Future<void> _cacheAndApplyOverrides(
    SharedPreferences prefs, {
    bool? ttsStreamingEnabled,
    int? bufferSize,
    int? maxMemorySeconds,
  }) async {
    if (ttsStreamingEnabled != null) {
      await prefs.setBool(_cacheTtsKey, ttsStreamingEnabled);
    }

    if (bufferSize != null && bufferSize > 0) {
      await prefs.setInt(_cacheBufferKey, bufferSize);
    }

    if (maxMemorySeconds != null && maxMemorySeconds > 0) {
      await prefs.setInt(_cacheMaxMemoryKey, maxMemorySeconds);
    }

    AppConfig().applyRuntimeOverrides(
      ttsStreamingEnabled: ttsStreamingEnabled,
      ttsStreamingBufferSize:
          (bufferSize != null && bufferSize > 0) ? bufferSize : null,
      ttsMaxMemoryDurationSeconds:
          (maxMemorySeconds != null && maxMemorySeconds > 0)
              ? maxMemorySeconds
              : null,
    );
  }
}
