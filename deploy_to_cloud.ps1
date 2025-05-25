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

# Add a timestamp to force rebuild without cache
$TIMESTAMP = Get-Date -Format "yyyyMMddHHmmss"
$BUILD_TAG = "$SERVICE_NAME-$TIMESTAMP"

# Read API keys from .env only, do not prompt
$ENV_FILE_PATH = "ai_therapist_backend\.env"
$openai_api_key = $null
$groq_api_key = $null
$google_api_key = $null
if (Test-Path $ENV_FILE_PATH) {
    $envLines = Get-Content $ENV_FILE_PATH
    foreach ($line in $envLines) {
        if ($line -match '^OPENAI_API_KEY=(.*)') { $openai_api_key = $Matches[1].Trim() }
        if ($line -match '^GROQ_API_KEY=(.*)') { $groq_api_key = $Matches[1].Trim() }
        if ($line -match '^GOOGLE_API_KEY=(.*)') { $google_api_key = $Matches[1].Trim() }
    }
}
if (-not $openai_api_key) {
    Write-Host "Error: OPENAI_API_KEY not found in $ENV_FILE_PATH. Please add it and try again." -ForegroundColor Red
    exit 1
}
if (-not $groq_api_key) {
    Write-Host "Error: GROQ_API_KEY not found in $ENV_FILE_PATH. Please add it and try again." -ForegroundColor Red
    exit 1
}
if (-not $google_api_key) {
    Write-Host "Error: GOOGLE_API_KEY not found in $ENV_FILE_PATH. Please add it and try again." -ForegroundColor Red
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

# Install aiofiles locally first to verify it works
Write-Host "Installing aiofiles locally to verify it works..." -ForegroundColor Yellow
pip install aiofiles

# Create a temporary deployment directory
$TEMP_DIR = "deploy_temp"
if (Test-Path $TEMP_DIR) {
    Remove-Item -Recurse -Force $TEMP_DIR
}
New-Item -ItemType Directory -Path $TEMP_DIR | Out-Null
Write-Host "Created temporary deployment directory." -ForegroundColor Green

# Copy necessary files to deployment directory - use correct paths to ai_therapist_backend
Write-Host "Copying files to deployment directory..." -ForegroundColor Yellow
Copy-Item -Path "ai_therapist_backend\app" -Destination "$TEMP_DIR\app" -Recurse
Copy-Item -Path "ai_therapist_backend\alembic" -Destination "$TEMP_DIR\alembic" -Recurse
Copy-Item -Path "ai_therapist_backend\alembic.ini" -Destination "$TEMP_DIR\alembic.ini"
Copy-Item -Path "ai_therapist_backend\main.py" -Destination "$TEMP_DIR\main.py"
Copy-Item -Path "ai_therapist_backend\requirements.txt" -Destination "$TEMP_DIR\requirements.txt"

# Check if .env exists and copy it; if not, create a basic one
$ENV_FILE_PATH = "ai_therapist_backend\.env"
if (Test-Path $ENV_FILE_PATH) {
    Write-Host "Copying existing .env file..." -ForegroundColor Green
    Copy-Item -Path $ENV_FILE_PATH -Destination "$TEMP_DIR\.env"
} else {
    Write-Host "Creating default .env file for deployment..." -ForegroundColor Yellow
    $envContent = @"
# Environment configuration
ENVIRONMENT=production
GOOGLE_CLOUD=1
DATABASE_URL=sqlite:///./app.db
OPENAI_API_KEY=${openai_api_key}
DEBUG=0
"@
    Set-Content -Path "$TEMP_DIR\.env" -Value $envContent
    Write-Host "Created default .env file" -ForegroundColor Green
}

# Create Dockerfile
Write-Host "Creating Dockerfile for deployment..." -ForegroundColor Yellow
$dockerFileContent = @"
FROM python:3.10-slim

WORKDIR /app

# Add build timestamp as an argument to force rebuild without cache
ENV BUILD_TIMESTAMP=$TIMESTAMP

# Install dependencies with --no-cache-dir to avoid cache issues
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Explicitly install aiofiles - critical for voice endpoints
RUN pip install --no-cache-dir aiofiles

# Copy application code
COPY . .

# Create audio directories with proper permissions
RUN mkdir -p /app/static/audio /tmp/static/audio
RUN chmod -R 777 /app/static /tmp/static

# Create error file if needed
RUN echo "Audio error" > /app/static/audio/error.mp3
RUN echo "Audio error" > /tmp/static/audio/error.mp3
RUN chmod 777 /app/static/audio/error.mp3 /tmp/static/audio/error.mp3

# Create SQLite database directory with proper permissions
RUN mkdir -p /app/data
RUN touch /app/data/app.db
RUN chmod 777 /app/data/app.db

# Environment variables
ENV PORT=8080
ENV ENVIRONMENT=production
ENV GOOGLE_CLOUD=1
ENV DATABASE_URL=sqlite:///./data/app.db
ENV OPENAI_API_KEY=$openai_api_key
ENV GROQ_API_KEY=$groq_api_key
ENV GOOGLE_API_KEY=$google_api_key
ENV PYTHONUNBUFFERED=1
ENV USE_GROQ=0

# Force the application to run on port 8080 for Cloud Run
CMD uvicorn app.main:app --host 0.0.0.0 --port 8080
"@

Set-Content -Path "$TEMP_DIR\Dockerfile" -Value $dockerFileContent

# Display the deployment directory contents for verification
Write-Host "Deployment directory contents:" -ForegroundColor Yellow
Get-ChildItem -Path $TEMP_DIR -Recurse | Select-Object -First 20

# Deploy to Cloud Run with a unique tag to avoid cache issues
Write-Host "Deploying to Google Cloud Run with a fresh build..." -ForegroundColor Yellow
$deployCmd = @(
    "gcloud builds submit $TEMP_DIR",
    "--tag=gcr.io/$PROJECT_ID/$BUILD_TAG"
)

# Execute the build command
Invoke-Expression ($deployCmd -join " ")
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Building the container image failed." -ForegroundColor Red
    exit 1
}

# Deploy the built image
$deployCmd = @(
    "gcloud run deploy $SERVICE_NAME",
    "--image=gcr.io/$PROJECT_ID/$BUILD_TAG",
    "--platform=managed",
    "--region=$REGION",
    "--min-instances=$MIN_INSTANCES",
    "--max-instances=$MAX_INSTANCES",
    "--memory=2Gi",
    "--cpu=2",
    "--timeout=$TIMEOUT",
    "--concurrency=80",
    "--allow-unauthenticated"
)

# Execute the deployment command
Invoke-Expression ($deployCmd -join " ")
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Deployment to Cloud Run failed." -ForegroundColor Red
    exit 1
}

# Get the service URL
Write-Host "Getting service URL..." -ForegroundColor Yellow
$serviceUrl = gcloud run services describe $SERVICE_NAME --platform=managed --region=$REGION --format="value(status.url)"

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "Service deployed successfully at: $serviceUrl" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan 