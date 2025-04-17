# PowerShell script to build a debug APK for the AI Therapist App

# Define the output directory and APK name
$outputDir = "C:\Releases"
$apkName = "ai_therapist_app_debug.apk"

# Check if the output directory exists, if not create it
if (!(Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir
}

# Clean previous builds
Write-Host "Cleaning previous builds..." -ForegroundColor Cyan
flutter clean

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Cyan
flutter pub get

# Build debug APK
Write-Host "Building debug APK for testing Firebase..." -ForegroundColor Cyan
flutter build apk --debug

# Check if the build was successful
if ($LASTEXITCODE -eq 0) {
    # Copy the APK to the output directory
    Copy-Item -Path "build\app\outputs\flutter-apk\app-debug.apk" -Destination "$outputDir\$apkName" -Force
    
    Write-Host "`nBuild successful!" -ForegroundColor Green
    Write-Host "APK saved to: $outputDir\$apkName" -ForegroundColor Green
    
    Write-Host "`nThis APK includes Firebase debugging tools to help diagnose connectivity issues." -ForegroundColor Yellow
    Write-Host "- Backend API: https://ai-therapist-backend-fuukqlcsha-uc.a.run.app" -ForegroundColor Yellow
    Write-Host "- Firebase: upliftapp-cd86e" -ForegroundColor Yellow
    
    # Installation instructions
    Write-Host "`nTo install on your device:" -ForegroundColor Cyan
    Write-Host "1. Connect your device via USB" -ForegroundColor Cyan
    Write-Host "2. Enable USB debugging on your device" -ForegroundColor Cyan
    Write-Host "3. Run: adb install -r $outputDir\$apkName" -ForegroundColor Cyan
} else {
    Write-Host "`nBuild failed!" -ForegroundColor Red
} 