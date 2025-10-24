// lib/services/memory_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation_memory.dart';
import '../di/service_locator.dart';
import '../di/dependency_container.dart';
import '../data/datasources/local/database_provider.dart';
import '../di/initialization_tracker.dart';
import '../utils/logging_service.dart';
import '../utils/database_helper.dart';
import '../utils/feature_flags.dart';
import '../data/datasources/remote/api_client.dart';
import '../di/interfaces/i_user_profile_service.dart';
import '../models/user_profile.dart';

/// Service for managing memory in therapy conversations.
/// Implements LangChain-like memory capabilities for maintaining context across conversations.
class MemoryService {
  // Singleton instance
  static MemoryService? _instance;

  // Initialization flag
  bool _isInitialized = false;

  // In-memory cache of conversation memories
  final List<ConversationMemory> _conversationMemories = [];

  // In-memory cache of insights
  final List<TherapyInsight> _insights = [];

  // In-memory cache of emotional states
  final List<EmotionalState> _emotionalStates = [];

  // Key personal anchors remembered about the user
  final List<UserAnchor> _anchors = [];

  // Persistent session counter for anchor decay tracking
  int _sessionCounter = 0;
  SharedPreferences? _preferences;

  // Remote sync dependencies and helpers
  final ApiClient _apiClient;
  final IUserProfileService _userProfileService;
  final Uuid _uuid = const Uuid();

  // Remote sync state tracking
  static const String _profileVersionKey = 'memory_profile_remote_version';
  static const String _lastAnchorSyncKey = 'memory_anchor_last_sync';
  static const String _pendingAnchorOpsKey = 'memory_anchor_pending_ops';
  static const String _pendingProfileKey = 'memory_profile_pending_update';
  int _remoteProfileVersion = 0;
  DateTime? _lastAnchorSync;
  bool _isApplyingRemoteProfile = false;
  bool _isApplyingRemoteAnchors = false;
  bool _isFlushingAnchorQueue = false;
  bool _isFlushingProfileQueue = false;
  final List<Map<String, dynamic>> _pendingAnchorOps = [];
  Map<String, dynamic>? _pendingProfileUpdate;

  // User preferences
  final Map<String, dynamic> _userPreferences = {};

  // Maximum context length for LLM
  static const int _maxContextLength = 4000;

  // Database provider for persistence
  final DatabaseProvider _databaseProvider;

  // Singleton factory constructor
  factory MemoryService({
    required DatabaseProvider databaseProvider,
    ApiClient? apiClient,
    IUserProfileService? userProfileService,
  }) {
    _instance ??= MemoryService._internal(
      databaseProvider,
      apiClient ?? DependencyContainer().apiClientConcrete,
      userProfileService ?? DependencyContainer().userProfile,
    );
    return _instance!;
  }

  // Private constructor
  MemoryService._internal(
    this._databaseProvider,
    this._apiClient,
    this._userProfileService,
  );

  // Getter for initialization status
  bool get isInitialized => _isInitialized;

  // Initialize the service on-demand
  Future<void> initializeIfNeeded() async {
    if (!_isInitialized) {
      await init();
    }
  }

  // Initialize the MemoryService
  Future<void> init() async {
    if (_isInitialized) {
      if (kDebugMode) {
        logger.debug('MemoryService already initialized, skipping init()');
      }
      return;
    }

    try {
      // Register with initialization tracker
      await initTracker.initializeWithRetry('MemoryService', () async {
        // First ensure database provider is initialized
        await _databaseProvider.init();

        // Verify required tables exist, create them if they don't
        await _ensureTablesExist();

        // Load conversation memories from database
        await _loadConversationMemories();

        // Load insights from database
        await _loadInsights();

        // Load emotional states from database
        await _loadEmotionalStates();

        // Load user anchors and session counter for personalized memory
        await _loadAnchors();
        await _loadSessionCounter();
        await _loadSyncMetadata();
        _subscribeToProfileChanges();

        _isInitialized = true;
        logger.info('MemoryService initialized successfully');
        logger.debug(
            'Loaded ${_conversationMemories.length} memories, ${_insights.length} insights, ${_emotionalStates.length} emotional states, and ${_anchors.length} anchors');

        if (_isSyncEnabled) {
          unawaited(_performInitialSync());
        }
      });
    } catch (e) {
      logger.error('Failed to initialize MemoryService', error: e);
      _isInitialized = false;
      throw Exception('MemoryService initialization failed: $e');
    }
  }

