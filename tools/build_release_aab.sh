#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT/ai_therapist_app"

flutter clean
flutter pub get
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm,android-arm64,android-x64

echo "\nArtifacts:"
ls -1 build/app/outputs/bundle/release

echo "\nRemember to upload build/symbols to Crashlytics before shipping."
