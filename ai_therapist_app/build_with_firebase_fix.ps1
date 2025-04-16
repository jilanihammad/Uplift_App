# Build script for AI Therapist App with Firebase fixes

Write-Host "Starting build process for AI Therapist App..." -ForegroundColor Green

# Clean the project
Write-Host "Cleaning project..." -ForegroundColor Cyan
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "Clean failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Get dependencies 
Write-Host "Getting dependencies..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter pub get failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Build the app in debug mode
Write-Host "Building app in debug mode..." -ForegroundColor Cyan
flutter build apk --debug
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "App built successfully! APK is at build/app/outputs/flutter-apk/app-debug.apk" -ForegroundColor Green

# Run the app
Write-Host "Running the app..." -ForegroundColor Cyan
flutter run
if ($LASTEXITCODE -ne 0) {
    Write-Host "App run failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "Build process completed successfully!" -ForegroundColor Green 