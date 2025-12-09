# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.editing.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }

# Firebase Crashlytics
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**

# Firebase Auth
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Firebase Firestore
-keep class com.google.firebase.firestore.** { *; }

# Firebase Storage
-keep class com.google.firebase.storage.** { *; }

# Gson
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Android
-keep class android.support.v4.app.** { *; }
-keep interface android.support.v4.app.** { *; }

# Keep your model classes
-keep class com.maya.uplift.models.** { *; }
-keep class com.maya.uplift.data.models.** { *; }
-keep class com.maya.uplift.domain.entities.** { *; }

# Just Audio
-keep class com.ryanheise.** { *; }

# ExoPlayer (used by just_audio)
-keep class com.google.android.exoplayer2.** { *; }
-keep interface com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Audio codecs and decoders
-keep class com.google.android.exoplayer2.audio.** { *; }
-keep class com.google.android.exoplayer2.decoder.** { *; }
-keep class com.google.android.exoplayer2.extractor.** { *; }
-keep class com.google.android.exoplayer2.mediacodec.** { *; }

# Audio focus and playback
-keep class com.google.android.exoplayer2.ExoPlayer { *; }
-keep class com.google.android.exoplayer2.SimpleExoPlayer { *; }
-keep class com.google.android.exoplayer2.source.** { *; }
-keep class com.google.android.exoplayer2.upstream.** { *; }

# Auth
-keep class com.google.android.gms.auth.** { *; }

# HTTP
-dontwarn org.codehaus.mojo.animal_sniffer.*

# Play Core
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep classes related to Flutter HTTP client and networking
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.connectivity.** { *; }
-keep class io.flutter.embedding.engine.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.platform.** { *; }
-keep class dart.** { *; }
-keep class io.dart.** { *; }

# Keep classes for dart:convert and http package
-keep class dart.convert.** { *; }
-keep class dart.io.** { *; } # HTTP client uses dart:io
-keep class org.conscrypt.** { *; } # Needed for TLS/SSL on some Android versions
-keep class com.google.android.gms.security.** { *; } # For security providers
-keepattributes Signature, InnerClasses, EnclosingMethod

# Keep ConfigService to prevent removal of necessary fields/methods
-keep class com.maya.uplift.services.ConfigService { *; }
-keepclassmembers class com.maya.uplift.services.ConfigService { *; }

# Broader rule to keep application Dart classes (replace if package structure differs)
-keep class com.maya.uplift.** { *; }

# Keep flutter_dotenv and shared_preferences related classes
-keep class io.github.cdimascio.dotenv.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; } # Already present but keep for clarity

# Fix for R8 full mode issues
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,RuntimeVisibleTypeAnnotations,AnnotationDefault

# Audio Recording Plugins
-keep class com.llfbandit.record.** { *; }
-keep class plugins.cachet.audio_streamer.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }

# RNNoise Flutter Plugin (Voice Activity Detection)
-keep class com.github.ashutoshgngwr.rnnoise_flutter.** { *; }

# Native audio libraries
-keep class android.media.** { *; }
-keep class android.media.AudioRecord { *; }
-keep class android.media.AudioTrack { *; }
-keep class android.media.MediaRecorder { *; }
-keep class android.media.MediaPlayer { *; }

# Audio permissions and focus
-keep class android.media.AudioManager { *; }
-keep class android.media.AudioFocusRequest { *; }

