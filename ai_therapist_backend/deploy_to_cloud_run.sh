#!/bin/bash
# Deployment script for AI Therapist Backend to Google Cloud Run

# Exit on error
set -e

# Configuration variables - update these
PROJECT_ID="your-gcp-project-id"
SERVICE_NAME="ai-therapist-backend"
REGION="us-central1"
SECRET_NAMES=("POSTGRES_PASSWORD" "SECRET_KEY" "GROQ_API_KEY" "OPENAI_API_KEY")
DB_INSTANCE_NAME="your-postgres-instance"
DB_NAME="ai_therapist"
GCS_BUCKET_NAME="ai-therapist-audio-files"

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting deployment to Google Cloud Run...${NC}"

# Check if Google Cloud SDK is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: Google Cloud SDK (gcloud) not found. Please install it first.${NC}"
    exit 1
fi

# Check authentication
echo -e "${YELLOW}Checking GCP authentication...${NC}"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GCP. Please run 'gcloud auth login' first.${NC}"
    exit 1
fi

# Set the project
echo -e "${YELLOW}Setting GCP project to ${PROJECT_ID}...${NC}"
gcloud config set project ${PROJECT_ID}

# Create GCS bucket if it doesn't exist
echo -e "${YELLOW}Ensuring GCS bucket exists...${NC}"
if ! gcloud storage buckets describe gs://${GCS_BUCKET_NAME} &> /dev/null; then
    echo -e "${YELLOW}Creating GCS bucket ${GCS_BUCKET_NAME}...${NC}"
    gcloud storage buckets create gs://${GCS_BUCKET_NAME} --location=${REGION}
fi

# Check for required secrets
echo -e "${YELLOW}Checking for required secrets...${NC}"
for SECRET_NAME in "${SECRET_NAMES[@]}"; do
    if ! gcloud secrets describe ${SECRET_NAME} &> /dev/null; then
        echo -e "${RED}Secret ${SECRET_NAME} does not exist. Please create it first:${NC}"
        echo -e "gcloud secrets create ${SECRET_NAME} --replication-policy=\"automatic\""
        echo -e "echo -n \"your-secret-value\" | gcloud secrets versions add ${SECRET_NAME} --data-file=-"
        exit 1
    fi
done

# Build and push the Docker image
echo -e "${YELLOW}Building and pushing Docker image...${NC}"
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
gcloud builds submit --tag ${IMAGE_NAME} --file Dockerfile.cloudrun .

# Deploy to Cloud Run
echo -e "${YELLOW}Deploying to Cloud Run...${NC}"
gcloud run deploy ${SERVICE_NAME} \
    --image ${IMAGE_NAME} \
    --platform managed \
    --region ${REGION} \
    --allow-unauthenticated \
    --cpu=1 \
    --memory=1Gi \
    --min-instances=0 \
    --max-instances=10 \
    --set-env-vars="APP_ENV=production,GCS_BUCKET_NAME=${GCS_BUCKET_NAME},POSTGRES_DB=${DB_NAME}" \
    --update-secrets="POSTGRES_PASSWORD=POSTGRES_PASSWORD:latest,SECRET_KEY=SECRET_KEY:latest,GROQ_API_KEY=GROQ_API_KEY:latest,OPENAI_API_KEY=OPENAI_API_KEY:latest" \
    --set-cloudsql-instances="${PROJECT_ID}:${REGION}:${DB_INSTANCE_NAME}"

# Get the URL
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} --platform managed --region ${REGION} --format="value(status.url)")

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"
echo -e "${YELLOW}Don't forget to update your frontend application with this new URL.${NC}"

# Optional health check
echo -e "${YELLOW}Performing health check...${NC}"
curl -s ${SERVICE_URL}/api/v1/health | grep -q "status" && echo -e "${GREEN}Health check passed!${NC}" || echo -e "${RED}Health check failed!${NC}"

echo -e "${YELLOW}Notes:${NC}"
echo -e "1. Make sure your Cloud SQL instance '${DB_INSTANCE_NAME}' is properly set up"
echo -e "2. Update your Firebase/frontend with the new backend URL: ${SERVICE_URL}"
echo -e "3. Check the logs for any issues: gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}\" --limit=10" 