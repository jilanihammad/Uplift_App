# PowerShell script to build a debug APK for the AI Therapist App with local backend for physical devices

# Set the output directory and file name
$outputDir = "C:\Releases"
$apkName = "ai_therapist_app_local_device_debug.apk"
$buildPath = "build\app\outputs\flutter-apk\app-debug.apk"

# Get the computer's IP address
$ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Wi-Fi*" }).IPAddress
if (!$ipAddress) {
    $ipAddress = "YOUR_COMPUTER_IP"
    Write-Host "Could not automatically detect WiFi IP address." -ForegroundColor Yellow
    Write-Host "Please manually edit the ConfigService.dart file with your computer's IP address." -ForegroundColor Yellow
} else {
    Write-Host "Detected IP address: $ipAddress" -ForegroundColor Cyan
}

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

# Remind to update the ConfigService
Write-Host "`nIMPORTANT: Before building, make sure the ConfigService is configured correctly:" -ForegroundColor Magenta
Write-Host "- In services/config_service.dart, uncomment and update:" -ForegroundColor White
Write-Host "  _llmApiEndpoint = 'http://$ipAddress:8001';" -ForegroundColor White
Write-Host "`nPress Enter to continue or Ctrl+C to cancel..." -ForegroundColor Yellow
Read-Host

# Build the debug APK
Write-Host "Building debug APK with local backend for physical device..." -ForegroundColor Cyan
flutter build apk --debug

# Check if build was successful
if (Test-Path $buildPath) {
    # Copy the APK to the output directory
    Copy-Item $buildPath "$outputDir\$apkName" -Force
    
    Write-Host "`nBuild successful!" -ForegroundColor Green
    Write-Host "APK saved to: $outputDir\$apkName" -ForegroundColor Green
    Write-Host "`nThis APK is configured to use:" -ForegroundColor Magenta
    Write-Host "- Backend API: http://$ipAddress:8001" -ForegroundColor White
    Write-Host "- Make sure your backend is running on port 8001!" -ForegroundColor Yellow
    Write-Host "- Ensure your phone is on the same WiFi network as your computer" -ForegroundColor Yellow
} else {
    Write-Host "`nBuild failed! APK not found at: $buildPath" -ForegroundColor Red
} 