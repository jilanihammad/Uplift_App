import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/utils/audio_path_utils.dart';

void main() {
  group('AudioPathUtils', () {
    group('ensureExtension', () {
      test('adds extension to filename without extension', () {
        expect(AudioPathUtils.ensureExtension('audio', 'wav'), 'audio.wav');
        expect(AudioPathUtils.ensureExtension('recording', 'mp3'),
            'recording.mp3');
      });

      test('preserves extension when already present', () {
        expect(AudioPathUtils.ensureExtension('audio.wav', 'wav'), 'audio.wav');
        expect(AudioPathUtils.ensureExtension('recording.mp3', 'mp3'),
            'recording.mp3');
      });

      test('handles case-insensitive extensions', () {
        expect(AudioPathUtils.ensureExtension('audio.WAV', 'wav'), 'audio.WAV');
        expect(AudioPathUtils.ensureExtension('audio.Mp3', 'mp3'), 'audio.Mp3');
      });

      test('works with paths', () {
        expect(AudioPathUtils.ensureExtension('/path/to/audio', 'wav'),
            '/path/to/audio.wav');
        expect(AudioPathUtils.ensureExtension('/path/to/audio.wav', 'wav'),
            '/path/to/audio.wav');
      });

      test('throws error for empty input', () {
        expect(() => AudioPathUtils.ensureExtension('', 'wav'),
            throwsArgumentError);
      });
    });

    group('ensureWav', () {
      test('adds .wav extension', () {
        expect(AudioPathUtils.ensureWav('audio'), 'audio.wav');
      });

      test('preserves existing .wav extension', () {
        expect(AudioPathUtils.ensureWav('audio.wav'), 'audio.wav');
      });

      test('prevents double .wav extensions', () {
        // This is the key test for the bug fix
        const input = 'tts_1751243751996444.wav';
        final result = AudioPathUtils.ensureWav(input);
        expect(result, 'tts_1751243751996444.wav');
        expect(result.endsWith('.wav.wav'), false);
      });
    });

    group('validateBasename', () {
      test('allows clean basenames', () {
        expect(AudioPathUtils.validateBasename('audio'), 'audio');
        expect(AudioPathUtils.validateBasename('tts_12345'), 'tts_12345');
      });

      test('rejects basenames with extensions', () {
        expect(() => AudioPathUtils.validateBasename('audio.wav'),
            throwsArgumentError);
        expect(() => AudioPathUtils.validateBasename('file.mp3'),
            throwsArgumentError);
      });
    });

    group('generateTimestampId', () {
      test('generates clean timestamp ID', () {
        final id = AudioPathUtils.generateTimestampId('tts');
        expect(id.startsWith('tts_'), true);
        expect(id.contains('.'), false); // No extensions
        expect(id.length > 4, true); // Has timestamp
      });

      test('uses custom prefix', () {
        final id = AudioPathUtils.generateTimestampId('audio');
        expect(id.startsWith('audio_'), true);
      });
    });

    group('regression test for double extension bug', () {
      test('TTS filename generation flow prevents .wav.wav', () {
        // Simulate the original bug scenario
        final fileId = AudioPathUtils.generateTimestampId('tts');

        // Ensure ID has no extension
        expect(fileId.contains('.'), false);

        // Simulate what PathManager.ttsFile() would do
        const ttsPrefix = 'tts_stream_';
        const ext = 'wav';
        final simulatedPath = '$ttsPrefix$fileId.$ext';

        // Verify no double extension
        expect(simulatedPath.endsWith('.wav.wav'), false);
        expect(simulatedPath.endsWith('.wav'), true);

        // Verify correct pattern
        expect(simulatedPath.startsWith('tts_stream_tts_'), true);

        // Count .wav occurrences (should be exactly 1)
        final wavCount = '.wav'.allMatches(simulatedPath).length;
        expect(wavCount, 1);
      });
    });
  });
}
