# Audio Optimization Deployment Script
# This script deploys the audio optimization changes to Google Cloud Run

Write-Host "=== AI Therapist Backend Audio Optimization Deployment ==="
Write-Host "This script will deploy your audio optimization changes to Google Cloud Run."
Write-Host ""

# Confirm with the user
$confirmation = Read-Host "Do you want to proceed with deployment? (y/n)"
if ($confirmation -ne 'y') {
    Write-Host "Deployment cancelled."
    exit
}

# Check if we're in the right directory
if (-not (Test-Path "app/services/openai_service.py")) {
    Write-Host "Error: Script must be run from the ai_therapist_backend directory."
    exit 1
}

# Create a timestamp for the deployment
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$deploy_dir = "deploy_temp/audio_optimizations_$timestamp"

# Create the deployment directory
New-Item -ItemType Directory -Path $deploy_dir -Force | Out-Null

try {
    Write-Host "Creating deployment package..."
    
    # Copy necessary files
    Copy-Item -Path "app" -Destination "$deploy_dir/" -Recurse
    Copy-Item -Path "main.py" -Destination "$deploy_dir/" 
    Copy-Item -Path "requirements.txt" -Destination "$deploy_dir/"
    Copy-Item -Path "Dockerfile.cloudrun" -Destination "$deploy_dir/Dockerfile"
    
    # Navigate to the deployment directory
    Push-Location $deploy_dir
    
    # Build and deploy to Google Cloud Run
    Write-Host "Building and deploying to Google Cloud Run..."
    
    # You can add your specific Google Cloud Run deployment commands here
    # For example:
    # gcloud builds submit --tag gcr.io/your-project-id/ai-therapist-backend
    # gcloud run deploy ai-therapist-backend --image gcr.io/your-project-id/ai-therapist-backend --platform managed

    # If you have an existing deployment script, you can call it here
    # For example:
    # & ../../deploy_to_cloud_run.sh
    
    Write-Host "Deployment commands would run here."
    Write-Host ""
    Write-Host "IMPORTANT: You need to customize this script with your actual deployment commands."
    Write-Host "See the ai_therapist_backend/deploy_to_cloud_run.sh or deploy_to_cloud.ps1 files for examples."
    
} finally {
    # Return to the original directory
    Pop-Location
}

Write-Host ""
Write-Host "==== Testing Audio Compression ===="
Write-Host "After deployment is complete, run the test script to verify the changes:"
Write-Host "python tests/test_audio_compression.py --url=https://your-backend-url.run.app"

Write-Host ""
Write-Host "Deployment package created at: $deploy_dir"
Write-Host "Remember to customize this script with your actual deployment commands!" 