# PowerShell script to test the app in release mode

Write-Host "==========================================="
Write-Host "Testing AI Therapist App in Release Mode"
Write-Host "==========================================="

# Clean previous builds
Write-Host "Cleaning previous builds..."
flutter clean

# Get dependencies
Write-Host "Getting dependencies..."
flutter pub get

# Run in release mode
Write-Host "Running in release mode..."
flutter run --release

Write-Host "Test complete!" 