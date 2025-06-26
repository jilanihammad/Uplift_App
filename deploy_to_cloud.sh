#!/bin/bash

# AI Therapist Backend - Google Cloud Run Deployment Script
echo "===== AI Therapist Backend Deployment Tool ====="
echo "This script will deploy your backend to Google Cloud Run"
echo "===================================================="

# Configuration
PROJECT_ID="upliftapp-cd86e"
SERVICE_NAME="ai-therapist-backend"
REGION="us-central1"
MIN_INSTANCES=1
MAX_INSTANCES=5
MEMORY="1Gi"
CPU="1"
TIMEOUT="300s"
CONCURRENCY=80
PORT=8000  # Cloud Run will use this port

# Add a timestamp to force rebuild without cache
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BUILD_TAG="$SERVICE_NAME-$TIMESTAMP"

# Ask for the OpenAI API key
echo -n "Please enter your OpenAI API key (starts with 'sk-'): "
read -s openai_api_key
echo

# Validate the OpenAI key format
if [[ ! $openai_api_key == sk-* ]]; then
    echo "Error: OpenAI API key should start with 'sk-'"
    exit 1
fi

# Ask for the Google API key
echo -n "Please enter your Google API key: "
read -s google_api_key
echo

# Validate the Google key is not empty
if [[ -z "$google_api_key" ]]; then
    echo "Error: Google API key cannot be empty"
    exit 1
fi

# Check if gcloud is installed and user is authenticated
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI not found in PATH"
    echo "Please ensure Google Cloud CLI is installed and in your PATH."
    echo "Install instructions: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

gcp_project=$(gcloud config get-value project 2>/dev/null)
if [[ "$gcp_project" != "$PROJECT_ID" ]]; then
    echo "Setting GCP project to $PROJECT_ID..."
    gcloud config set project $PROJECT_ID
fi

# Install aiofiles locally first to verify it works
echo "Installing aiofiles locally to verify it works..."
pip install aiofiles

# Create a temporary deployment directory
TEMP_DIR="deploy_temp"
if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
fi
mkdir -p "$TEMP_DIR"
echo "Created temporary deployment directory."

# Copy necessary files to deployment directory - use correct paths to ai_therapist_backend
echo "Copying files to deployment directory..."
cp -r "ai_therapist_backend/app" "$TEMP_DIR/"
cp -r "ai_therapist_backend/alembic" "$TEMP_DIR/"
cp "ai_therapist_backend/alembic.ini" "$TEMP_DIR/"
cp "ai_therapist_backend/main.py" "$TEMP_DIR/"
cp "ai_therapist_backend/requirements.txt" "$TEMP_DIR/"

# Check if .env exists and copy it; if not, create a basic one
ENV_FILE_PATH="ai_therapist_backend/.env"
if [[ -f "$ENV_FILE_PATH" ]]; then
    echo "Copying existing .env file..."
    cp "$ENV_FILE_PATH" "$TEMP_DIR/.env"
else
    echo "Creating default .env file for deployment..."
    cat > "$TEMP_DIR/.env" << EOF
# Environment configuration
ENVIRONMENT=production
GOOGLE_CLOUD=1
DATABASE_URL=sqlite:///./app.db
OPENAI_API_KEY=${openai_api_key}
GOOGLE_API_KEY=${google_api_key}
DEBUG=0
EOF
    echo "Created default .env file"
fi

# Create Dockerfile
echo "Creating Dockerfile for deployment..."
cat > "$TEMP_DIR/Dockerfile" << EOF
FROM python:3.10-slim

WORKDIR /app

# Add build timestamp as an argument to force rebuild without cache
ENV BUILD_TIMESTAMP=$TIMESTAMP

# Install dependencies with --no-cache-dir to avoid cache issues
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Explicitly install aiofiles - critical for voice endpoints
RUN pip install --no-cache-dir aiofiles

# Copy application code
COPY . .

# Create audio directories with proper permissions
RUN mkdir -p /app/static/audio /tmp/static/audio
RUN chmod -R 777 /app/static /tmp/static

# Create error file if needed
RUN echo "Audio error" > /app/static/audio/error.mp3
RUN echo "Audio error" > /tmp/static/audio/error.mp3
RUN chmod 777 /app/static/audio/error.mp3 /tmp/static/audio/error.mp3

# Create SQLite database directory with proper permissions
RUN mkdir -p /app/data
RUN touch /app/data/app.db
RUN chmod 777 /app/data/app.db

# Environment variables
ENV PORT=8080
ENV ENVIRONMENT=production
ENV GOOGLE_CLOUD=1
ENV DATABASE_URL=sqlite:///./data/app.db
ENV OPENAI_API_KEY=$openai_api_key
ENV GOOGLE_API_KEY=$google_api_key
ENV OPENAI_LLM_MODEL=gpt-3.5-turbo
ENV OPENAI_TTS_MODEL=gpt-4o-mini-tts
ENV OPENAI_TTS_VOICE=sage
ENV OPENAI_TRANSCRIPTION_MODEL=whisper-1
ENV PYTHONUNBUFFERED=1
ENV USE_GROQ=0

# Force the application to run on port 8080 for Cloud Run
CMD uvicorn app.main:app --host 0.0.0.0 --port 8080
EOF

# Display the deployment directory contents for verification
echo "Deployment directory contents:"
ls -la "$TEMP_DIR" | head -20

# Deploy to Cloud Run with a unique tag to avoid cache issues
echo "Deploying to Google Cloud Run with a fresh build..."

# Execute the build command
echo "Building container image..."
if ! gcloud builds submit "$TEMP_DIR" --tag="gcr.io/$PROJECT_ID/$BUILD_TAG"; then
    echo "Error: Building the container image failed."
    exit 1
fi

# Deploy the built image
echo "Deploying to Cloud Run..."
if ! gcloud run deploy "$SERVICE_NAME" \
    --image="gcr.io/$PROJECT_ID/$BUILD_TAG" \
    --platform=managed \
    --region="$REGION" \
    --min-instances="$MIN_INSTANCES" \
    --max-instances="$MAX_INSTANCES" \
    --memory=2Gi \
    --cpu=2 \
    --timeout="$TIMEOUT" \
    --concurrency=80 \
    --allow-unauthenticated; then
    echo "Error: Deployment to Cloud Run failed."
    exit 1
fi

# Get the service URL
echo "Getting service URL..."
service_url=$(gcloud run services describe "$SERVICE_NAME" --platform=managed --region="$REGION" --format="value(status.url)")

echo "================================================="
echo "Deployment Complete!"
echo "Service deployed successfully at: $service_url"
echo "================================================="

# Clean up temporary directory
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"
echo "Cleanup complete."