  /// Ensure all required tables exist in the database
  Future<void> _ensureTablesExist() async {
    try {
      // Get DatabaseOperationManager to prevent database locks
      final dbOpManager =
          DependencyContainer().databaseOperationManagerConcrete;

      // Check if required tables exist - this should be read-only
      final convMemoriesExists = await dbOpManager.queueOperation<bool>(
        () => _databaseProvider.tableExists('conversation_memories'),
        name: 'check-conversation-memories-exists',
        isReadOnly: true,
      );

      final therapyInsightsExists = await dbOpManager.queueOperation<bool>(
        () => _databaseProvider.tableExists('therapy_insights'),
        name: 'check-therapy-insights-exists',
        isReadOnly: true,
      );

      final emotionalStatesExists = await dbOpManager.queueOperation<bool>(
        () => _databaseProvider.tableExists('emotional_states'),
        name: 'check-emotional-states-exists',
        isReadOnly: true,
      );

      logger.debug(
          'Table check: conversation_memories=[32m$convMemoriesExists[0m, therapy_insights=[32m$therapyInsightsExists[0m, emotional_states=[32m$emotionalStatesExists[0m');

      // If any table is missing, log and throw
      if (!convMemoriesExists ||
          !therapyInsightsExists ||
          !emotionalStatesExists) {
        final missing = [
          if (!convMemoriesExists) 'conversation_memories',
          if (!therapyInsightsExists) 'therapy_insights',
          if (!emotionalStatesExists) 'emotional_states',
        ];
        logger.error(
            'Missing required database tables: [31m${missing.join(', ')}[0m');
        throw Exception(
            'Missing required database tables: ${missing.join(', ')}');
      }
    } catch (e) {
      logger.error('Error checking required tables', error: e);
      throw Exception('Failed to verify required database tables: $e');
    }
  }

  /// Load conversation memories from database with better error handling
  Future<void> _loadConversationMemories() async {
    try {
      final memoryRecords = await _databaseProvider.query(
        'conversation_memories',
        orderBy: 'timestamp DESC',
      );

      _conversationMemories.clear();
      for (final record in memoryRecords) {
        try {
          final memory = ConversationMemory.fromJson(record);
          _conversationMemories.add(memory);
        } catch (e) {
          logger.warning('Error parsing conversation memory: $e');
        }
      }
      logger.debug(
          'Loaded ${_conversationMemories.length} conversation memories');
    } catch (e) {
      // Fall back to old table name if needed
      try {
        logger.warning(
            'Failed to load from conversation_memories, trying conversations table');
        final memoryRecords = await _databaseProvider.query(
          'conversations',
          orderBy: 'timestamp DESC',
        );

        _conversationMemories.clear();
        for (final record in memoryRecords) {
          try {
            final memory = ConversationMemory.fromJson(record);
            _conversationMemories.add(memory);
          } catch (e) {
            logger.warning('Error parsing conversation from old table: $e');
          }
        }
        logger.debug(
            'Loaded ${_conversationMemories.length} conversations from legacy table');
      } catch (fallbackError) {
        logger.error('Failed to load conversation memories from either table',
            error: fallbackError);
        // Continue with empty memories rather than crashing
      }
    }
  }

  /// Load insights from database with better error handling
  Future<void> _loadInsights() async {
    try {
      final insightRecords = await _databaseProvider.query('therapy_insights');
      _insights.clear();
      for (final record in insightRecords) {
        try {
          final insight = TherapyInsight.fromJson(record);
          _insights.add(insight);
        } catch (e) {
          logger.warning('Error parsing therapy insight: $e');
        }
      }
      logger.debug('Loaded ${_insights.length} therapy insights');
    } catch (e) {
      // Fall back to old table name if needed
      try {
        logger.warning(
            'Failed to load from therapy_insights, trying insights table');
        final insightRecords = await _databaseProvider.query('insights');
        _insights.clear();
        for (final record in insightRecords) {
          try {
            final insight = TherapyInsight.fromJson(record);
            _insights.add(insight);
          } catch (e) {
            logger.warning('Error parsing insight from old table: $e');
          }
        }
        logger.debug('Loaded ${_insights.length} insights from legacy table');
      } catch (fallbackError) {
        logger.error('Failed to load insights from either table',
            error: fallbackError);
        // Continue with empty insights rather than crashing
      }
    }
  }

  /// Load emotional states from database with better error handling
  Future<void> _loadEmotionalStates() async {
    try {
      final stateRecords = await _databaseProvider.query('emotional_states');
      _emotionalStates.clear();
      for (final record in stateRecords) {
        try {
          final state = EmotionalState.fromJson(record);
          _emotionalStates.add(state);
        } catch (e) {
          logger.warning('Error parsing emotional state: $e');
        }
      }
      logger.debug('Loaded ${_emotionalStates.length} emotional states');
    } catch (e) {
      logger.error('Failed to load emotional states', error: e);
      // Continue with empty emotional states rather than crashing
    }
  }

