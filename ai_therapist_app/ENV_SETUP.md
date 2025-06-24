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
  # Database
POSTGRES_SERVER=localhost
POSTGRES_USER=postgres
POSTGRES_PASSWORD=7860
POSTGRES_DB=ai_therapist

# Security
SECRET_KEY=your_secret_key
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# API
API_V1_STR=/api/v1
SERVER_HOST=http://localhost:8000

# Groq API Configuration
GROQ_API_KEY=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
GROQ_API_BASE_URL=https://api.groq.com/openai/v1
GROQ_LLM_MODEL_ID=llama-3.3-70b-versatile

#backend URL
SERVER_HOST=https://ai-therapist-backend-385290373302.us-central1.run.app

GOOGLE_API_KEY=AIzaSyAa525sLf7FPId43NgvVTJECO8K79SJHzM
GOOGLE_LLM_MODEL_ID=gemini-2.5-flash-preview-05-20
GOOGLE_TTS_MODEL=gemini-2.5-flash-preview-tts
GOOGLE_TTS_VOICE=Zephyr
GOOGLE_API_BASE_URL=https://generativelanguage.googleapis.com/v1beta

      

OPENAI_API_KEY=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
OPENAI_TTS_MODEL=gpt-4o-mini-tts
OPENAI_TTS_VOICE=sage
OPENAI_TRANSCRIPTION_MODEL=gpt-4o-mini-transcribe


#Huggingface Token: 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

# Payment
STRIPE_SECRET_KEY=your_stripe_secret_key
STRIPE_WEBHOOK_SECRET=your_stripe_webhook_secret
BASIC_MONTHLY_PRICE_ID=price_basic_monthly
BASIC_YEARLY_PRICE_ID=price_basic_yearly
PREMIUM_MONTHLY_PRICE_ID=price_premium_monthly
PREMIUM_YEARLY_PRICE_ID=price_premium_yearly

# Security
ENCRYPTION_KEY=your_encryption_key