# Android Release Build Setup Guide

## Current Status
✅ **RNNoise duplication fixed** - Debug builds work  
✅ **TTS completely working** - Both welcome and AI responses  
❌ **Release build fails** - Missing signing configuration

## Quick Setup (Automated)

Run the setup script:
```bash
./setup_release_build.sh
```

## Manual Setup Instructions

### 1. Generate Android Keystore

```bash
cd ai_therapist_app
keytool -genkey -v -keystore android/uplift-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias uplift-key
```

**Prompts you'll see:**
- **Keystore password**: Choose strong password (min 6 chars) - **REMEMBER THIS!**
- **Key password**: Can use same as keystore password
- **Name**: "Maya Uplift" or your name
- **Organization**: Your company/organization
- **City/State/Country**: Your location

### 2. Create Key Properties File

Create `android/key.properties`:
```
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD  
keyAlias=uplift-key
storeFile=uplift-release-key.jks
```

### 3. Fix Android SDK Issues (Optional)

The missing cmdline-tools won't prevent release builds, but if you want to fix them:

#### Option A: Android Studio
1. Open Android Studio
2. Go to Tools → SDK Manager
3. Install "Android SDK Command-line Tools (latest)"

#### Option B: Manual Download
1. Download from: https://developer.android.com/studio#command-line-tools-only
2. Extract to `/home/jilani/Android/Sdk/cmdline-tools/latest/`
3. Add to PATH: `export PATH=$PATH:/home/jilani/Android/Sdk/cmdline-tools/latest/bin`

#### Accept Licenses
```bash
export ANDROID_HOME=/home/jilani/Android/Sdk
flutter doctor --android-licenses
```

### 4. Build Release APK

```bash
flutter build apk \
  --release \
  --obfuscate \
  --split-debug-info=build/symbols \
  --target-platform android-arm,android-arm64,android-x64
```

**Expected output:**
```
✓ Built build/app/outputs/flutter-apk/app-release.apk
```

🧩 **Debug symbols** are emitted to `build/symbols`. Archive this directory alongside the APK and upload to Crashlytics/Sentry for de-obfuscating stack traces.

### 5. Build App Bundle (for Play Store)

```bash
flutter build appbundle \
  --release \
  --obfuscate \
  --split-debug-info=build/symbols \
  --target-platform android-arm,android-arm64,android-x64
```

> Reuse the same `build/symbols` directory—do not delete it between APK and AAB builds.

## Security Notes

⚠️ **CRITICAL**: Keep these files safe and private:
- `android/uplift-release-key.jks` - Your signing keystore
- `android/key.properties` - Contains passwords

✅ **Already secured:**
- Both files are in `.gitignore` - won't be committed to Git
- Never share keystore passwords publicly

## Troubleshooting

### "SigningConfig release is missing required property storeFile"
- Ensure `android/key.properties` exists with correct content
- Check keystore file path is correct

### "Android license status unknown"  
- Run: `flutter doctor --android-licenses`
- Accept all license agreements

### "cmdline-tools component is missing"
- This won't prevent release builds
- Fix using Android Studio SDK Manager if desired

### Build fails with ProGuard errors
- Check `android/app/proguard-rules.pro` for conflicting rules
- Add keep rules for any libraries causing issues

## File Locations

After successful build:
- **Release APK**: `build/app/outputs/flutter-apk/app-release.apk`
- **App Bundle**: `build/app/outputs/bundle/release/app-release.aab`
- **Keystore**: `android/uplift-release-key.jks` 
- **Config**: `android/key.properties`

## Next Steps

1. **Test APK** on physical device
2. **Upload to Play Store** using app bundle
3. **Backup keystore** to secure location
4. **Document passwords** in secure password manager
