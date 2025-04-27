# AI Therapist Backend - Google Cloud Run Deployment Script (No Docker Desktop required)
Write-Host "===== AI Therapist Backend Deployment Tool =====" -ForegroundColor Cyan
Write-Host "This script will deploy your backend to Google Cloud Run using Cloud Build" -ForegroundColor Cyan
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

# Check for environment files
if (-not (Test-Path -Path ".env")) {
    Write-Host "Error: .env file is missing." -ForegroundColor Red
    exit 1
}

# Create a temporary deployment directory
$TEMP_DIR = "deploy_temp"
if (Test-Path $TEMP_DIR) {
    Remove-Item -Recurse -Force $TEMP_DIR
}
New-Item -ItemType Directory -Path $TEMP_DIR | Out-Null

# Copy necessary files to deployment directory
Write-Host "Copying files to deployment directory..." -ForegroundColor Yellow
Copy-Item -Path "app" -Destination "$TEMP_DIR/app" -Recurse
Copy-Item -Path "main.py" -Destination "$TEMP_DIR/main.py"
Copy-Item -Path "requirements.txt" -Destination "$TEMP_DIR/requirements.txt"
Copy-Item -Path "Dockerfile.cloudrun" -Destination "$TEMP_DIR/Dockerfile"
Copy-Item -Path ".env" -Destination "$TEMP_DIR/.env"
Copy-Item -Path "alembic" -Destination "$TEMP_DIR/alembic" -Recurse
Copy-Item -Path "alembic.ini" -Destination "$TEMP_DIR/alembic.ini"

# Change to the deployment directory
Push-Location $TEMP_DIR

# Submit the build to Cloud Build
Write-Host "Submitting build to Cloud Build..." -ForegroundColor Yellow
gcloud builds submit --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" .

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host "Error: Cloud Build failed." -ForegroundColor Red
    exit 1
}

# Return to the original directory
Pop-Location

# Extract key environment variables from .env file
Write-Host "Preparing environment variables..." -ForegroundColor Yellow
$envFile = Get-Content .env

# Rather than directly passing all env vars, let's extract the ones we know are critical
$groqApiKey = ($envFile | Where-Object { $_ -match 'GROQ_API_KEY=(.*)' } | ForEach-Object { $matches[1] }).Trim('"''')
$groqTtsModelId = ($envFile | Where-Object { $_ -match 'GROQ_TTS_MODEL_ID=(.*)' } | ForEach-Object { $matches[1] }).Trim('"''')
$groqTranscriptionModelId = ($envFile | Where-Object { $_ -match 'GROQ_TRANSCRIPTION_MODEL_ID=(.*)' } | ForEach-Object { $matches[1] }).Trim('"''')
$groqLlmModelId = ($envFile | Where-Object { $_ -match 'GROQ_LLM_MODEL_ID=(.*)' } | ForEach-Object { $matches[1] }).Trim('"''')
$secretKey = ($envFile | Where-Object { $_ -match 'SECRET_KEY=(.*)' } | ForEach-Object { $matches[1] }).Trim('"''')

# Build the environment variables string
$envVars = "--set-env-vars=ENVIRONMENT=production,GROQ_API_KEY=$groqApiKey,GROQ_API_BASE_URL=https://api.groq.com/openai/v1,GROQ_LLM_MODEL_ID=$groqLlmModelId,GROQ_TTS_MODEL_ID=$groqTtsModelId,GROQ_TRANSCRIPTION_MODEL_ID=$groqTranscriptionModelId,SECRET_KEY=$secretKey"

# Deploy to Cloud Run
Write-Host "Deploying to Google Cloud Run..." -ForegroundColor Yellow
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
    "--allow-unauthenticated",
    $envVars
)

# Execute the deployment command
Invoke-Expression ($deployCmd -join " ")

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Deployment to Cloud Run failed." -ForegroundColor Red
    exit 1
}

# Clean up temporary deployment directory
if (Test-Path $TEMP_DIR) {
    Remove-Item -Recurse -Force $TEMP_DIR
    Write-Host "Cleaned up temporary deployment directory." -ForegroundColor Green
}

# Get the service URL
Write-Host "Getting service URL..." -ForegroundColor Yellow
$serviceUrl = gcloud run services describe $SERVICE_NAME --platform=managed --region=$REGION --format="value(status.url)"

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "Service deployed successfully at: $serviceUrl" -ForegroundColor Green
Write-Host "App API endpoint: $serviceUrl/api/v1" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# Verify the deployment with a simple test
Write-Host "Testing the deployment..." -ForegroundColor Yellow
$testUrl = "$serviceUrl/api/v1/llm/status"
try {
    $response = Invoke-WebRequest -Uri $testUrl -Method GET
    if ($response.StatusCode -eq 200) {
        Write-Host "Backend API is responding correctly!" -ForegroundColor Green
    } else {
        Write-Host "Backend API responded with status code: $($response.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Warning: Could not verify deployment. Error: $_" -ForegroundColor Yellow
}

Write-Host "You can now use this backend with your mobile app!" -ForegroundColor Cyan 