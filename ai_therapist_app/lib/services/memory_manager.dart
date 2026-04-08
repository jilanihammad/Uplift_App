import 'dart:async';
import 'package:mutex/mutex.dart';
import '../services/memory_service.dart';
import '../utils/logging_service.dart';
import '../di/initialization_tracker.dart';
import '../di/interfaces/i_memory_manager.dart';
import '../models/conversation_memory.dart';
class MemoryManager implements IMemoryManager {
  static final Mutex _initMutex = Mutex();
  static bool _staticInitialized = false;
  final MemoryService _memoryService;
  bool _isInitialized = false;
  String? _lastInitError;
  int _initAttempts = 0;
  static const int _maxInitAttempts = 3;
  MemoryManager({required MemoryService memoryService})
      : _memoryService = memoryService;
  Future<void> initialize() async {
    await init();
  }
  Future<void> init() async {
    if (_staticInitialized && _isInitialized) {
      return;
    }
    await _initMutex.acquire();
    try {
      if (_staticInitialized && _isInitialized) {
        return;
      }
      _initAttempts++;
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
      _isInitialized = false;
      rethrow;
    } finally {
      _initMutex.release();
    }
  }
  bool get isInitialized => _isInitialized;
  String? get lastInitError => _lastInitError;
  Future<void> initializeIfNeeded() async {
    if (_staticInitialized && _isInitialized) {
      return;
    }
    if (!_isInitialized && _initAttempts < _maxInitAttempts) {
      await init();
    } else if (_isInitialized) {
    } else {
      logger
          .warning('MemoryManager.initializeIfNeeded() - max attempts reached');
    }
  }
  @override
  Future<void> initializeOnlyIfNeeded() async {
    return initializeIfNeeded();
  }
  @override
  Future<String> getMemoryContext() async {
    try {
      await _safeInitialize();
      return await _memoryService.getCurrentContext();
    } catch (e) {
      logger.error('Error retrieving memory context', error: e);
      return ''; // Return empty context on error
    }
  }
  @override
  Future<void> addInteraction(String userMessage, String aiResponse,
      Map<String, dynamic> metadata) async {
    try {
      await _safeInitialize();
      await _memoryService.addMemory(userMessage, aiResponse,
          metadata: metadata);
      logger.debug('Interaction added to memory');
    } catch (e) {
      logger.error('Error adding interaction to memory', error: e);
    }
  }
  @override
  Future<void> addInsight(String insightText, String source) async {
    try {
      await _safeInitialize();
      await _memoryService.addInsight(insightText, source);
      logger.debug('Insight added to memory: $insightText');
    } catch (e) {
      logger.error('Error adding insight to memory', error: e);
    }
  }
  @override
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
    }
  }
  @override
  Future<void> updateUserPreference(String key, dynamic value) async {
    try {
      await _safeInitialize();
      await _memoryService.addInsight(
          'User preference: $key = $value', 'system');
      logger.debug('User preference saved as insight: $key');
    } catch (e) {
      logger.error('Error saving user preference', error: e);
    }
  }
  @override
  Future<void> updateTherapeuticGoals(List<String> goals) async {
    try {
      await _safeInitialize();
      await _memoryService.addInsight(
          'Therapeutic goals: ${goals.join(", ")}', 'system');
      logger.debug('Therapeutic goals saved as insight: ${goals.join(", ")}');
    } catch (e) {
      logger.error('Error saving therapeutic goals', error: e);
    }
  }
  @override
  Future<void> processInsightsAndSaveMemory(String userMessage,
      Map<String, dynamic> response, Map<String, dynamic> graphResult) async {
    try {
      await _safeInitialize();
      final sessionIndex = await _memoryService.incrementSessionCounter();
      if (response.containsKey('insights') && response['insights'] != null) {
        final insights = response['insights'];
        if (insights is List && insights.isNotEmpty) {
          for (final insight in insights) {
            try {
              await addInsight(insight, 'ai');
            } catch (e) {
              logger.warning('Error saving individual insight: $e');
            }
          }
        }
      }
      try {
        await addInteraction(userMessage, response['response'], {
          'state': graphResult['state'] ?? 'exploration',
          'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
          'topics': graphResult['analysis']?['topics'] ?? [],
        });
      } catch (e) {
        logger.warning('Error saving interaction to memory: $e');
      }
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
      await _updateKeyAnchors(
        userMessage: userMessage,
        graphResult: graphResult,
        sessionIndex: sessionIndex,
      );
    } catch (e) {
      logger.error('Error processing insights and saving memory', error: e);
    }
  }
  Future<void> _safeInitialize() async {
    if (_staticInitialized && _isInitialized) return;
    try {
      if (_initAttempts < _maxInitAttempts) {
        await initializeIfNeeded();
      } else if (_initAttempts == _maxInitAttempts) {
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
    String titleCaseSegment(String input) {
      return input.replaceAllMapped(RegExp(r"[A-Za-z]+"), (match) {
        final segment = match.group(0)!;
        return segment[0].toUpperCase() + segment.substring(1).toLowerCase();
      });
    }
    String? sanitizeName(String raw) {
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
      final formatted = words.map(titleCaseSegment).join(' ');
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
    final namePattern = RegExp(
      r"\b(my name is|call me|you can call me)\s+([A-Za-z][A-Za-z'\- ]{1,40})",
      caseSensitive: false,
    );
    for (final match in namePattern.allMatches(userMessage)) {
      final raw = match.group(2);
      final cleaned = raw != null ? sanitizeName(raw) : null;
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
      final cleaned = raw != null ? sanitizeName(raw) : null;
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
    final relationshipPattern = RegExp(
      r'\bmy\s+(wife|husband|partner|boyfriend|girlfriend|fiancé|fiancee|son|daughter|child|kid|kids|mom|mother|dad|father|sister|brother|grandma|grandmother|grandpa|grandfather|best friend|friend)\b',
      caseSensitive: false,
    );
    for (final match in relationshipPattern.allMatches(lower)) {
      addCandidate(match.group(0) ?? '', type: 'relationship', confidence: 0.9);
    }
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
  @override
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
  static Future<String> getMemoryContextBackground(
      MemoryService memoryService) async {
    try {
      return await memoryService.getCurrentContext();
    } catch (e) {
      logger.error('Error getting memory context in background', error: e);
      return '';
    }
  }
  void dispose() {
    _isInitialized = false;
  }
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
