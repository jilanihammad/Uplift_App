# Build script for AI Therapist App release APK
Write-Host "Building AI Therapist App release APK..." -ForegroundColor Green

# Configuration
$OUTPUT_DIR = "C:\Releases"
$VERSION = "1.0.0"
$APK_NAME = "ai_therapist_app_v$VERSION.apk"
$BUILD_PATH = "build\app\outputs\flutter-apk\app-release.apk"

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $OUTPUT_DIR)) {
    Write-Host "Creating output directory: $OUTPUT_DIR" -ForegroundColor Yellow
    New-Item -Path $OUTPUT_DIR -ItemType Directory
}

# Clean previous builds
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter clean failed." -ForegroundColor Red
    exit 1
}

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter pub get failed." -ForegroundColor Red
    exit 1
}

# Build the release APK
Write-Host "Building release APK..." -ForegroundColor Yellow
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter build failed." -ForegroundColor Red
    exit 1
}

# Copy the APK to the output directory
Write-Host "Copying APK to output directory..." -ForegroundColor Yellow
Copy-Item -Path $BUILD_PATH -Destination "$OUTPUT_DIR\$APK_NAME"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to copy APK." -ForegroundColor Red
    exit 1
}

Write-Host "Build and copy completed successfully!" -ForegroundColor Green
Write-Host "APK location: $OUTPUT_DIR\$APK_NAME" -ForegroundColor Cyan 