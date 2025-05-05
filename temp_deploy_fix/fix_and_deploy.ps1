# Fix Session Endpoint and Deploy Script
Write-Host "===== AI Therapist Backend Fix and Deploy Tool =====" -ForegroundColor Cyan
Write-Host "This script will fix the session endpoint and deploy to Google Cloud Run" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Ensure Python is available
try {
    python --version
} catch {
    Write-Host "Error: Python is not available in the PATH." -ForegroundColor Red
    Write-Host "Please ensure Python is installed and in your PATH." -ForegroundColor Red
    exit 1
}

# Fix the session endpoint
Write-Host "Fixing the session endpoint code..." -ForegroundColor Yellow
python temp_deploy_fix/fix_sessions.py ai_therapist_backend/app/main.py

# Check if fix was successful
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to fix the session endpoint code." -ForegroundColor Red
    exit 1
}

# Run the deployment script
Write-Host "Running deployment script..." -ForegroundColor Yellow
./deploy_to_cloud.ps1

# Check if deployment was successful
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Deployment to Cloud Run failed." -ForegroundColor Red
    exit 1
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Fix and deployment complete!" -ForegroundColor Green
Write-Host "Your backend should now save sessions to the database." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan 