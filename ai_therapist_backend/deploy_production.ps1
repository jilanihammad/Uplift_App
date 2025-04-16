# Production deployment script for AI Therapist Backend
Write-Host "Deploying AI Therapist Backend to Cloud Run..." -ForegroundColor Green

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

# Check for environment variables
if (-not (Test-Path -Path ".env")) {
    Write-Host "Error: .env file is missing. Please create it with the required environment variables." -ForegroundColor Red
    exit 1
}

# Build the Docker image
Write-Host "Building Docker image..." -ForegroundColor Yellow
docker build -t gcr.io/$PROJECT_ID/$SERVICE_NAME .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker build failed." -ForegroundColor Red
    exit 1
}

# Push the Docker image to Google Container Registry
Write-Host "Pushing Docker image to Google Container Registry..." -ForegroundColor Yellow
docker push gcr.io/$PROJECT_ID/$SERVICE_NAME
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to push Docker image to GCR." -ForegroundColor Red
    exit 1
}

# Load environment variables from .env file
$envVars = @()
foreach ($line in Get-Content .env) {
    if ($line -match '^([^=]+)=(.*)$') {
        $key = $matches[1]
        $value = $matches[2]
        # Skip comments
        if (-not $key.StartsWith("#")) {
            # Ensure all values are strings by wrapping in quotes
            $value = $value.Trim('"''')
            $envVars += "--set-env-vars=$key=`"$value`""
        }
    }
}

# Deploy to Cloud Run
Write-Host "Deploying to Cloud Run..." -ForegroundColor Yellow
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

# Get the service URL
Write-Host "Getting service URL..." -ForegroundColor Yellow
$serviceUrl = gcloud run services describe $SERVICE_NAME --platform=managed --region=$REGION --format="value(status.url)"
Write-Host "Service deployed successfully at: $serviceUrl" -ForegroundColor Green

# Update the frontend configuration
Write-Host "Note: Remember to update the frontend API configuration with the new backend URL." -ForegroundColor Yellow
Write-Host "URL to use in api.dart: $serviceUrl/api/v1" -ForegroundColor Cyan

Write-Host "Deployment complete!" -ForegroundColor Green 