  /// Load persisted user anchors into memory
  Future<void> _loadAnchors() async {
    try {
      final anchorRecords = await _databaseProvider.query(
        'user_anchors',
        orderBy: 'last_seen_at DESC',
      );

      _anchors
        ..clear()
        ..addAll(anchorRecords
            .map(UserAnchor.fromJson)
            .where((anchor) => !anchor.isDeleted));

      logger.debug('Loaded ${_anchors.length} user anchors');
    } catch (e) {
      logger.error('Failed to load user anchors', error: e);
      _anchors.clear();
    }
  }

  /// Load persisted session counter for anchor decay tracking
  Future<void> _loadSessionCounter() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      _sessionCounter = _preferences?.getInt('memory_session_counter') ?? 0;
      logger.debug('Loaded memory session counter: $_sessionCounter');
    } catch (e) {
      logger.warning('Failed to load session counter from preferences: $e');
      _sessionCounter = 0;
    }
  }

  Future<void> _loadSyncMetadata() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      _remoteProfileVersion =
          _preferences?.getInt(_profileVersionKey) ?? _remoteProfileVersion;

      final lastSyncString = _preferences?.getString(_lastAnchorSyncKey);
      if (lastSyncString != null && lastSyncString.isNotEmpty) {
        _lastAnchorSync = DateTime.tryParse(lastSyncString);
      }
      logger.debug(
          'Loaded sync metadata: profileVersion=$_remoteProfileVersion, lastAnchorSync=$_lastAnchorSync');
    } catch (e) {
      logger.warning('Failed to load sync metadata: $e');
      _remoteProfileVersion = 0;
      _lastAnchorSync = null;
    }
  }

  void _subscribeToProfileChanges() {
    _userProfileService.profileChanged.addListener(() {
      if (!_isSyncEnabled || _isApplyingRemoteProfile) {
        return;
      }
      final profile = _userProfileService.profile;
      if (profile == null) {
        return;
      }
      unawaited(_syncProfileToServer(profile));
    });
  }

  Future<void> _performInitialSync() async {
    try {
      await _syncProfileFromServer();
      await _syncAnchorsFromServer(initial: true);
      await _loadPendingOperations();
      await _flushPendingProfile();
      await _flushPendingAnchors();
    } catch (e) {
      logger.warning('Initial memory sync failed: $e');
    }
  }

  Future<void> _loadPendingOperations() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final anchorsJson = _preferences?.getString(_pendingAnchorOpsKey);
      if (anchorsJson != null && anchorsJson.isNotEmpty) {
        final decoded = jsonDecode(anchorsJson);
        if (decoded is List) {
          _pendingAnchorOps
            ..clear()
            ..addAll(decoded.map(
                (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>)));
        }
      }

      final profileJson = _preferences?.getString(_pendingProfileKey);
      if (profileJson != null && profileJson.isNotEmpty) {
        final decoded = jsonDecode(profileJson);
        if (decoded is Map<String, dynamic>) {
          _pendingProfileUpdate = decoded;
        }
      }
    } catch (e) {
      logger.warning('Failed to load pending sync operations: $e');
      _pendingAnchorOps.clear();
      _pendingProfileUpdate = null;
    }
  }

  Future<void> _syncProfileFromServer() async {
    if (!_isSyncEnabled) {
      return;
    }
    try {
      final response = await _apiClient.get('/profile');
      final preferredName = response['preferred_name'] as String?;
      _remoteProfileVersion =
          (response['version'] as int?) ?? _remoteProfileVersion;
      await _preferences?.setInt(_profileVersionKey, _remoteProfileVersion);

      if (preferredName != null && preferredName.trim().isNotEmpty) {
        _isApplyingRemoteProfile = true;
        try {
          final currentProfile = _userProfileService.profile;
          if (currentProfile == null) {
            await _userProfileService.updateProfile(
              name: preferredName,
              firstName: preferredName,
            );
          } else {
            await _userProfileService.updateProfile(
              name: currentProfile.name,
              firstName: preferredName,
            );
          }
        } finally {
          _isApplyingRemoteProfile = false;
        }
      }
    } catch (e) {
      logger.warning('Failed to sync profile from server: $e');
    }
  }

  Future<void> _syncProfileToServer(UserProfile profile) async {
    if (!_isSyncEnabled) {
      return;
    }

    _preferences ??= await SharedPreferences.getInstance();

    final payload = <String, dynamic>{
      'preferred_name': profile.firstName ?? profile.displayName,
      'pronouns': null,
      'locale': null,
      'version': _remoteProfileVersion,
    };

    final headers = {
      'If-Match': 'W/"v$_remoteProfileVersion"',
    };

    try {
      final response =
          await _apiClient.put('/profile', payload, headers: headers);
      final newVersion = (response['version'] as int?) ?? _remoteProfileVersion;
      _remoteProfileVersion = newVersion;
      await _preferences?.setInt(_profileVersionKey, newVersion);
      if (_pendingProfileUpdate != null) {
        _pendingProfileUpdate = null;
        await _preferences?.remove(_pendingProfileKey);
      }
      await _flushPendingProfile();
    } catch (e) {
      logger.warning('Failed to sync profile to server: $e');
      await _queueProfileUpdate(payload);
    }
  }

  Future<void> _syncAnchorsFromServer({bool initial = false}) async {
    if (!_isSyncEnabled) {
      return;
    }

    _preferences ??= await SharedPreferences.getInstance();

    final queryParams = <String, dynamic>{};
    if (!initial && _lastAnchorSync != null) {
      queryParams['since'] = _lastAnchorSync!.toIso8601String();
    }

    try {
      final response =
          await _apiClient.get('/anchors', queryParams: queryParams);
      final items = (response['items'] as List<dynamic>?) ?? const [];

      final serverTimeString = response['server_time'] as String?;
      if (serverTimeString != null) {
        final parsed = DateTime.tryParse(serverTimeString);
        if (parsed != null) {
          _lastAnchorSync = parsed;
          await _preferences?.setString(
              _lastAnchorSyncKey, parsed.toIso8601String());
        }
      }

      if (items.isEmpty) {
        return;
      }

      _isApplyingRemoteAnchors = true;
      for (final rawItem in items) {
        if (rawItem is! Map) {
          continue;
        }
        final item = Map<String, dynamic>.from(rawItem as Map);
        final clientId = item['client_anchor_id'] as String?;
        if (clientId == null || clientId.isEmpty) {
          continue;
        }

        final isDeleted = item['is_deleted'] == true;
        final updatedAt =
            DateTime.tryParse(item['updated_at'] as String? ?? '') ??
                DateTime.now();
        final anchorText = item['anchor_text'] as String? ?? '';
        final normalized = UserAnchor.normalize(anchorText);
        final anchorType = item['anchor_type'] as String?;
        final confidence = (item['confidence'] as num?)?.toDouble();
        final lastSeenIndex = item['last_seen_session_index'] as int? ?? 0;
        final serverId = item['id'] as String?;

        final existingIndex =
            _anchors.indexWhere((anchor) => anchor.clientAnchorId == clientId);

        if (isDeleted) {
          if (existingIndex != -1) {
            final existing = _anchors.removeAt(existingIndex);
            if (existing.id != null) {
              await _databaseProvider.delete(
                'user_anchors',
                where: 'id = ?',
                whereArgs: [existing.id],
              );
            }
          }
          continue;
        }

        if (existingIndex != -1) {
          final existing = _anchors[existingIndex];
          if (existing.updatedAt.isAfter(updatedAt)) {
            continue; // Local copy is newer
          }

          final merged = existing.copyWith(
            anchorText:
                anchorText.isNotEmpty ? anchorText : existing.anchorText,
            anchorType: anchorType ?? existing.anchorType,
            confidence: confidence ?? existing.confidence,
            lastSessionIndex: lastSeenIndex,
            lastSeenAt: DateTime.now(),
            serverId: serverId ?? existing.serverId,
            updatedAt: updatedAt,
            isDeleted: false,
          );

          if (existing.id != null) {
            await _databaseProvider.update(
              'user_anchors',
              merged.toJson(),
              where: 'id = ?',
              whereArgs: [existing.id],
            );
            _anchors[existingIndex] = merged;
          }
          continue;
        }

        if (anchorText.isEmpty) {
          continue;
        }

        final newAnchor = UserAnchor(
          anchorText: anchorText,
          normalizedText: normalized,
          anchorType: anchorType,
          confidence: confidence ?? 0.0,
          mentionCount: 1,
          firstSeenAt: updatedAt,
          lastSeenAt: updatedAt,
          firstSessionIndex: lastSeenIndex,
          lastSessionIndex: lastSeenIndex,
          serverId: serverId,
          clientAnchorId: clientId,
          updatedAt: updatedAt,
        );

        final insertData = Map<String, dynamic>.from(newAnchor.toJson())
          ..remove('id');
        final insertedId =
            await _databaseProvider.insert('user_anchors', insertData);
        _anchors.add(newAnchor.copyWith(id: insertedId));
      }
    } catch (e) {
      logger.warning('Failed to sync anchors from server: $e');
    } finally {
      _isApplyingRemoteAnchors = false;
      await _flushPendingAnchors();
    }
  }

  Future<void> _syncAnchorUpsert(UserAnchor anchor) async {
    if (!_isSyncEnabled) {
      return;
    }

    final payload = <String, dynamic>{
      'client_anchor_id': anchor.clientAnchorId,
      'anchor_text': anchor.anchorText,
      'anchor_type': anchor.anchorType,
      'confidence': anchor.confidence,
      'last_seen_session_index': anchor.lastSessionIndex,
      'updated_at': anchor.updatedAt.toIso8601String(),
    };

    try {
      final response = await _apiClient.post('/anchors:upsert', payload);
      final serverId = response['id'] as String?;
      final updatedAtStr = response['updated_at'] as String?;
      final changed = response['changed'] == true;

      if (serverId != null || changed) {
        final updatedAnchor = anchor.copyWith(
          serverId: serverId ?? anchor.serverId,
          updatedAt: updatedAtStr != null
              ? DateTime.tryParse(updatedAtStr) ?? anchor.updatedAt
              : anchor.updatedAt,
          isDeleted: false,
        );
        if (anchor.id != null) {
          await _databaseProvider.update(
            'user_anchors',
            updatedAnchor.toJson(),
            where: 'id = ?',
            whereArgs: [anchor.id],
          );
          final index = _anchors.indexWhere(
              (element) => element.clientAnchorId == anchor.clientAnchorId);
          if (index != -1) {
            _anchors[index] = updatedAnchor;
          }
        }
      }
      await _removeAnchorOpFromQueue(anchor.clientAnchorId, type: 'upsert');
      await _flushPendingAnchors();
    } catch (e) {
      logger.warning('Failed to upsert anchor to server: $e');
      await _queueAnchorOperation({
        'type': 'upsert',
        'payload': payload,
      });
    }
  }

  Future<void> _syncAnchorDelete(UserAnchor anchor) async {
    if (!_isSyncEnabled) {
      return;
    }

    final payload = <String, dynamic>{
      'client_anchor_id': anchor.clientAnchorId,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _apiClient.post('/anchors:delete', payload);
      await _removeAnchorOpFromQueue(anchor.clientAnchorId, type: 'delete');
      await _flushPendingAnchors();
    } catch (e) {
      logger.warning('Failed to delete anchor on server: $e');
      await _queueAnchorOperation({
        'type': 'delete',
        'payload': payload,
      });
    }
  }

  Future<void> _queueProfileUpdate(Map<String, dynamic> payload) async {
    _pendingProfileUpdate = payload;
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences?.setString(_pendingProfileKey, jsonEncode(payload));
    } catch (e) {
      logger.warning('Failed to persist pending profile update: $e');
    }
  }

  Future<void> _flushPendingProfile() async {
    if (_isFlushingProfileQueue || !_isSyncEnabled) {
      return;
    }
    if (_pendingProfileUpdate == null) {
      return;
    }

    _isFlushingProfileQueue = true;
    try {
      final payload = Map<String, dynamic>.from(_pendingProfileUpdate!);
      final headers = {
        'If-Match': 'W/"v${payload['version'] ?? _remoteProfileVersion}"',
      };
      final response =
          await _apiClient.put('/profile', payload, headers: headers);
      final newVersion = (response['version'] as int?) ?? _remoteProfileVersion;
      _remoteProfileVersion = newVersion;
      await _preferences?.setInt(_profileVersionKey, newVersion);
      _pendingProfileUpdate = null;
      await _preferences?.remove(_pendingProfileKey);
    } catch (e) {
      logger.warning('Failed to flush pending profile update: $e');
    } finally {
      _isFlushingProfileQueue = false;
    }
  }

  Future<void> _queueAnchorOperation(Map<String, dynamic> operation) async {
    final payload = operation['payload'] as Map<String, dynamic>?;
    final clientId = payload?['client_anchor_id'] as String?;
    if (clientId == null || clientId.isEmpty) {
      return;
    }

    final existingIndex = _pendingAnchorOps.indexWhere((op) {
      final opPayload = op['payload'] as Map<String, dynamic>?;
      return opPayload?['client_anchor_id'] == clientId;
    });

    if (existingIndex != -1) {
      _pendingAnchorOps[existingIndex] = operation;
    } else {
      _pendingAnchorOps.add(operation);
    }

    await _persistAnchorQueue();
  }

  Future<void> _removeAnchorOpFromQueue(String clientId,
      {required String type}) async {
    final index = _pendingAnchorOps.indexWhere((op) {
      final payload = op['payload'] as Map<String, dynamic>?;
      return payload?['client_anchor_id'] == clientId && op['type'] == type;
    });
    if (index != -1) {
      _pendingAnchorOps.removeAt(index);
      await _persistAnchorQueue();
    }
  }

  Future<void> _persistAnchorQueue() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      if (_pendingAnchorOps.isEmpty) {
        await _preferences?.remove(_pendingAnchorOpsKey);
      } else {
        await _preferences?.setString(
            _pendingAnchorOpsKey, jsonEncode(_pendingAnchorOps));
      }
    } catch (e) {
      logger.warning('Failed to persist anchor queue: $e');
    }
  }

  Future<void> _flushPendingAnchors() async {
    if (_isFlushingAnchorQueue || !_isSyncEnabled) {
      return;
    }
    if (_pendingAnchorOps.isEmpty) {
      return;
    }

    _isFlushingAnchorQueue = true;
    final opsSnapshot = List<Map<String, dynamic>>.from(_pendingAnchorOps);
    try {
      for (final op in opsSnapshot) {
        final type = op['type'] as String?;
        final payload = op['payload'] as Map<String, dynamic>?;
        if (type == null || payload == null) {
          continue;
        }
        if (type == 'upsert') {
          await _apiClient.post('/anchors:upsert', payload);
        } else if (type == 'delete') {
          await _apiClient.post('/anchors:delete', payload);
        }
        _pendingAnchorOps.remove(op);
        await _persistAnchorQueue();
      }
    } catch (e) {
      logger.warning('Failed to flush pending anchor operations: $e');
    } finally {
      _isFlushingAnchorQueue = false;
    }
  }

  /// Increment the session counter and persist it for decay tracking
  Future<int> incrementSessionCounter() async {
    await initializeIfNeeded();
    _sessionCounter += 1;

    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences?.setInt('memory_session_counter', _sessionCounter);
    } catch (e) {
      logger.warning('Failed to persist session counter: $e');
    }

    return _sessionCounter;
  }

  /// Retrieve current session index without incrementing
  int get currentSessionIndex => _sessionCounter;

  /// Return an immutable snapshot of active anchors
  List<UserAnchor> getAnchors() => List.unmodifiable(_anchors);

  bool get _isSyncEnabled => FeatureFlags.isMemoryPersistenceEnabled;

  /// Add a new anchor or update an existing one
  Future<UserAnchor> addOrUpdateAnchor({
    required String anchorText,
    String? anchorType,
    double confidence = 0.5,
    required int sessionIndex,
  }) async {
    await initializeIfNeeded();

    final normalized = UserAnchor.normalize(anchorText);
    final existingIndex = _anchors.indexWhere(
      (anchor) => anchor.normalizedText == normalized,
    );

    if (existingIndex != -1) {
      final existing = _anchors[existingIndex];
      final updated = existing.copyWith(
        anchorText: anchorText.length > existing.anchorText.length
            ? anchorText
            : existing.anchorText,
        anchorType: anchorType ?? existing.anchorType,
        confidence:
            confidence > existing.confidence ? confidence : existing.confidence,
        mentionCount: existing.mentionCount + 1,
        lastSeenAt: DateTime.now(),
        lastSessionIndex: sessionIndex,
        updatedAt: DateTime.now(),
        isDeleted: false,
      );

      await _databaseProvider.update(
        'user_anchors',
        updated.toJson(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );

      _anchors[existingIndex] = updated;

      if (_isSyncEnabled && !_isApplyingRemoteAnchors) {
        unawaited(_syncAnchorUpsert(updated));
      }
      return updated;
    }

    final now = DateTime.now();
    final clientId = _uuid.v4();
    final newAnchor = UserAnchor(
      anchorText: anchorText,
      normalizedText: normalized,
      anchorType: anchorType,
      confidence: confidence,
      mentionCount: 1,
      firstSeenAt: now,
      lastSeenAt: now,
      firstSessionIndex: sessionIndex,
      lastSessionIndex: sessionIndex,
      clientAnchorId: clientId,
      updatedAt: now,
    );

    final insertData = Map<String, dynamic>.from(newAnchor.toJson());
    insertData.remove('id');
    final insertedId =
        await _databaseProvider.insert('user_anchors', insertData);
    final persisted = newAnchor.copyWith(id: insertedId);

    _anchors.add(persisted);
    await pruneAnchors(maxAnchors: 3);

    if (_isSyncEnabled && !_isApplyingRemoteAnchors) {
      unawaited(_syncAnchorUpsert(persisted));
    }
    return persisted;
  }

  /// Ensure we only keep a limited number of anchors prioritized by relevance
  Future<void> pruneAnchors({int maxAnchors = 3}) async {
    if (_anchors.isEmpty) {
      return;
    }

    final nameAnchors =
        _anchors.where((anchor) => anchor.anchorType == 'name').toList();
    final otherAnchors =
        _anchors.where((anchor) => anchor.anchorType != 'name').toList();

    if (nameAnchors.isNotEmpty) {
      otherAnchors.sort((a, b) {
        if (b.mentionCount != a.mentionCount) {
          return b.mentionCount.compareTo(a.mentionCount);
        }
        return b.lastSeenAt.compareTo(a.lastSeenAt);
      });
    } else {
      otherAnchors.sort((a, b) {
        if (b.mentionCount != a.mentionCount) {
          return b.mentionCount.compareTo(a.mentionCount);
        }
        return b.lastSeenAt.compareTo(a.lastSeenAt);
      });
    }

    final allowedOtherCount = maxAnchors <= 0
        ? 0
        : ((maxAnchors - nameAnchors.length).clamp(0, maxAnchors)).toInt();
    final keptOthers = otherAnchors.take(allowedOtherCount).toList();
    final toKeep = [...nameAnchors, ...keptOthers];

    // If there are no limits, ensure we still respect maxAnchors for others
    if (maxAnchors > 0 && toKeep.length > maxAnchors && nameAnchors.isEmpty) {
      toKeep.sort((a, b) {
        if (b.mentionCount != a.mentionCount) {
          return b.mentionCount.compareTo(a.mentionCount);
        }
        return b.lastSeenAt.compareTo(a.lastSeenAt);
      });
      toKeep.removeRange(maxAnchors, toKeep.length);
    }

    final toRemove =
        _anchors.where((anchor) => !toKeep.contains(anchor)).toList();
    _anchors
      ..clear()
      ..addAll(toKeep);

    for (final anchor in toRemove) {
      if (anchor.id != null) {
        if (_isSyncEnabled && !_isApplyingRemoteAnchors) {
          unawaited(_syncAnchorDelete(anchor));
        }
        await _databaseProvider.delete(
          'user_anchors',
          where: 'id = ?',
          whereArgs: [anchor.id],
        );
      }
    }
  }

  /// Anchors that have not been mentioned within the threshold sessions
  List<UserAnchor> getAnchorsNeedingCheck(
    int sessionIndex, {
    int threshold = 5,
  }) {
    return _anchors.where((anchor) {
      final sessionsSinceMention = sessionIndex - anchor.lastSessionIndex;
      final alreadyPromptedRecently =
          anchor.lastPromptedSession >= anchor.lastSessionIndex &&
              (sessionIndex - anchor.lastPromptedSession) < threshold;
      return sessionsSinceMention >= threshold && !alreadyPromptedRecently;
    }).toList();
  }

  /// Update anchor to reflect that a gentle check-in prompt has been queued
  Future<void> markAnchorPrompted(UserAnchor anchor, int sessionIndex) async {
    if (anchor.id == null) {
      return;
    }

    final updated = anchor.copyWith(lastPromptedSession: sessionIndex);
    await _databaseProvider.update(
      'user_anchors',
      updated.toJson(),
      where: 'id = ?',
      whereArgs: [anchor.id],
    );

    final index = _anchors.indexWhere((a) => a.id == anchor.id);
    if (index != -1) {
      _anchors[index] = updated;
    }
  }

  /// Update anchor metadata after a mention without increasing count
  Future<void> refreshAnchor(UserAnchor anchor, int sessionIndex) async {
    if (anchor.id == null) {
      return;
    }

    final refreshed = anchor.copyWith(
      lastSeenAt: DateTime.now(),
      lastSessionIndex: sessionIndex,
    );

    await _databaseProvider.update(
      'user_anchors',
      refreshed.toJson(),
      where: 'id = ?',
      whereArgs: [anchor.id],
    );

    final index = _anchors.indexWhere((a) => a.id == anchor.id);
    if (index != -1) {
      _anchors[index] = refreshed;
    }

    if (_isSyncEnabled && !_isApplyingRemoteAnchors) {
      unawaited(_syncAnchorUpsert(refreshed));
    }
  }

  /// Adds a new conversation memory pair (user message + AI response)
  Future<void> addMemory(String userMessage, String aiResponse,
      {Map<String, dynamic>? metadata}) async {
    await initializeIfNeeded();

    final memory = ConversationMemory(
      userMessage: userMessage,
      aiResponse: aiResponse,
      metadata: metadata ?? {},
    );

    try {
      _conversationMemories.add(memory);

      // Convert to database format (snake_case field names)
      final Map<String, dynamic> dbData = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'user_message': userMessage,
        'ai_response': aiResponse,
        'metadata': jsonEncode(metadata ?? {}),
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Persist to database
      try {
        await _databaseProvider.insert('conversation_memories', dbData);
      } catch (e) {
        logger.error(
            'Failed to insert into conversation_memories, trying fallback',
            error: e);
        // Try inserting into the legacy table as fallback
        try {
          await _databaseProvider.insert('conversations', dbData);
          logger.debug('Added memory to legacy conversations table');
        } catch (fallbackError) {
          logger.error('Failed to save memory to any database table',
              error: fallbackError);
          // Already added to in-memory cache, so continue
        }
      }

      logger.debug('Added new conversation memory');
    } catch (e) {
      logger.error('Failed to add conversation memory', error: e);
      // Don't rethrow to prevent app crashes
    }
  }

  /// Adds a new insight discovered during therapy
  Future<void> addInsight(String insight, String source) async {
    await initializeIfNeeded();

    final therapyInsight = TherapyInsight(
      insight: insight,
      source: source,
    );

    try {
      // Add to in-memory cache
      _insights.add(therapyInsight);

      // Persist to database
      try {
        await _databaseProvider.insert(
            'therapy_insights', therapyInsight.toJson());
      } catch (e) {
        logger.error('Failed to insert into therapy_insights, trying fallback',
            error: e);
        // Try inserting into the legacy table as fallback
        try {
          await _databaseProvider.insert('insights', therapyInsight.toJson());
          logger.debug('Added insight to legacy insights table');
        } catch (fallbackError) {
          logger.error('Failed to save insight to any database table',
              error: fallbackError);
          // Already added to in-memory cache, so continue
        }
      }

      logger.debug('Added new therapy insight: $insight');
    } catch (e) {
      logger.error('Failed to add therapy insight', error: e);
      // Don't rethrow to prevent app crashes
    }
  }

  /// Records the user's emotional state
  Future<void> recordEmotionalState(String emotion, double intensity,
      {String? trigger}) async {
    await initializeIfNeeded();

    final state = EmotionalState(
      emotion: emotion,
      intensity: intensity,
      trigger: trigger,
    );

    try {
      // Add to in-memory cache
      _emotionalStates.add(state);

      // Persist to database
      try {
        await _databaseProvider.insert('emotional_states', state.toJson());
        logger.debug(
            'Recorded emotional state: $emotion (intensity: $intensity)');
      } catch (e) {
        logger.error('Failed to save emotional state to database', error: e);
        // Already added to in-memory cache, so continue
      }
    } catch (e) {
      logger.error('Failed to record emotional state', error: e);
      // Don't rethrow to prevent app crashes
    }
  }

  /// Gets recent conversation memories up to a certain number
  Future<List<ConversationMemory>> getRecentMemories({int limit = 5}) async {
    await initializeIfNeeded();

    // Sort memories by timestamp (most recent first)
    final sortedMemories = List<ConversationMemory>.from(_conversationMemories)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Return up to limit memories
    return sortedMemories.take(limit).toList();
  }

  /// Gets the current memory context as a string for LLM usage
  Future<String> getCurrentContext({int memoryLimit = 5}) async {
    await initializeIfNeeded();

    final StringBuffer contextBuffer = StringBuffer();

    // Add recent conversation history
    final recentMemories = await getRecentMemories(limit: memoryLimit);
    if (recentMemories.isNotEmpty) {
      contextBuffer.writeln('RECENT CONVERSATION HISTORY:');
      for (final memory in recentMemories) {
        contextBuffer.writeln('User: ${memory.userMessage}');
        contextBuffer.writeln('AI: ${memory.aiResponse}');
        contextBuffer.writeln();
      }
    }

    // Add key insights
    if (_insights.isNotEmpty) {
      contextBuffer.writeln('KEY INSIGHTS:');
      // Sort insights by recency
      final sortedInsights = List<TherapyInsight>.from(_insights)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Add top insights
      for (int i = 0; i < min(5, sortedInsights.length); i++) {
        final insight = sortedInsights[i];
        contextBuffer.writeln('- ${insight.insight}');
      }
      contextBuffer.writeln();
    }

    // Add emotional states
    if (_emotionalStates.isNotEmpty) {
      contextBuffer.writeln('EMOTIONAL STATES:');
      // Sort states by recency
      final sortedStates = List<EmotionalState>.from(_emotionalStates)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Add most recent emotional state
      if (sortedStates.isNotEmpty) {
        final state = sortedStates.first;
        contextBuffer.writeln(
            '- Current: ${state.emotion} (intensity: ${state.intensity}/10)');
        if (state.trigger != null) {
          contextBuffer.writeln('  Trigger: ${state.trigger}');
        }
      }

      // Add emotional trends if we have enough data
      if (sortedStates.length > 1) {
        contextBuffer.writeln('- Trends: ');
        // Logic for detecting trends would go here
      }

      contextBuffer.writeln();
    }

    return contextBuffer.toString();
  }

  /// Clears all memory (use with caution)
  Future<void> clearMemory() async {
    await initializeIfNeeded();

    try {
      // Clear in-memory caches
      _conversationMemories.clear();
      _insights.clear();
      _emotionalStates.clear();

      // Clear database tables with error handling
      try {
        await _databaseProvider.delete('conversation_memories');
      } catch (e) {
        logger.warning('Failed to clear conversation_memories table: $e');
        try {
          await _databaseProvider.delete('conversations');
        } catch (e2) {
          logger.warning('Failed to clear conversations table: $e2');
        }
      }

      try {
        await _databaseProvider.delete('therapy_insights');
      } catch (e) {
        logger.warning('Failed to clear therapy_insights table: $e');
        try {
          await _databaseProvider.delete('insights');
        } catch (e2) {
          logger.warning('Failed to clear insights table: $e2');
        }
      }

      try {
        await _databaseProvider.delete('emotional_states');
      } catch (e) {
        logger.warning('Failed to clear emotional_states table: $e');
      }

      logger.info('Memory cleared successfully');
    } catch (e) {
      logger.error('Failed to clear memory', error: e);
      // Don't rethrow to prevent app crashes
    }
  }

  // Helper method to get the minimum of two numbers
  int min(int a, int b) {
    return a < b ? a : b;
  }
}