# WebSocket for TTS streaming
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep all native methods (audio plugins use JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Audio Session and Focus (CRITICAL for playback)
-keep class android.media.AudioAttributes { *; }
-keep class android.media.AudioAttributes$Builder { *; }
-keep class android.media.session.** { *; }
-keepclassmembers class android.media.session.** { *; }

# Media Player and Audio Track initialization
-keep class android.media.MediaPlayer$** { *; }
-keep class android.media.AudioTrack$** { *; }
-keepclassmembers class android.media.MediaPlayer { *; }
-keepclassmembers class android.media.AudioTrack { *; }

# Audio Format and Encoding
-keep class android.media.AudioFormat { *; }
-keep class android.media.AudioFormat$Builder { *; }
-keep enum android.media.AudioFormat$Encoding { *; }

# ExoPlayer audio renderer (critical!)
-keep class com.google.android.exoplayer2.audio.AudioRendererEventListener { *; }
-keep class com.google.android.exoplayer2.audio.AudioSink { *; }
-keep class com.google.android.exoplayer2.audio.DefaultAudioSink { *; }
-keep class com.google.android.exoplayer2.audio.DefaultAudioSink$** { *; }
-keepclassmembers class com.google.android.exoplayer2.audio.** { *; }

# Audio processor chain
-keep class com.google.android.exoplayer2.audio.AudioProcessor { *; }
-keep class com.google.android.exoplayer2.audio.AudioProcessor$** { *; }

# Just Audio method channels
-keep class com.ryanheise.just_audio.** { *; }
-keepclassmembers class com.ryanheise.just_audio.** { *; }

# Audio streaming data source
-keep class com.google.android.exoplayer2.upstream.DataSource { *; }
-keep class com.google.android.exoplayer2.upstream.DataSource$** { *; }
-keep class com.google.android.exoplayer2.upstream.DefaultDataSource { *; }

# Keep reflection used by audio libraries
-keepattributes *Annotation*,Signature,Exception,InnerClasses

# Audio Codecs (AAC, MP3, OPUS, WAV decoders)
-keep class com.google.android.exoplayer2.ext.** { *; }
-keep class com.google.android.exoplayer2.extractor.wav.** { *; }
-keep class com.google.android.exoplayer2.extractor.mp3.** { *; }
-keep class com.google.android.exoplayer2.audio.AudioCapabilities { *; }
-keep class com.google.android.exoplayer2.audio.AudioCapabilitiesReceiver { *; }

# Media codecs and decoders
-keep class android.media.MediaCodec { *; }
-keep class android.media.MediaCodec$** { *; }
-keep class android.media.MediaCodecInfo { *; }
-keep class android.media.MediaCodecInfo$** { *; }
-keep class android.media.MediaCodecList { *; }

# Prevent stripping of audio-related enums and constants
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep audio plugin registration
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keepclassmembers class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# CRITICAL: Live audio streaming sources (used by TTS)
-keep class com.ryanheise.just_audio.StreamAudioSource { *; }
-keep class com.ryanheise.just_audio.StreamAudioSource$** { *; }
-keep class com.ryanheise.just_audio.LockCachingAudioSource { *; }
-keep class com.ryanheise.just_audio.ProgressiveAudioSource { *; }
-keepclassmembers class com.ryanheise.just_audio.*AudioSource { *; }

# Audio player listeners and callbacks
-keep interface com.ryanheise.just_audio.AudioPlayer$** { *; }
-keepclassmembers interface com.ryanheise.just_audio.AudioPlayer$** { *; }

# Method channel handlers for audio player
-keep class com.ryanheise.just_audio.MainMethodCallHandler { *; }
-keep class com.ryanheise.just_audio.AudioPlayer$** { *; }
-keepclassmembers class com.ryanheise.just_audio.MainMethodCallHandler { *; }

# Audio Session (CRITICAL for audio focus and routing)
-keep class com.ryanheise.audio_session.** { *; }
-keepclassmembers class com.ryanheise.audio_session.** { *; }
-keep class com.ryanheise.audio_session.AudioSession { *; }
-keep class com.ryanheise.audio_session.AudioSession$** { *; }
-keepclassmembers class com.ryanheise.audio_session.AudioSession { *; }

# RxDart (used by just_audio for streaming)
-keep class io.reactivex.rxjava3.** { *; }
-dontwarn io.reactivex.rxjava3.** 