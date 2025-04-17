# SecurityFix: Remove Groq API key from frontend app
Write-Host "Updating app security configuration..." -ForegroundColor Cyan

# Define output paths
$OUTPUT_DIR = "C:\Releases"
$APK_NAME = "ai_therapist_app_secure_v1.0.0.apk"

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
    Write-Host "Created output directory at $OUTPUT_DIR" -ForegroundColor Green
}

# 1. Make a backup of the .env file
Write-Host "Making a backup of the .env file..." -ForegroundColor Yellow
Copy-Item -Path ".env" -Destination ".env.backup"

# 2. Update the .env file to remove Groq API key and use cloud endpoints
$envContent = @"
# API Configurations
# IMPORTANT: API keys should never be stored in frontend code
# The Groq API key has been removed for security - all API calls should go through the backend

# Base Endpoints
GROQ_API_BASE_URL=https://api.groq.com/openai/v1
LLM_API_ENDPOINT=https://ai-therapist-backend-fuukqlcsha-uc.a.run.app
VOICE_MODEL_ENDPOINT=https://ai-therapist-backend-fuukqlcsha-uc.a.run.app

# LLM Model
LLM_MODEL_ENDPOINT=https://api.groq.com/openai/v1/models
LLM_MODEL_ID=meta-llama/llama-4-scout-17b-16e-instruct

# Voice TTS Model
TTS_MODEL_ENDPOINT=https://api.groq.com/openai/v1/audio/speech
TTS_MODEL_ID=playai-tts

# Transcription Model
TRANSCRIPTION_ENDPOINT=https://api.groq.com/openai/v1/audio/transcriptions
TRANSCRIPTION_MODEL_ID=whisper-large-v3-turbo

# Environment settings
IS_PRODUCTION=true
"@

# Write the updated .env content
Set-Content -Path ".env" -Value $envContent
Write-Host "Updated .env file to remove API keys" -ForegroundColor Green

# 3. Update GroqService to remove API key handling
$groqServicePath = "lib/services/groq_service.dart"
Write-Host "Modifying GroqService to remove API key..." -ForegroundColor Yellow

# Make a backup of the original file
Copy-Item -Path $groqServicePath -Destination "$groqServicePath.backup"

# Get the content of the file
$groqServiceContent = Get-Content -Path $groqServicePath -Raw

# Replace references to _apiKey in the constructor and class variables
$groqServiceContent = $groqServiceContent -replace "late String _apiKey;", ""
$groqServiceContent = $groqServiceContent -replace "_apiKey = config.groqApiKey;", ""

# Remove API key debug printing
$groqServiceContent = $groqServiceContent -replace "print\('GroqService: Using API key: [\$].*'\);", ""

# Remove Authorization headers from API calls
$groqServiceContent = $groqServiceContent -replace "customHeaders: \{[\r\n\s]*'Authorization': 'Bearer \$_apiKey',[\r\n\s]*\}", ""
$groqServiceContent = $groqServiceContent -replace ", customHeaders: \{[\r\n\s]*'Authorization': 'Bearer \$_apiKey',[\r\n\s]*\}", ""

# Write the updated file
Set-Content -Path $groqServicePath -Value $groqServiceContent
Write-Host "Updated GroqService to remove API key handling" -ForegroundColor Green

# 4. Clear cached preferences that might contain API keys
Write-Host "Cleaning previous builds and preferences..." -ForegroundColor Yellow
flutter clean

# 5. Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# 6. Build the release APK
Write-Host "Building release APK with security updates..." -ForegroundColor Yellow
flutter build apk --release

# 7. Copy the APK to the output directory
$BUILD_SUCCESS = $?
if ($BUILD_SUCCESS) {
    Copy-Item -Path "build\app\outputs\flutter-apk\app-release.apk" -Destination "$OUTPUT_DIR\$APK_NAME"
    Write-Host "`nBuild successful!" -ForegroundColor Green
    Write-Host "APK saved to: $OUTPUT_DIR\$APK_NAME" -ForegroundColor Green
    
    Write-Host "`nThis APK is configured to use:" -ForegroundColor Cyan
    Write-Host "- Backend API: https://ai-therapist-backend-fuukqlcsha-uc.a.run.app" -ForegroundColor Cyan
    Write-Host "- Firebase: upliftapp-cd86e" -ForegroundColor Cyan
    Write-Host "- Security: API keys removed from frontend" -ForegroundColor Green
} else {
    Write-Host "`nBuild failed!" -ForegroundColor Red
}

# Restore the backups
Write-Host "`nRestoring backups..." -ForegroundColor Yellow
Copy-Item -Path ".env.backup" -Destination ".env"
Remove-Item -Path ".env.backup"
Copy-Item -Path "$groqServicePath.backup" -Destination $groqServicePath
Remove-Item -Path "$groqServicePath.backup"
Write-Host "Backups restored" -ForegroundColor Green 