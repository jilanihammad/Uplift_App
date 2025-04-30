# Environment Setup for AI Therapist App

## Overview
This app now uses environment variables for configuration, eliminating hardcoded values throughout the codebase. This allows for:

- Different configurations for development, staging, and production environments
- Secure handling of API keys and sensitive information
- Easier CI/CD workflow
- Local development without modifying the main codebase

## Setting Up Your .env File
1. Create a file named `.env` in the root of the `ai_therapist_app` directory
2. Copy the content below and replace with your appropriate values

```
# AI Therapist App Configuration

# === Backend API Configuration ===
BACKEND_URL=https://ai-therapist-backend-fuukqlcsha-uc.a.run.app
LLM_API_ENDPOINT=https://ai-therapist-backend-fuukqlcsha-uc.a.run.app
VOICE_MODEL_ENDPOINT=https://ai-therapist-backend-fuukqlcsha-uc.a.run.app

# === Model Configuration ===
LLM_MODEL_ID=meta-llama/llama-4-scout-17b-16e-instruct
TTS_MODEL_ID=playai-tts
TRANSCRIPTION_MODEL_ID=whisper-large-v3-turbo

# === Firebase Configuration ===
FIREBASE_API_KEY=YOUR_API_KEY
FIREBASE_APP_ID=YOUR_APP_ID
FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID
FIREBASE_PROJECT_ID=upliftapp-cd86e
FIREBASE_STORAGE_BUCKET=upliftapp-cd86e.appspot.com
FIREBASE_DATABASE_ID=upliftdb

# === App Configuration ===
IS_PRODUCTION_MODE=true
USE_VOICE_FEATURES=true
ENABLE_ANALYTICS=true
DEFAULT_THEME=light
```

## Configuration Variables Explained

### Backend API Configuration
- `BACKEND_URL`: The base URL for the backend service
- `LLM_API_ENDPOINT`: Endpoint for LLM (Language Model) API
- `VOICE_MODEL_ENDPOINT`: Endpoint for voice synthesis and recognition

### Model Configuration
- `LLM_MODEL_ID`: The ID of the language model to use
- `TTS_MODEL_ID`: The ID of the text-to-speech model
- `TRANSCRIPTION_MODEL_ID`: The ID of the speech-to-text model

### Firebase Configuration
- `FIREBASE_API_KEY`: Your Firebase API key
- `FIREBASE_APP_ID`: Your Firebase app ID
- `FIREBASE_MESSAGING_SENDER_ID`: Firebase Cloud Messaging sender ID
- `FIREBASE_PROJECT_ID`: Your Firebase project ID
- `FIREBASE_STORAGE_BUCKET`: Your Firebase storage bucket
- `FIREBASE_DATABASE_ID`: Your Firestore database ID

### App Configuration
- `IS_PRODUCTION_MODE`: Set to "true" for production, "false" for development
- `USE_VOICE_FEATURES`: Enable/disable voice features
- `ENABLE_ANALYTICS`: Enable/disable analytics
- `DEFAULT_THEME`: Default app theme (light/dark)

## Important Notes
- The `.env` file should never be committed to version control
- For local development, you can create a `.env.dev` file
- The app will fallback to default values if a variable is not found in the environment
- Some services might not work without valid API keys and configuration 