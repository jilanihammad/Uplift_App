# PowerShell script to run the Docker container locally for testing

# Stop and remove existing container if it exists
docker stop ai-therapist-backend 2>$null
docker rm ai-therapist-backend 2>$null

# Clear Docker cache if needed
# docker system prune -f

# Run the container with required environment variables
docker run -d --name ai-therapist-backend `
  -p 8000:8000 `
  -e PORT=8000 `
  -e APP_ENV=development `
  -e DEBUG=1 `
  -e POSTGRES_SERVER=localhost `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=7860 `
  -e POSTGRES_DB=ai_therapist `
  -e SECRET_KEY=testsecretkey123 `
  -e GROQ_API_KEY="$env:GROQ_API_KEY" `
  -e OPENAI_API_KEY="$env:OPENAI_API_KEY" `
  -e BACKEND_CORS_ORIGINS=* `
  -e GCS_BUCKET_NAME=ai-therapist-audio-files `
  ai-therapist-backend:local

Write-Host "Container started. Access the API at: http://localhost:8000/api/v1/health" 