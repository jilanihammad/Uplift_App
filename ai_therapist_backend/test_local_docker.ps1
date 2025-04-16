# PowerShell script for testing AI Therapist Backend locally in Docker
# This script is for Windows environments

# Stop any running containers with the same name
Write-Host "Stopping any existing containers..." -ForegroundColor Yellow
docker stop ai-therapist-backend 2>$null
docker rm ai-therapist-backend 2>$null

# Kill any process using port 8080
$process = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess
if ($process) {
    Write-Host "Killing process using port 8080..." -ForegroundColor Yellow
    Stop-Process -Id $process -Force
}

# Build the Docker image
Write-Host "Building Docker image..." -ForegroundColor Yellow
docker build -t ai-therapist-backend:local -f Dockerfile.cloudrun .

# Run the container
Write-Host "Running container on port 8080..." -ForegroundColor Green
docker run --name ai-therapist-backend -p 8080:8080 -e PORT=8080 -e APP_ENV=production ai-therapist-backend:local

# Note: The container will run in the foreground. Press Ctrl+C to stop it.
# To view logs: docker logs ai-therapist-backend
# To stop: docker stop ai-therapist-backend

# Kill all Python processes
Stop-Process -Name python -Force

# Try running on a different port (8080)
cd ai_therapist_backend
python -m uvicorn app.main:app --host 0.0.0.0 --port 8080 