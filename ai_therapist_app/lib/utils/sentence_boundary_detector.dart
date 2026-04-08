class SentenceBoundaryDetector {
  // Buffer to accumulate incoming text chunks
  String _buffer = '';
  String _processedText = '';
  static const List<String> _sentenceEnders = ['.', '!', '?', '...'];
  static const Set<String> _abbreviations = {
    'dr',
    'mr',
    'mrs',
    'ms',
    'prof',
    'inc',
    'ltd',
    'vs',
    'etc',
    'eg',
    'ie',
    'st',
    'ave',
    'blvd',
    'rd',
    'jr',
    'sr',
    'vol',
    'no',
    'pp',
    'ph',
    'md',
    'co',
    'corp',
    'llc',
    'org',
    'govt',
    'dept',
    'univ',
    'assn',
    'bros',
    'min',
    'max',
    'temp',
    'avg',
    'est',
    'approx',
    'misc',
    'gen',
    'spec'
  };
  void addChunk(String chunk) {
    _buffer += chunk;
  }
  List<String> extractCompleteSentences() {
    if (_buffer.isEmpty) return [];
    List<String> sentences = [];
    String workingBuffer = _buffer;
    int lastSentenceEnd = 0;
    for (int i = 0; i < workingBuffer.length; i++) {
      String char = workingBuffer[i];
      if (_sentenceEnders.contains(char)) {
        if (_isRealSentenceEnd(workingBuffer, i)) {
          String sentence =
              workingBuffer.substring(lastSentenceEnd, i + 1).trim();
          if (sentence.isNotEmpty && sentence.length > 3) {
            if (!_processedText.contains(sentence)) {
              sentences.add(sentence);
              _processedText += '$sentence ';
            }
          }
          lastSentenceEnd = i + 1;
        }
      }
    }
    if (lastSentenceEnd > 0 && lastSentenceEnd < workingBuffer.length) {
      _buffer = workingBuffer.substring(lastSentenceEnd).trim();
    } else if (lastSentenceEnd >= workingBuffer.length) {
      _buffer = '';
    }
    return sentences;
  }
  bool _isRealSentenceEnd(String text, int position) {
    String char = text[position];
    if (char == '.' && position >= 2) {
      if (text.substring(position - 2, position + 1) == '...') {
        return true;
      }
    }
    if (char == '!' || char == '?') {
      return true;
    }
    if (char == '.') {
      int wordStart = position - 1;
      while (wordStart >= 0 && text[wordStart] != ' ') {
        wordStart--;
      }
      wordStart++; // Move to start of word
      if (wordStart < position) {
        String word = text.substring(wordStart, position).toLowerCase();
        if (_abbreviations.contains(word)) {
          return false;
        }
        if (RegExp(r'^\d+$').hasMatch(word)) {
          return false;
        }
        if (position + 1 < text.length) {
          String nextChar = text[position + 1];
          if (nextChar != ' ' && nextChar.toLowerCase() == nextChar) {
            return false;
          }
        }
      }
      return true;
    }
    return false;
  }
  String getRemainingBuffer() {
    return _buffer;
  }
  String? flushRemaining() {
    if (_buffer.trim().isEmpty) return null;
    String remaining = _buffer.trim();
    _buffer = '';
    if (remaining.length > 5) {
      return remaining;
    }
    return null;
  }
  void reset() {
    _buffer = '';
    _processedText = '';
  }
  bool get hasUnprocessedContent => _buffer.trim().isNotEmpty;
  Map<String, dynamic> getStats() {
    return {
      'buffer_length': _buffer.length,
      'processed_length': _processedText.length,
      'has_unprocessed': hasUnprocessedContent,
    };
  }
  static List<String> splitForTTSStreaming(String text,
      {int maxChunkLength = 200}) {
    if (text.length <= maxChunkLength) {
      return [text];
    }
    List<String> chunks = [];
    List<String> sentences = text.split(RegExp(r'[.!?]+'));
    String currentChunk = '';
    for (String sentence in sentences) {
      sentence = sentence.trim();
      if (sentence.isEmpty) continue;
      if (!sentence.endsWith('.') &&
          !sentence.endsWith('!') &&
          !sentence.endsWith('?')) {
        sentence += '.';
      }
      if (currentChunk.isEmpty) {
        currentChunk = sentence;
      } else if ('$currentChunk $sentence'.length <= maxChunkLength) {
        currentChunk += ' $sentence';
      } else {
        chunks.add(currentChunk);
        currentChunk = sentence;
      }
    }
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }
    return chunks;
  }
  List<String> extractTherapeuticSentences() {
    List<String> baseSentences = extractCompleteSentences();
    List<String> processedSentences = [];
    for (String sentence in baseSentences) {
      if (_isTherapeuticPause(sentence)) {
        List<String> segments = _splitAtTherapeuticPauses(sentence);
        processedSentences.addAll(segments);
      } else {
        processedSentences.add(sentence);
      }
    }
    return processedSentences;
  }
  bool _isTherapeuticPause(String sentence) {
    List<String> pausePatterns = [
      ', and ',
      ', but ',
      ', however ',
      ', although ',
      ', while ',
      ', because ',
      ', since ',
      ', therefore ',
      ', so ',
      ', yet ',
    ];
    return pausePatterns
        .any((pattern) => sentence.toLowerCase().contains(pattern));
  }
  List<String> _splitAtTherapeuticPauses(String sentence) {
    List<String> segments = [];
    List<String> pausePatterns = [
      ', and ',
      ', but ',
      ', however ',
      ', although ',
      ', while ',
      ', because ',
      ', since ',
      ', therefore ',
      ', so ',
      ', yet ',
    ];
    String remaining = sentence;
    for (String pattern in pausePatterns) {
      if (remaining.toLowerCase().contains(pattern.toLowerCase())) {
        List<String> parts =
            remaining.split(RegExp(pattern, caseSensitive: false));
        if (parts.length > 1) {
          String firstPart = parts[0].trim() + pattern.trim();
          if (firstPart.length > 10) {
            segments.add(firstPart);
            remaining = parts.sublist(1).join(pattern);
          }
        }
        break;
      }
    }
    if (remaining.trim().isNotEmpty && remaining.trim().length > 5) {
      segments.add(remaining.trim());
    }
    return segments.isNotEmpty ? segments : [sentence];
  }
}
