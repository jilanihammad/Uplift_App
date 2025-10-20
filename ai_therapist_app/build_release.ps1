# PowerShell script to build a release APK for the AI Therapist App

Write-Host "Building Uplift Therapist App Release Version..." -ForegroundColor Green

# Define variables
$outputDir = "C:\Releases"
$apkName = "uplift_therapist_v1.0.0.apk"
$backendApi = "https://ai-therapist-backend-fuukqlcsha-uc.a.run.app"
$firebaseProject = "upliftapp-cd86e"

# Create output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
    Write-Host "Created output directory: $outputDir" -ForegroundColor Yellow
}

# Clean previous build artifacts
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
flutter clean

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# Build release APK
Write-Host "Building release APK..." -ForegroundColor Green
flutter build apk --release `
    --obfuscate `
    --split-debug-info=build/symbols `
    --target-platform android-arm,android-arm64,android-x64 `
    --dart-define=API_BASE_URL=$backendApi `
    --dart-define=FIREBASE_PROJECT=$firebaseProject

# Check if build was successful
if ($LASTEXITCODE -eq 0) {
    # Copy APK to output directory
    $sourcePath = "build\app\outputs\flutter-apk\app-release.apk"
    $destPath = Join-Path -Path $outputDir -ChildPath $apkName
    
    Copy-Item -Path $sourcePath -Destination $destPath -Force

    $symbolsSource = "build\symbols"
    if (Test-Path $symbolsSource) {
        $symbolsDest = Join-Path -Path $outputDir -ChildPath "symbols"
        if (Test-Path $symbolsDest) {
            Remove-Item -Recurse -Force $symbolsDest
        }
        Copy-Item -Path $symbolsSource -Destination $symbolsDest -Recurse -Force
        Write-Host "Debug symbols copied to: $symbolsDest" -ForegroundColor Cyan
    } else {
        Write-Host "Warning: Debug symbols directory not found." -ForegroundColor Yellow
    }
    
    Write-Host "Release build successful!" -ForegroundColor Green
    Write-Host "APK saved to: $destPath" -ForegroundColor Cyan
    Write-Host "Backend API: $backendApi" -ForegroundColor Cyan
    Write-Host "Firebase Project: $firebaseProject" -ForegroundColor Cyan
    
    # Optional: Calculate APK size
    $apkSize = (Get-Item $destPath).Length / 1MB
    Write-Host "APK Size: $($apkSize.ToString("#.##")) MB" -ForegroundColor Cyan
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
}

Write-Host "Build process completed." -ForegroundColor Green

Write-Host "`nIMPORTANT: Before installing on your device:" -ForegroundColor Magenta
Write-Host "1. Make sure your backend is running using the start_backend.ps1 script" -ForegroundColor White
Write-Host "2. Verify you've updated the IP address in api.dart with your computer's local network IP" -ForegroundColor White
Write-Host "3. Ensure your phone is connected to the same WiFi network as your computer" -ForegroundColor White 
