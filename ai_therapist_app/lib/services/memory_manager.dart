import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import '../services/memory_service.dart';
import '../utils/logging_service.dart';
import '../di/initialization_tracker.dart';
import '../di/interfaces/i_memory_manager.dart';
import '../models/conversation_memory.dart';

/// Handles management of conversation memory and context for therapy sessions
class MemoryManager implements IMemoryManager {
  // Static mutex to guard initialization across all instances
  static final Mutex _initMutex = Mutex();

  // Static initialization tracking to prevent double initialization
  static bool _staticInitialized = false;

  // The underlying memory service
  final MemoryService _memoryService;

  // Initialization status
  bool _isInitialized = false;

  // Error state tracking
  String? _lastInitError;
  int _initAttempts = 0;
  static const int _maxInitAttempts = 3;

  // Constructor
  MemoryManager({required MemoryService memoryService})
      : _memoryService = memoryService;

  /// Initialize the memory manager
  @override
  Future<void> initialize() async {
    await init();
  }

  /// Legacy initialization method - use initialize() instead
  Future<void> init() async {
    // Fast path: Check if already initialized without acquiring mutex
    if (_staticInitialized && _isInitialized) {
      if (kDebugMode) {
        logger.debug('MemoryManager already initialized (fast path)');
      }
      return;
    }

    // Acquire mutex to prevent concurrent initialization
    await _initMutex.acquire();

    try {
      // Double-check inside mutex
      if (_staticInitialized && _isInitialized) {
        if (kDebugMode) {
          logger.debug('MemoryManager already initialized (mutex path)');
        }
        return;
      }

      _initAttempts++;

      // Add stack trace to understand where initialization is called from
      if (kDebugMode) {
        logger.debug(
            'Initializing MemoryManager (attempt $_initAttempts of $_maxInitAttempts)\n'
            'Called from: ${StackTrace.current.toString().split('\n').take(5).join('\n')}');
      } else {
        logger.debug(
            'Initializing MemoryManager (attempt $_initAttempts of $_maxInitAttempts)');
      }

      // Use initialization tracker for consistent initialization pattern
      final success =
          await initTracker.initializeWithRetry('MemoryManager', () async {
        await _memoryService.initializeIfNeeded();
        _isInitialized = true;
        _staticInitialized = true; // Mark static initialization complete
        _lastInitError = null;
      });

      if (success) {
        logger.info('MemoryManager initialized ✓');
      } else {
        _isInitialized = false;
        _lastInitError = 'Failed to initialize after multiple attempts';
        logger
            .error('Failed to initialize memory manager after maximum retries');
        throw Exception(_lastInitError!);
      }
    } catch (e) {
      _lastInitError = e.toString();
      logger.error('Failed to initialize memory manager', error: e);

      // Allow continued operation with limited functionality even after failed init
      _isInitialized = false;
      rethrow;
    } finally {
      _initMutex.release();
    }
  }

  /// Check if already initialized
  @override
  bool get isInitialized => _isInitialized;

  /// Get the last initialization error
  String? get lastInitError => _lastInitError;

  /// Initialize only if not already initialized
  Future<void> initializeIfNeeded() async {
    // Fast path: Check if already initialized without logging
    if (_staticInitialized && _isInitialized) {
      return;
    }

    if (!_isInitialized && _initAttempts < _maxInitAttempts) {
      if (kDebugMode) {
        logger.debug(
            'MemoryManager.initializeIfNeeded() - triggering initialization');
      }
      await init();
    } else if (_isInitialized) {
      if (kDebugMode) {
        logger
            .debug('MemoryManager.initializeIfNeeded() - already initialized');
      }
    } else {
      logger
          .warning('MemoryManager.initializeIfNeeded() - max attempts reached');
    }
  }

  /// Legacy method for backward compatibility
  @override
  Future<void> initializeOnlyIfNeeded() async {
    if (kDebugMode) {
      logger.debug(
          'MemoryManager.initializeOnlyIfNeeded() - delegating to initializeIfNeeded()');
    }
    return initializeIfNeeded();
  }

