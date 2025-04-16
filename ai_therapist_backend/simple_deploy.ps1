# Simple deployment script for Cloud Run
Write-Host "Deploying to Cloud Run..."
gcloud run deploy ai-therapist-backend `
  --source . `
  --platform managed `
  --region us-central1 `
  --allow-unauthenticated 