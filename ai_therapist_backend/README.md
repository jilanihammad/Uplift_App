# AI Therapist Backend

A FastAPI backend for the AI Therapist application that works seamlessly in both local development and Firebase environments.

## Environment Setup

This project uses an environment-based configuration system that allows for seamless transitions between:
- Local development
- Firebase deployment

### Prerequisites

- Python 3.10+ installed
- Firebase CLI installed (`npm install -g firebase-tools`)
- Firebase account and project created
- Google Cloud account connected to your Firebase project

## Local Development

### Setup

1. **Create environment files**:
   - `.env.local` for local development
   - `.env.production` for Firebase production

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Set up your environment**:
   ```bash
   # Run the setup script
   python scripts/dev.py setup
   ```

4. **Edit `.env.local`** and add your API keys:
   ```
   APP_ENV=local
   GROQ_API_KEY=your_actual_groq_api_key
   OPENAI_API_KEY=your_actual_openai_api_key
   # ... other configuration
   ```

### Running Locally

Use the development script:

```bash
python scripts/dev.py local
```

The server will start at `http://localhost:8000` with auto-reload enabled.

## Firebase Deployment

### First-Time Setup

1. **Login to Firebase**:
   ```bash
   firebase login
   ```

2. **Initialize Firebase** (if not already done):
   ```bash
   firebase init
   ```
   - Select "Functions" and "Hosting"
   - Choose your project
   - Select Python as the language

3. **Set environment variables in Firebase**:
   ```bash
   # Set production environment variables
   firebase functions:config:set groq.api_key="your_groq_api_key" openai.api_key="your_openai_api_key"
   ```

### Deploying to Firebase

Deploy using the development script:

```bash
python scripts/dev.py deploy
```

This will:
1. Set the environment to production
2. Deploy the functions to Firebase

### Deployment to Different Environments

To deploy to staging or development environments:

```bash
python scripts/dev.py deploy --env staging
```

## Project Structure

- `app/` - Main application code
  - `core/` - Core components
    - `environment.py` - Environment configuration
    - `config.py` - Application settings
  - `main.py` - FastAPI application
- `scripts/` - Utility scripts
  - `dev.py` - Development helper script
- `main.py` - Firebase Functions entry point
- `.env.local` - Local environment variables
- `.env.production` - Production environment variables template

## Environment Variables

Create these files with the appropriate variables:

- `.env.local` - For local development
- `.env.development` - For Firebase development environment
- `.env.staging` - For Firebase staging environment
- `.env.production` - For Firebase production environment

## Testing

Run tests with:

```bash
pytest
```

## Troubleshooting

### API Key Issues

If experiencing authentication errors with Groq or OpenAI:

1. Verify the API keys in your environment files
2. For Firebase, check that the environment variables are properly set:
   ```bash
   firebase functions:config:get
   ```
   
### CORS Issues

If experiencing CORS issues, update the `BACKEND_CORS_ORIGINS` setting in your environment file to include the frontend domain.