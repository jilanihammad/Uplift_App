# Simple deployment script for the test app
Write-Host "Deploying test app to Cloud Run..."
gcloud run deploy ai-therapist-test `
  --source . `
  --platform managed `
  --region us-central1 `
  --allow-unauthenticated 