# AI Therapist Backend

This is the backend API for the AI Therapist application, built with FastAPI and designed to be deployed to Google Cloud Run.

## Local Development

1. Install dependencies:
   ```
   pip install -r requirements.txt
   ```

2. Set up environment variables:
   - Create a `.env` file based on `.env.example`
   - Set the required API keys and configuration

3. Run the development server:
   ```
   python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

## Deployment to Google Cloud

### Prerequisites

1. Install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)

2. Authenticate with Google Cloud:
   ```
   gcloud auth login
   ```

3. Create necessary secrets in Google Cloud Secret Manager:
   ```
   gcloud secrets create POSTGRES_PASSWORD --replication-policy="automatic"
   echo -n "your-password" | gcloud secrets versions add POSTGRES_PASSWORD --data-file=-
   
   # Repeat for all other secrets:
   # SECRET_KEY, GROQ_API_KEY, OPENAI_API_KEY, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, ENCRYPTION_KEY
   ```

4. Set up a Cloud SQL PostgreSQL instance:
   ```
   gcloud sql instances create jilaniuplift \
     --database-version=POSTGRES_13 \
     --tier=db-f1-micro \
     --region=us-central1 \
     --root-password=[YOUR_ROOT_PASSWORD]
   
   gcloud sql databases create ai_therapist --instance=jilaniuplift
   ```

### Deployment

1. Update the configuration variables in `deploy_to_cloud_run.sh`:
   - `PROJECT_ID`: Your Google Cloud project ID
   - `SERVICE_NAME`: Name for your Cloud Run service
   - `REGION`: Google Cloud region
   - `DB_INSTANCE_NAME`: Name of your Cloud SQL instance
   - `GCS_BUCKET_NAME`: Name for the Cloud Storage bucket to store audio files

2. Run the deployment script:
   ```
   bash deploy_to_cloud_run.sh
   ```

3. After successful deployment, update the frontend configuration:
   - Update the backend URL in `ai_therapist_app/lib/config/api.dart` to point to your new Cloud Run endpoint

## API Documentation

Once deployed, visit: `https://[YOUR-SERVICE-URL]/docs` to see the API documentation.

## Authentication Identity Model

- Each Firebase authentication provider (`provider`, `uid`) pair maps to its own `users` row.
- Accounts are no longer merged implicitly by email address.
- The backend links additional identities only when the same provider/uid logs in again.
- Use `user_identities.email` if you need the raw email/phone that the user authenticated with.

This isolation prevents users who share a device from seeing one another's therapy history.

## Session Endpoints

- `POST /sessions`: Create a new therapy session
- `GET /sessions/{session_id}`: Get details for a specific session
- `PATCH /sessions/{session_id}`: Update session details
- `DELETE /sessions/{session_id}`: Delete a session

## Model Endpoints

- `POST /ai/response`: Generate AI therapist response
- `POST /therapy/end_session`: End a session and generate summary
- `POST /voice/synthesize`: Generate speech from text
- `POST /voice/transcribe`: Transcribe audio to text
