/// Utility class for detecting sentence boundaries in streaming text
/// This enables natural TTS streaming by processing complete sentences
class SentenceBoundaryDetector {
  // Buffer to accumulate incoming text chunks
  String _buffer = '';

  // Track processed text to avoid repetition
  String _processedText = '';

  // Sentence ending patterns
  static const List<String> _sentenceEnders = ['.', '!', '?', '...'];

  // Abbreviations that shouldn't end sentences
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

  /// Add new text chunk to the buffer
  void addChunk(String chunk) {
    _buffer += chunk;
  }

  /// Extract complete sentences from the buffer
  /// Returns list of complete sentences ready for TTS
  List<String> extractCompleteSentences() {
    if (_buffer.isEmpty) return [];

    List<String> sentences = [];
    String workingBuffer = _buffer;

    // Find sentence boundaries
    int lastSentenceEnd = 0;

    for (int i = 0; i < workingBuffer.length; i++) {
      String char = workingBuffer[i];

      if (_sentenceEnders.contains(char)) {
        // Check if this is a real sentence ending
        if (_isRealSentenceEnd(workingBuffer, i)) {
          String sentence =
              workingBuffer.substring(lastSentenceEnd, i + 1).trim();

          if (sentence.isNotEmpty && sentence.length > 3) {
            // Check if we haven't already processed this sentence
            if (!_processedText.contains(sentence)) {
              sentences.add(sentence);
              _processedText += '$sentence ';
            }
          }

          lastSentenceEnd = i + 1;
        }
      }
    }

    // Update buffer to keep unprocessed text
    if (lastSentenceEnd > 0 && lastSentenceEnd < workingBuffer.length) {
      _buffer = workingBuffer.substring(lastSentenceEnd).trim();
    } else if (lastSentenceEnd >= workingBuffer.length) {
      _buffer = '';
    }

    return sentences;
  }

  /// Check if a punctuation mark is a real sentence ending
  bool _isRealSentenceEnd(String text, int position) {
    String char = text[position];

    // Handle ellipsis
    if (char == '.' && position >= 2) {
      if (text.substring(position - 2, position + 1) == '...') {
        return true;
      }
    }

    // Regular sentence enders
    if (char == '!' || char == '?') {
      return true;
    }

    // For periods, check for abbreviations
    if (char == '.') {
      // Look for word before the period
      int wordStart = position - 1;
      while (wordStart >= 0 && text[wordStart] != ' ') {
        wordStart--;
      }
      wordStart++; // Move to start of word

      if (wordStart < position) {
        String word = text.substring(wordStart, position).toLowerCase();

        // Check if it's a known abbreviation
        if (_abbreviations.contains(word)) {
          return false;
        }

        // Check if it's a number (like "3.14")
        if (RegExp(r'^\d+$').hasMatch(word)) {
          return false;
        }

        // Check if next character is lowercase (likely continuation)
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

  /// Get remaining buffer content (incomplete sentence)
  String getRemainingBuffer() {
    return _buffer;
  }

  /// Force flush remaining buffer as a sentence (for end of stream)
  String? flushRemaining() {
    if (_buffer.trim().isEmpty) return null;

    String remaining = _buffer.trim();
    _buffer = '';

    // Only return if it's substantial content
    if (remaining.length > 5) {
      return remaining;
    }

    return null;
  }

  /// Reset the detector for a new stream
  void reset() {
    _buffer = '';
    _processedText = '';
  }

  /// Check if there's unprocessed content
  bool get hasUnprocessedContent => _buffer.trim().isNotEmpty;

  /// Get statistics about processing
  Map<String, dynamic> getStats() {
    return {
      'buffer_length': _buffer.length,
      'processed_length': _processedText.length,
      'has_unprocessed': hasUnprocessedContent,
    };
  }

  /// Split text into optimal chunks for TTS streaming
  /// This method handles cases where complete sentences are too long
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

      // Add appropriate punctuation back
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
        // Current chunk is full, add it and start new chunk
        chunks.add(currentChunk);
        currentChunk = sentence;
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }

    return chunks;
  }

  /// Advanced sentence detection with context awareness
  /// This considers therapeutic conversation patterns
  List<String> extractTherapeuticSentences() {
    List<String> baseSentences = extractCompleteSentences();
    List<String> processedSentences = [];

    for (String sentence in baseSentences) {
      // Handle therapeutic conversation patterns
      if (_isTherapeuticPause(sentence)) {
        // Split at natural pause points
        List<String> segments = _splitAtTherapeuticPauses(sentence);
        processedSentences.addAll(segments);
      } else {
        processedSentences.add(sentence);
      }
    }

    return processedSentences;
  }

  /// Check if sentence contains therapeutic pause patterns
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

  /// Split sentence at natural therapeutic conversation pauses
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
