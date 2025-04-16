# PowerShell script to run the AI Therapist Backend locally
# This avoids Docker issues and runs directly with Python

Write-Host "Starting AI Therapist Backend locally..." -ForegroundColor Green

# Set environment variables for development
$env:APP_ENV = "local"
$env:PORT = "9000"

# Kill all Python processes
Stop-Process -Name python -Force -ErrorAction SilentlyContinue

# Run the backend
Write-Host "Running backend on http://localhost:9000" -ForegroundColor Green
cd ai_therapist_backend
python -m uvicorn app.main:app --host 0.0.0.0 --port 9000