  /// Get relevant context for the current conversation
  Future<String> getMemoryContext() async {
    try {
      await _safeInitialize();
      return await _memoryService.getCurrentContext();
    } catch (e) {
      logger.error('Error retrieving memory context', error: e);
      return ''; // Return empty context on error
    }
  }

  /// Add interaction between user and AI to memory
  Future<void> addInteraction(String userMessage, String aiResponse,
      Map<String, dynamic> metadata) async {
    try {
      await _safeInitialize();
      await _memoryService.addMemory(userMessage, aiResponse,
          metadata: metadata);
      logger.debug('Interaction added to memory');
    } catch (e) {
      logger.error('Error adding interaction to memory', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Add an insight to memory
  Future<void> addInsight(String insightText, String source) async {
    try {
      await _safeInitialize();
      await _memoryService.addInsight(insightText, source);
      logger.debug('Insight added to memory: $insightText');
    } catch (e) {
      logger.error('Error adding insight to memory', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Update the emotional state in memory
  Future<void> updateEmotionalState(
      String emotion, double intensity, String? trigger) async {
    try {
      await _safeInitialize();
      await _memoryService.recordEmotionalState(emotion, intensity,
          trigger: trigger);
      logger.debug(
          'Emotional state updated: $emotion (${intensity.toStringAsFixed(1)}/10)');
    } catch (e) {
      logger.error('Error updating emotional state', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Update user preferences - this is no longer supported in the new implementation
  Future<void> updateUserPreference(String key, dynamic value) async {
    try {
      await _safeInitialize();
      // Add a fallback implementation using insights
      await _memoryService.addInsight(
          'User preference: $key = $value', 'system');
      logger.debug('User preference saved as insight: $key');
    } catch (e) {
      logger.error('Error saving user preference', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Update therapeutic goals - this is no longer supported in the new implementation
  Future<void> updateTherapeuticGoals(List<String> goals) async {
    try {
      await _safeInitialize();
      // Add a fallback implementation using insights
      await _memoryService.addInsight(
          'Therapeutic goals: ${goals.join(", ")}', 'system');
      logger.debug('Therapeutic goals saved as insight: ${goals.join(", ")}');
    } catch (e) {
      logger.error('Error saving therapeutic goals', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Process insights from a response and save to memory
  Future<void> processInsightsAndSaveMemory(String userMessage,
      Map<String, dynamic> response, Map<String, dynamic> graphResult) async {
    try {
      await _safeInitialize();

      final sessionIndex = await _memoryService.incrementSessionCounter();

      // Extract any insights detected in the response
      if (response.containsKey('insights') && response['insights'] != null) {
        final insights = response['insights'];
        if (insights is List && insights.isNotEmpty) {
          for (final insight in insights) {
            try {
              await addInsight(insight, 'ai');
            } catch (e) {
              logger.warning('Error saving individual insight: $e');
              // Continue with next insight
            }
          }
        }
      }

      // Save interaction to memory
      try {
        await addInteraction(userMessage, response['response'], {
          'state': graphResult['state'] ?? 'exploration',
          'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
          'topics': graphResult['analysis']?['topics'] ?? [],
        });
      } catch (e) {
        logger.warning('Error saving interaction to memory: $e');
      }

      // Extract any detected emotional state
      if (graphResult.containsKey('analysis') &&
          graphResult['analysis'] != null &&
          graphResult['analysis'].containsKey('emotion') &&
          graphResult['analysis'].containsKey('emotionIntensity')) {
        try {
          await updateEmotionalState(
              graphResult['analysis']['emotion'],
              graphResult['analysis']['emotionIntensity'],
              userMessage.length > 50
                  ? '${userMessage.substring(0, 50)}...'
                  : userMessage);
        } catch (e) {
          logger.warning('Error updating emotional state: $e');
        }
      }

      // Update key anchors based on new information
      await _updateKeyAnchors(
        userMessage: userMessage,
        graphResult: graphResult,
        sessionIndex: sessionIndex,
      );
    } catch (e) {
      logger.error('Error processing insights and saving memory', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Safely initialize the service, handling errors gracefully
  Future<void> _safeInitialize() async {
    // Fast path: Check if already initialized
    if (_staticInitialized && _isInitialized) return;

    try {
      if (_initAttempts < _maxInitAttempts) {
        await initializeIfNeeded();
      } else if (_initAttempts == _maxInitAttempts) {
        // One final attempt with mutex protection
        await _initMutex.acquire();
        try {
          if (!_isInitialized) {
            _initAttempts++;
            logger.warning('Making final attempt to initialize MemoryManager');
            await _memoryService.initializeIfNeeded();
            _isInitialized = true;
            _staticInitialized = true;
            logger.info('MemoryManager initialized ✓ (final attempt)');
          }
        } finally {
          _initMutex.release();
        }
      }
    } catch (e) {
      // Log but allow operation to continue
      logger.error('Failed to initialize in _safeInitialize', error: e);
    }
  }

  Future<void> _updateKeyAnchors({
    required String userMessage,
    required Map<String, dynamic> graphResult,
    required int sessionIndex,
  }) async {
    final candidates = _extractAnchorCandidates(userMessage, graphResult);
    final candidateNormalized = candidates.map((c) => c.normalizedText).toSet();

    for (final candidate in candidates) {
      await _memoryService.addOrUpdateAnchor(
        anchorText: candidate.anchorText,
        anchorType: candidate.anchorType,
        confidence: candidate.confidence,
        sessionIndex: sessionIndex,
      );
    }

    // Refresh anchors that were referenced but not captured as new candidates
    final lowerMessage = userMessage.toLowerCase();
    for (final anchor in _memoryService.getAnchors()) {
      if (candidateNormalized.contains(anchor.normalizedText)) {
        continue;
      }

      if (_messageMentionsAnchor(lowerMessage, anchor)) {
        await _memoryService.refreshAnchor(anchor, sessionIndex);
      }
    }
  }

  List<_AnchorCandidate> _extractAnchorCandidates(
    String userMessage,
    Map<String, dynamic> graphResult,
  ) {
    final lower = userMessage.toLowerCase();
    final seen = <String>{};
    final candidates = <_AnchorCandidate>[];

    String _titleCaseSegment(String input) {
      return input.replaceAllMapped(RegExp(r"[A-Za-z]+"), (match) {
        final segment = match.group(0)!;
        return segment[0].toUpperCase() + segment.substring(1).toLowerCase();
      });
    }

    String? _sanitizeName(String raw) {
      if (raw.isEmpty) return null;
      var candidate = raw.split(RegExp(r"[\.,!?]")).first;
      candidate = candidate.replaceAll(RegExp(r"[^A-Za-z'\-\s]"), ' ').trim();
      if (candidate.isEmpty) return null;

      final words =
          candidate.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
      if (words.isEmpty || words.length > 3) {
        return null;
      }

      const disallowed = {
        'feeling',
        'feel',
        'feels',
        'feelin',
        'doing',
        'going',
        'trying',
        'being',
        'living',
        'working',
        'worried',
        'anxious',
        'sad',
        'happy',
        'tired',
        'good',
        'bad',
        'okay',
        'ok',
        'fine',
        'alright',
        'better',
        'worse',
        'stressed',
        'stress',
        'angry',
        'maybe',
      };

      if (words.any((w) => disallowed.contains(w.toLowerCase()))) {
        return null;
      }

      final formatted = words.map(_titleCaseSegment).join(' ');
      if (formatted.isEmpty || formatted.length > 40) {
        return null;
      }

      return formatted;
    }

    void addCandidate(String text, {String? type, double confidence = 0.6}) {
      final normalized = UserAnchor.normalize(text);
      if (normalized.isEmpty || seen.contains(normalized)) {
        return;
      }
      seen.add(normalized);
      candidates.add(_AnchorCandidate(
        anchorText: text.trim(),
        normalizedText: normalized,
        anchorType: type,
        confidence: confidence,
      ));
    }

    // Preferred name anchors
    final namePattern = RegExp(
      r"\b(my name is|call me|you can call me)\s+([A-Za-z][A-Za-z'\- ]{1,40})",
      caseSensitive: false,
    );
    for (final match in namePattern.allMatches(userMessage)) {
      final raw = match.group(2);
      final cleaned = raw != null ? _sanitizeName(raw) : null;
      if (cleaned != null) {
        addCandidate(cleaned, type: 'name', confidence: 0.98);
      }
    }

    final introPattern = RegExp(
      r"\bi['’]?m\s+([A-Za-z][A-Za-z'\- ]{1,40})",
      caseSensitive: false,
    );
    for (final match in introPattern.allMatches(userMessage)) {
      final raw = match.group(1);
      final cleaned = raw != null ? _sanitizeName(raw) : null;
      if (cleaned == null) {
        continue;
      }

      final trailing = userMessage.substring(match.end).trim();
      if (trailing.isNotEmpty) {
        final trailingWord = trailing.split(RegExp(r"\s+")).first.toLowerCase();
        const stopWords = {
          'and',
          'but',
          'so',
          'because',
          'since',
          'while',
          'when',
          'feeling',
          'feel',
          'feelings',
          'feels',
          'facing',
          'having',
          'working',
          'living',
          'doing',
          'going',
          'struggling',
          'dealing',
          'experiencing',
          'getting',
          'taking',
          'thinking',
          'sleeping',
        };
        if (stopWords.contains(trailingWord)) {
          continue;
        }
      }

      addCandidate(cleaned, type: 'name', confidence: 0.9);
    }

    // Relationship-focused anchors
    final relationshipPattern = RegExp(
      r'\bmy\s+(wife|husband|partner|boyfriend|girlfriend|fiancé|fiancee|son|daughter|child|kid|kids|mom|mother|dad|father|sister|brother|grandma|grandmother|grandpa|grandfather|best friend|friend)\b',
      caseSensitive: false,
    );
    for (final match in relationshipPattern.allMatches(lower)) {
      addCandidate(match.group(0) ?? '', type: 'relationship', confidence: 0.9);
    }

    // Life events and milestones
    final eventKeywords = <String, String>{
      'wedding': 'life_event',
      'married': 'life_event',
      'engaged': 'life_event',
      'anniversary': 'life_event',
      'pregnant': 'life_event',
      'baby': 'life_event',
      'newborn': 'life_event',
      'passed away': 'life_event',
      'funeral': 'life_event',
      'lost my job': 'life_event',
      'got fired': 'life_event',
      'laid off': 'life_event',
      'got promoted': 'life_event',
      'promotion': 'life_event',
      'started a business': 'life_event',
      'graduation': 'life_event',
    };
    eventKeywords.forEach((phrase, type) {
      if (lower.contains(phrase)) {
        addCandidate(phrase, type: type, confidence: 0.75);
      }
    });

    // Passions and deeply held values
    final passionPattern = RegExp(
      r'(?:i\s+(?:really\s+)?love|i\s+am\s+passionate\s+about|it\s+means\s+so\s+much\s+to\s+me|it\s+means\s+a\s+lot\s+to\s+me|important\s+to\s+me|matters\s+a\s+lot\s+to\s+me)\s+([^\.;,]+)',
      caseSensitive: false,
    );
    for (final match in passionPattern.allMatches(lower)) {
      final raw = match.group(1)?.trim();
      if (raw != null && raw.isNotEmpty) {
        addCandidate(raw, type: 'passion', confidence: 0.65);
      }
    }

    // Goals or enduring priorities
    final goalPattern = RegExp(
      r'(?:my\s+goal\s+is|i\s+want\s+to|i\s+hope\s+to|i\s+am\s+working\s+on)\s+([^\.;,]+)',
      caseSensitive: false,
    );
    for (final match in goalPattern.allMatches(lower)) {
      final raw = match.group(1)?.trim();
      if (raw != null && raw.isNotEmpty) {
        addCandidate(raw, type: 'goal', confidence: 0.6);
      }
    }

    // Topic-informed anchors (fallback when nothing else is captured)
    final analysis = graphResult['analysis'] as Map<String, dynamic>?;
    final topics = (analysis?['topics'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        [];

    if (candidates.isEmpty && topics.isNotEmpty) {
      for (final topic in topics) {
        switch (topic) {
          case 'work':
            addCandidate('work and career', type: 'work', confidence: 0.5);
            break;
          case 'family':
            addCandidate('family connections', type: 'family', confidence: 0.5);
            break;
          case 'relationships':
            addCandidate('romantic relationships',
                type: 'relationship', confidence: 0.5);
            break;
          case 'finances':
            addCandidate('financial stability',
                type: 'finances', confidence: 0.5);
            break;
        }
      }
    }

    return candidates;
  }

  bool _messageMentionsAnchor(String lowerMessage, UserAnchor anchor) {
    if (lowerMessage.contains(anchor.normalizedText)) {
      return true;
    }

    // Additional checks for anchor types when normalized text differs
    if (anchor.anchorType == 'relationship') {
      const relationshipTerms = [
        'wife',
        'husband',
        'partner',
        'boyfriend',
        'girlfriend',
        'fiancé',
        'fiancee',
        'son',
        'daughter',
        'child',
        'kids',
        'mom',
        'mother',
        'dad',
        'father',
        'sister',
        'brother',
        'grandma',
        'grandpa',
        'friend',
      ];
      return relationshipTerms.any((term) => lowerMessage.contains(term));
    }

    if (anchor.anchorType == 'work') {
      return lowerMessage.contains('work') ||
          lowerMessage.contains('job') ||
          lowerMessage.contains('career');
    }

    if (anchor.anchorType == 'finances') {
      return lowerMessage.contains('money') || lowerMessage.contains('finance');
    }

    return false;
  }

  Future<String> getAnchorGuidance(
    String userMessage,
    Map<String, dynamic> graphResult,
  ) async {
    await _safeInitialize();

    final anchors = _memoryService.getAnchors();
    if (anchors.isEmpty) {
      return '';
    }

    final sessionIndex = _memoryService.currentSessionIndex;
    final lowerMessage = userMessage.toLowerCase();
    final topics =
        ((graphResult['analysis'] as Map<String, dynamic>?)?['topics'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toSet() ??
            <String>{};

    final relevantAnchors = anchors.where((anchor) {
      if (_messageMentionsAnchor(lowerMessage, anchor)) {
        return true;
      }
      if (anchor.anchorType == null) {
        return false;
      }
      return topics.contains(anchor.anchorType) ||
          topics.contains(anchor.anchorType!.toLowerCase());
    }).toList();

    final guidance = StringBuffer();

    if (relevantAnchors.isNotEmpty) {
      relevantAnchors.sort((a, b) {
        if (a.anchorType == 'name' && b.anchorType != 'name') {
          return -1;
        }
        if (b.anchorType == 'name' && a.anchorType != 'name') {
          return 1;
        }
        return b.confidence.compareTo(a.confidence);
      });
      guidance.writeln(
          'KEY PERSONAL DETAILS (reference gently and only if the user steers the conversation there):');
      for (final anchor in relevantAnchors) {
        final detail = anchor.anchorType == 'name'
            ? 'Preferred name: ${anchor.anchorText}. Use it naturally but sparingly.'
            : anchor.anchorText;
        guidance.writeln('- $detail');
      }
    }

    final staleAnchors =
        _memoryService.getAnchorsNeedingCheck(sessionIndex, threshold: 5);
    if (staleAnchors.isNotEmpty) {
      staleAnchors.sort((a, b) {
        if (a.anchorType == 'name' && b.anchorType != 'name') {
          return -1;
        }
        if (b.anchorType == 'name' && a.anchorType != 'name') {
          return 1;
        }
        return b.lastSeenAt.compareTo(a.lastSeenAt);
      });
      guidance.writeln(
          'It has been several sessions since these mattered; if the moment feels natural, softly check whether they are still important:');
      for (final anchor in staleAnchors) {
        final detail = anchor.anchorType == 'name'
            ? 'Confirm they still prefer the name ${anchor.anchorText}. Treat this gently.'
            : anchor.anchorText;
        guidance.writeln('- $detail');
      }

      for (final anchor in staleAnchors) {
        await _memoryService.markAnchorPrompted(anchor, sessionIndex);
      }
    }

    final text = guidance.toString().trim();
    return text.isEmpty ? '' : text;
  }

  /// Get memory context in background process
  static Future<String> getMemoryContextBackground(
      MemoryService memoryService) async {
    try {
      return await memoryService.getCurrentContext();
    } catch (e) {
      logger.error('Error getting memory context in background', error: e);
      return '';
    }
  }

  // Interface implementation methods
  @override
  Future<void> storeMemory(
    String sessionId,
    String content, {
    Map<String, dynamic>? metadata,
    List<String>? tags,
  }) async {
    try {
      await _safeInitialize();
      await _memoryService.addMemory(content, '', metadata: metadata ?? {});
    } catch (e) {
      logger.error('Error storing memory', error: e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveMemories(
    String sessionId, {
    String? query,
    List<String>? tags,
    int limit = 10,
  }) async {
    try {
      await _safeInitialize();
      // MemoryService doesn't have a direct retrieve method
      // Return empty list for now
      return [];
    } catch (e) {
      logger.error('Error retrieving memories', error: e);
      return [];
    }
  }

  @override
  Future<void> updateMemory(
    String memoryId,
    String content, {
    Map<String, dynamic>? metadata,
  }) async {
    // Not implemented in underlying service
    logger.debug('updateMemory not implemented: $memoryId');
  }

  @override
  Future<void> deleteMemory(String memoryId) async {
    // Not implemented in underlying service
    logger.debug('deleteMemory not implemented: $memoryId');
  }

  @override
  Future<void> clearSessionMemories(String sessionId) async {
    // Not implemented in underlying service
    logger.debug('clearSessionMemories not implemented: $sessionId');
  }

  @override
  Future<void> updateContext(
      String sessionId, Map<String, dynamic> context) async {
    // Not implemented in underlying service
    logger.debug('updateContext not implemented: $sessionId');
  }

  @override
  Future<Map<String, dynamic>?> getContext(String sessionId) async {
    try {
      await _safeInitialize();
      final context = await getMemoryContext();
      return {'context': context};
    } catch (e) {
      logger.error('Error getting context', error: e);
      return null;
    }
  }

  @override
  Future<void> clearContext(String sessionId) async {
    // Not implemented in underlying service
    logger.debug('clearContext not implemented: $sessionId');
  }

  @override
  Future<void> addToHistory(
    String sessionId,
    String role,
    String content, {
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _safeInitialize();
      if (role == 'user') {
        await _memoryService.addMemory(content, '', metadata: metadata ?? {});
      } else {
        await _memoryService.addMemory('', content, metadata: metadata ?? {});
      }
    } catch (e) {
      logger.error('Error adding to history', error: e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getHistory(
    String sessionId, {
    int limit = 50,
    String? fromTimestamp,
  }) async {
    try {
      await _safeInitialize();
      // MemoryService doesn't have a direct history method
      // Return empty list for now
      return [];
    } catch (e) {
      logger.error('Error getting history', error: e);
      return [];
    }
  }

  @override
  Future<void> summarizeHistory(String sessionId) async {
    // Not implemented in underlying service
    logger.debug('summarizeHistory not implemented: $sessionId');
  }

  @override
  Future<Map<String, dynamic>> getMemoryStats(String sessionId) async {
    return {
      'total_memories': 0,
      'session_id': sessionId,
      'last_updated': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<List<String>> extractKeyTopics(String sessionId) async {
    return [];
  }

  @override
  Future<Map<String, double>> getSentimentAnalysis(String sessionId) async {
    return {
      'positive': 0.0,
      'negative': 0.0,
      'neutral': 1.0,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> searchMemories(
    String query, {
    String? sessionId,
    List<String>? tags,
    double threshold = 0.7,
  }) async {
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> getRelatedMemories(
    String memoryId, {
    int limit = 5,
    double threshold = 0.8,
  }) async {
    return [];
  }

  @override
  void dispose() {
    // Cleanup resources
    _isInitialized = false;
  }

  @override
  int get memoryCount => 0;
}

class _AnchorCandidate {
  final String anchorText;
  final String normalizedText;
  final String? anchorType;
  final double confidence;

  _AnchorCandidate({
    required this.anchorText,
    required this.normalizedText,
    this.anchorType,
    required this.confidence,
  });
}
