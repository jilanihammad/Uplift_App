# AI Therapist Backend - Google Cloud Run Deployment Script
Write-Host "===== AI Therapist Backend Deployment Tool =====" -ForegroundColor Cyan
Write-Host "This script will deploy your backend to Google Cloud Run" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Configuration 
$PROJECT_ID = "upliftapp-cd86e"
$SERVICE_NAME = "ai-therapist-backend"
$REGION = "us-central1"
$MIN_INSTANCES = 1
$MAX_INSTANCES = 5
$MEMORY = "1Gi"
$CPU = "1"
$TIMEOUT = "300s" 
$CONCURRENCY = 80
$PORT = 8000  # Cloud Run will use this port

# Ask for the OpenAI API key
Write-Host "Please enter your OpenAI API key (starts with 'sk-'): " -ForegroundColor Yellow -NoNewline
$openai_api_key = Read-Host

# Validate the key format
if (-not $openai_api_key.StartsWith("sk-")) {
    Write-Host "Error: OpenAI API key should start with 'sk-'" -ForegroundColor Red
    exit 1
}

# Check if gcloud is installed and user is authenticated
try {
    $gcpProject = gcloud config get-value project
    if ($gcpProject -ne $PROJECT_ID) {
        Write-Host "Setting GCP project to $PROJECT_ID..." -ForegroundColor Yellow
        gcloud config set project $PROJECT_ID
    }
} catch {
    Write-Host "Error: gcloud CLI not found or not authenticated." -ForegroundColor Red
    Write-Host "Please install gcloud and run 'gcloud auth login' first." -ForegroundColor Red
    exit 1
}

# Create a temporary deployment directory
$TEMP_DIR = "deploy_temp"
if (Test-Path $TEMP_DIR) {
    Remove-Item -Recurse -Force $TEMP_DIR
}
New-Item -ItemType Directory -Path $TEMP_DIR | Out-Null
Write-Host "Created temporary deployment directory." -ForegroundColor Green

# Copy necessary files to deployment directory
Write-Host "Copying files to deployment directory..." -ForegroundColor Yellow
Copy-Item -Path "app" -Destination "$TEMP_DIR\app" -Recurse
Copy-Item -Path "alembic" -Destination "$TEMP_DIR\alembic" -Recurse
Copy-Item -Path "alembic.ini" -Destination "$TEMP_DIR\alembic.ini"
Copy-Item -Path "main.py" -Destination "$TEMP_DIR\main.py"
Copy-Item -Path ".env" -Destination "$TEMP_DIR\.env"
Copy-Item -Path "requirements.txt" -Destination "$TEMP_DIR\requirements.txt"

# Create Dockerfile
Write-Host "Creating Dockerfile for deployment..." -ForegroundColor Yellow
$dockerFileContent = @"
FROM python:3.10-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Environment variables
ENV PORT=8080
ENV ENVIRONMENT=production
ENV GOOGLE_CLOUD=1
ENV OPENAI_API_KEY=$openai_api_key
ENV OPENAI_LLM_MODEL=gpt-3.5-turbo
ENV OPENAI_TTS_MODEL=gpt-4o-mini-tts
ENV OPENAI_TTS_VOICE=sage
ENV OPENAI_TRANSCRIPTION_MODEL=whisper-1
ENV PYTHONUNBUFFERED=1
ENV USE_GROQ=0

# Force the application to run on port 8080 for Cloud Run
CMD uvicorn app.main:app --host 0.0.0.0 --port 8080
"@

Set-Content -Path "$TEMP_DIR\Dockerfile" -Value $dockerFileContent

# Deploy to Cloud Run
Write-Host "Deploying to Google Cloud Run..." -ForegroundColor Yellow
cd ..
$deployCmd = @(
    "gcloud run deploy $SERVICE_NAME",
    "--image=gcr.io/$PROJECT_ID/$SERVICE_NAME",
    "--platform=managed",
    "--region=$REGION",
    "--min-instances=$MIN_INSTANCES",
    "--max-instances=$MAX_INSTANCES",
    "--memory=$MEMORY",
    "--cpu=$CPU",
    "--timeout=$TIMEOUT",
    "--concurrency=$CONCURRENCY",
    "--allow-unauthenticated"
)

# Execute the deployment command
Invoke-Expression ($deployCmd -join " ")
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Deployment to Cloud Run failed." -ForegroundColor Red
    exit 1
} 