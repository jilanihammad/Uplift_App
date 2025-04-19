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