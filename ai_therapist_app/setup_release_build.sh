#!/bin/bash

echo "🚀 Android Release Build Setup Script"
echo "====================================="

# Set Android environment variables
export ANDROID_HOME=/home/jilani/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools/bin

echo "✅ ANDROID_HOME set to: $ANDROID_HOME"

# Step 1: Generate keystore (if it doesn't exist)
if [ ! -f "android/uplift-release-key.jks" ]; then
    echo ""
    echo "📱 Step 1: Generate Android Keystore"
    echo "======================================"
    echo "Running keytool to generate release keystore..."
    echo "You'll be prompted for:"
    echo "  - Keystore password (at least 6 characters)"
    echo "  - Key password (can be same as keystore)"
    echo "  - Your name and organization details"
    echo ""
    
    keytool -genkey -v -keystore android/uplift-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias uplift-key
    
    if [ $? -eq 0 ]; then
        echo "✅ Keystore generated successfully!"
    else
        echo "❌ Keystore generation failed. Please try again."
        exit 1
    fi
else
    echo "✅ Keystore already exists: android/uplift-release-key.jks"
fi

# Step 2: Create key.properties file
echo ""
echo "🔑 Step 2: Create key.properties file"
echo "======================================"

if [ ! -f "android/key.properties" ]; then
    echo "Please enter your keystore password:"
    read -s KEYSTORE_PASSWORD
    echo "Please enter your key password (or press Enter to use same as keystore):"
    read -s KEY_PASSWORD
    
    if [ -z "$KEY_PASSWORD" ]; then
        KEY_PASSWORD=$KEYSTORE_PASSWORD
    fi
    
    cat > android/key.properties << EOF
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=uplift-key
storeFile=uplift-release-key.jks
EOF
    
    echo "✅ key.properties file created"
else
    echo "✅ key.properties already exists"
fi

# Step 3: Build release APK
echo ""
echo "🔨 Step 3: Build Release APK"
echo "============================"
echo "Building release APK..."

flutter build apk --release

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 SUCCESS! Release APK built successfully!"
    echo "📱 APK location: build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    echo "Next steps:"
    echo "1. Test the APK on your device"
    echo "2. For Play Store: flutter build appbundle --release"
    echo "3. Keep your keystore and key.properties files safe!"
else
    echo "❌ Release build failed. Check the error messages above."
    echo ""
    echo "Common issues:"
    echo "1. Missing Android SDK cmdline-tools"
    echo "2. Android licenses not accepted"
    echo "3. Invalid keystore configuration"
fi