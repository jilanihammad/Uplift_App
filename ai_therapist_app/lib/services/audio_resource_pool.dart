// lib/services/audio_resource_pool.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Singleton pool for managing reusable AudioPlayer instances
/// Reduces codec creation/destruction overhead that impacts TTS performance
class AudioResourcePool {
  static final AudioResourcePool _instance = AudioResourcePool._internal();
  static AudioResourcePool get instance => _instance;

  final List<AudioPlayer> _availablePlayers = [];
  final List<AudioPlayer> _usedPlayers = [];
  final Set<String> _playerUsers =
      <String>{}; // Track which service is using which player
  final int _maxPoolSize =
      3; // Limit concurrent players to avoid resource contention
  bool _isInitialized = false;

  AudioResourcePool._internal();

  /// Initialize the audio pool - should be called during app startup
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (kDebugMode) {
      print('🎵 AudioResourcePool: Initializing audio player pool...');
    }

    // Pre-create one AudioPlayer to avoid cold start delay
    try {
      final player = AudioPlayer();
      _availablePlayers.add(player);
      _isInitialized = true;

      if (kDebugMode) {
        print(
            '🎵 AudioResourcePool: Successfully initialized with ${_availablePlayers.length} players');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎵 AudioResourcePool: Error during initialization: $e');
      }
      _isInitialized =
          true; // Still mark as initialized to avoid infinite retry
    }
  }

  /// Borrow an AudioPlayer from the pool
  /// Returns a reusable player instance to avoid codec creation overhead
  Future<AudioPlayer> borrowPlayer(String userId) async {
    if (!_isInitialized) {
      await initialize();
    }

    AudioPlayer player;

    // Reuse available player if possible
    if (_availablePlayers.isNotEmpty) {
      player = _availablePlayers.removeLast();
      if (kDebugMode) {
        print('🎵 AudioResourcePool: Reusing existing player for $userId');
      }
    } else if (_usedPlayers.length < _maxPoolSize) {
      // Create new player if under limit
      player = AudioPlayer();
      if (kDebugMode) {
        print(
            '🎵 AudioResourcePool: Creating new player for $userId (${_usedPlayers.length + 1}/$_maxPoolSize)');
      }
    } else {
      // Pool is full, force create a new temporary player
      // This should be rare if pool size is tuned correctly
      player = AudioPlayer();
      if (kDebugMode) {
        print(
            '🎵 AudioResourcePool: WARNING - Creating temporary player for $userId (pool full)');
      }
    }

    _usedPlayers.add(player);
    _playerUsers.add('$userId-${player.hashCode}');

    return player;
  }

  /// Return an AudioPlayer to the pool for reuse
  /// Resets player state and makes it available for other services
  Future<void> returnPlayer(AudioPlayer player, String userId) async {
    final playerKey = '$userId-${player.hashCode}';

    if (!_playerUsers.contains(playerKey)) {
      if (kDebugMode) {
        print(
            '🎵 AudioResourcePool: WARNING - Returning untracked player from $userId');
      }
    }

    _playerUsers.remove(playerKey);
    _usedPlayers.remove(player);

    try {
      // Reset player state for reuse
      await player.stop();
      await player.seek(Duration.zero);

      // Return to available pool if under limit
      if (_availablePlayers.length < _maxPoolSize) {
        _availablePlayers.add(player);
        if (kDebugMode) {
          print(
              '🎵 AudioResourcePool: Returned player from $userId to pool (${_availablePlayers.length} available)');
        }
      } else {
        // Pool full, dispose the player
        await player.dispose();
        if (kDebugMode) {
          print('🎵 AudioResourcePool: Disposed excess player from $userId');
        }
      }
    } catch (e) {
      // If reset fails, dispose the player to avoid corrupted state
      if (kDebugMode) {
        print(
            '🎵 AudioResourcePool: Error resetting player from $userId, disposing: $e');
      }
      try {
        await player.dispose();
      } catch (disposeError) {
        if (kDebugMode) {
          print(
              '🎵 AudioResourcePool: Error disposing problematic player: $disposeError');
        }
      }
    }
  }

  /// Check if a player is currently playing across all pool instances
  /// More efficient than creating temporary players for status checks
  bool get hasActivePlayback {
    for (final player in _usedPlayers) {
      if (player.playing) {
        return true;
      }
    }
    return false;
  }

  /// Get pool statistics for debugging
  Map<String, int> get stats => {
        'available': _availablePlayers.length,
        'used': _usedPlayers.length,
        'total': _availablePlayers.length + _usedPlayers.length,
        'users': _playerUsers.length,
      };

  /// Dispose all players and clean up the pool
  Future<void> dispose() async {
    if (kDebugMode) {
      print('🎵 AudioResourcePool: Disposing all players...');
    }

    final allPlayers = [..._availablePlayers, ..._usedPlayers];
    _availablePlayers.clear();
    _usedPlayers.clear();
    _playerUsers.clear();

    for (final player in allPlayers) {
      try {
        await player.dispose();
      } catch (e) {
        if (kDebugMode) {
          print('🎵 AudioResourcePool: Error disposing player: $e');
        }
      }
    }

    _isInitialized = false;

    if (kDebugMode) {
      print('🎵 AudioResourcePool: Disposed ${allPlayers.length} players');
    }
  }
}
