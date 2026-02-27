#!/bin/bash

# AI Therapist Backend - Google Cloud Run Deployment Script
echo "===== AI Therapist Backend Deployment Tool ====="
echo "This script will deploy your backend to Google Cloud Run"
echo "===================================================="

# Configuration
PROJECT_ID="upliftapp-cd86e"
SERVICE_NAME="ai-therapist-backend"
REGION="us-central1"
MIN_INSTANCES=0
MAX_INSTANCES=5
MEMORY="512Mi"
CPU="1"
TIMEOUT="300s"
CONCURRENCY=80
PORT=8000  # Cloud Run will use this port

# Add a timestamp to force rebuild without cache
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BUILD_TAG="$SERVICE_NAME-$TIMESTAMP"

# ===== HARDCODED API KEYS =====
# Replace these with your actual API keys:
openai_api_key=REDACTED_OPENAI_KEY    # Replace with your OpenAI key (starts with sk-)
google_api_key=REDACTED_GOOGLE_API_KEY   # Replace with your Google key
groq_api_key=REDACTED_GROQ_KEY         # Replace with your Groq key (starts with gsk_)

# Validate API keys are not placeholders
if [[ "$openai_api_key" == "YOUR_OPENAI_API_KEY_HERE" ]]; then
    echo "Error: Please replace 'YOUR_OPENAI_API_KEY_HERE' with your actual OpenAI API key"
    exit 1
fi

if [[ "$google_api_key" == "YOUR_GOOGLE_API_KEY_HERE" ]]; then
    echo "Error: Please replace 'YOUR_GOOGLE_API_KEY_HERE' with your actual Google API key"
    exit 1
fi

if [[ "$groq_api_key" == "YOUR_GROQ_API_KEY_HERE" ]]; then
    echo "Error: Please replace 'YOUR_GROQ_API_KEY_HERE' with your actual Groq API key"
    exit 1
fi

echo "Using hardcoded API keys for deployment..."

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

# Skip local aiofiles install - it will be handled in Docker container
echo "Skipping local aiofiles install (will be installed in container)..."

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
cp -r "ai_therapist_backend/scripts" "$TEMP_DIR/"
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
GROQ_API_KEY=${groq_api_key}
DEBUG=0
EOF
    echo "Created default .env file"
fi

# Create Dockerfile
echo "Creating Dockerfile for deployment..."
cat > "$TEMP_DIR/Dockerfile" << EOF
FROM python:3.11-slim

WORKDIR /app

# Add build timestamp as an argument to force rebuild without cache
ENV BUILD_TIMESTAMP=$TIMESTAMP

# Install system dependencies including FFmpeg for OPUS audio conversion
RUN apt-get update && apt-get install -y \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies with deterministic approach
COPY requirements.txt .

# Install pipdeptree for dependency inspection
RUN pip install --no-cache-dir pipdeptree

# Install all dependencies EXCEPT OpenAI first (langchain might try to downgrade it)
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir --upgrade google-genai==1.46.0

# Force reinstall OpenAI 1.95.0 AFTER other packages to override any downgrades
RUN pip install --no-cache-dir --force-reinstall openai==1.95.0

# Verify OpenAI version is correct and show dependency tree
RUN python -c "import openai; print(f'OpenAI SDK version: {openai.__version__}'); assert openai.__version__ == '1.95.0', f'Wrong OpenAI version: {openai.__version__}'" && \
    echo "=== OpenAI dependency tree ===" && \
    pipdeptree -p openai

# Explicitly install aiofiles - critical for voice endpoints
RUN pip install --no-cache-dir aiofiles

# Final verification with detailed logging
RUN python -c "import openai, sys; print(f'FINAL CHECK - OpenAI {openai.__version__} from {openai.__file__}'); sys.exit(0 if openai.__version__ >= '1.85.0' else 1)"

# Copy application code
COPY . .

# Create audio directories with proper permissions
RUN mkdir -p /app/static/audio /tmp/static/audio
RUN chmod -R 777 /app/static /tmp/static

# Create error file if needed
RUN echo "Audio error" > /app/static/audio/error.mp3
RUN echo "Audio error" > /tmp/static/audio/error.mp3
RUN chmod 777 /app/static/audio/error.mp3 /tmp/static/audio/error.mp3

# Copy and configure entrypoint script for migrations
COPY scripts/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Environment variables
ENV PORT=8080
ENV ENVIRONMENT=production
ENV GOOGLE_CLOUD=1
# DATABASE_URL will be set by Cloud Run environment variables
ENV OPENAI_API_KEY=$openai_api_key
ENV GOOGLE_API_KEY=$google_api_key
ENV GROQ_API_KEY=$groq_api_key
ENV OPENAI_LLM_MODEL=gpt-3.5-turbo
ENV OPENAI_TTS_MODEL=gpt-4o-mini-tts
ENV OPENAI_TTS_VOICE=sage
ENV OPENAI_TRANSCRIPTION_MODEL=whisper-1
ENV PYTHONUNBUFFERED=1
ENV USE_GROQ=0

# Run migrations and start application via entrypoint
CMD ["/app/entrypoint.sh"]
EOF

# Display the deployment directory contents for verification
echo "Deployment directory contents:"
ls -la "$TEMP_DIR" | head -20

# Deploy to Cloud Run with a unique tag to avoid cache issues
echo "Deploying to Google Cloud Run with a fresh build..."

# Execute the build command - use timestamp to force fresh build
echo "Building container image with timestamp $TIMESTAMP to force fresh build..."
if ! gcloud builds submit "$TEMP_DIR" --no-cache --tag="gcr.io/$PROJECT_ID/$BUILD_TAG"; then
    echo "Error: Building the container image failed."
    exit 1
fi

# Deploy the built image with Cloud SQL connection
echo "Deploying to Cloud Run with Cloud SQL..."
if ! gcloud run deploy "$SERVICE_NAME" \
    --image="gcr.io/$PROJECT_ID/$BUILD_TAG" \
    --platform=managed \
    --region="$REGION" \
    --min-instances="$MIN_INSTANCES" \
    --max-instances="$MAX_INSTANCES" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --cpu-throttling \
    --timeout="$TIMEOUT" \
    --concurrency=80 \
    --add-cloudsql-instances="upliftapp-cd86e:us-central1:jilaniuplift" \
    --set-env-vars="DATABASE_URL=postgresql://postgres:7860@/ai_therapist?host=/cloudsql/upliftapp-cd86e:us-central1:jilaniuplift" \
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
