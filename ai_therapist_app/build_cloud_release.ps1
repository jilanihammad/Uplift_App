# PowerShell script to build a release APK for the AI Therapist App with cloud backend

# Set the output directory and file name
$outputDir = "C:\Releases"
$version = "1.0.0"
$apkName = "ai_therapist_app_cloud_v$version.apk"
$buildPath = "build\app\outputs\flutter-apk\app-release.apk"

# Create the output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
    Write-Host "Created output directory: $outputDir" -ForegroundColor Green
}

# Clean previous builds
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
flutter clean

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# Build the release APK
Write-Host "Building release APK with cloud backend..." -ForegroundColor Cyan
flutter build apk --release

# Check if build was successful
if (Test-Path $buildPath) {
    # Copy the APK to the output directory
    Copy-Item $buildPath "$outputDir\$apkName" -Force
    
    Write-Host "`nBuild successful!" -ForegroundColor Green
    Write-Host "APK saved to: $outputDir\$apkName" -ForegroundColor Green
    Write-Host "`nThis APK is configured to use:" -ForegroundColor Magenta
    Write-Host "- Backend API: https://ai-therapist-backend-fuukqlcsha-uc.a.run.app" -ForegroundColor White
    Write-Host "- Firebase: upliftapp-cd86e" -ForegroundColor White
} else {
    Write-Host "`nBuild failed! APK not found at: $buildPath" -ForegroundColor Red
} 