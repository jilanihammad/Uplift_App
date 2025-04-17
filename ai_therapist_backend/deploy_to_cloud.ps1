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

# Force the application to run on port 8080 for Cloud Run
CMD uvicorn app.main:app --host 0.0.0.0 --port 8080
"@

Set-Content -Path "$TEMP_DIR\Dockerfile" -Value $dockerFileContent

# Build and tag the Docker image
Write-Host "Building Docker image..." -ForegroundColor Yellow
cd $TEMP_DIR
docker build -t "gcr.io/$PROJECT_ID/$SERVICE_NAME" .
if ($LASTEXITCODE -ne 0) {
    cd ..
    Write-Host "Error: Docker build failed." -ForegroundColor Red
    exit 1
}

# Push the Docker image to Google Container Registry
Write-Host "Pushing Docker image to Google Container Registry..." -ForegroundColor Yellow
docker push "gcr.io/$PROJECT_ID/$SERVICE_NAME"
if ($LASTEXITCODE -ne 0) {
    cd ..
    Write-Host "Error: Failed to push Docker image to GCR." -ForegroundColor Red
    exit 1
}

# Load environment variables from .env file
$envVars = @()
foreach ($line in Get-Content .env) {
    if ($line -match '^([^=]+)=(.*)$') {
        $key = $matches[1]
        $value = $matches[2]
        # Skip comments and empty lines
        if (-not $key.StartsWith("#") -and $key.Trim() -ne "") {
            # Remove quotes if present
            $value = $value.Trim('"''')
            $envVars += "--set-env-vars=$key=`"$value`""
        }
    }
}

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

# Add all environment variables to the command
$deployCmd += $envVars

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