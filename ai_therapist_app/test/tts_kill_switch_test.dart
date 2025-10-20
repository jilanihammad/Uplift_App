import 'package:ai_therapist_app/config/app_config.dart';
import 'package:ai_therapist_app/config/tts_streaming_config.dart';
import 'package:ai_therapist_app/services/remote_config_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(fileInput: 'TTS_STREAMING_ENABLED=true');
    AppConfig().clearRuntimeOverrides();
  });

  test('kill switch disables streaming at runtime', () async {
    // Sanity check default is enabled
    expect(TTSStreamingConfig.isEnabled, isTrue);

    await RemoteConfigService().forceOverride(ttsStreamingEnabled: false);

    expect(TTSStreamingConfig.isEnabled, isFalse);
    expect(TTSStreamingConfig.shouldUseStreaming, isFalse);
  });

  test('kill switch re-enables streaming when toggled on', () async {
    await RemoteConfigService().forceOverride(ttsStreamingEnabled: false);
    expect(TTSStreamingConfig.isEnabled, isFalse);

    await RemoteConfigService().forceOverride(ttsStreamingEnabled: true);

    expect(TTSStreamingConfig.isEnabled, isTrue);
    expect(TTSStreamingConfig.shouldUseStreaming, isTrue);
  });

  test('buffer and memory overrides update AppConfig', () async {
    const bufferOverride = 16384;
    const memoryOverride = 120;

    await RemoteConfigService().forceOverride(
      bufferSize: bufferOverride,
      maxMemorySeconds: memoryOverride,
    );

    expect(AppConfig().ttsStreamingBufferSize, bufferOverride);
    expect(AppConfig().ttsMaxMemoryDurationSeconds, memoryOverride);
  });
}
