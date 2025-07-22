#!/bin/bash
# Build script for Google Play Console Internal Testing
# Creates a signed APK ready for upload

echo "🚀 Building AI Therapist App for Google Play Internal Testing"
echo "============================================================="

# Navigate to Flutter project
cd "$(dirname "$0")/.."

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter and add it to PATH"
    exit 1
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean
flutter pub get

# Check if android/key.properties exists (needed for signing)
if [ ! -f "android/key.properties" ]; then
    echo "⚠️  Warning: android/key.properties not found"
    echo "   You'll need to set up app signing for Play Store upload"
    echo "   For now, building with debug key..."
    
    # Build debug APK (can be uploaded to internal testing)
    echo "🔨 Building debug APK..."
    flutter build apk --debug
    
    echo ""
    echo "✅ Debug APK built successfully!"
    echo "📁 Location: build/app/outputs/flutter-apk/app-debug.apk"
    echo ""
    echo "⚠️  Note: Debug APKs work for internal testing but you'll need"
    echo "   to set up proper app signing for production releases."
    
else
    echo "🔨 Building release APK with signing..."
    flutter build apk --release
    
    echo ""
    echo "✅ Release APK built successfully!"
    echo "📁 Location: build/app/outputs/flutter-apk/app-release.apk"
fi

echo ""
echo "📋 Next Steps:"
echo "1. Go to https://play.google.com/console"
echo "2. Create new app (if not done already)"
echo "3. Go to Release > Testing > Internal testing"
echo "4. Create new release and upload the APK"
echo "5. Add testers and test your subscription flow!"

echo ""
echo "💡 Tip: Use 'flutter build appbundle --release' for production"
echo "   App Bundles are preferred over APKs for Play Store"