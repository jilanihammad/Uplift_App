FROM python:3.10-slim

WORKDIR /app

# Add build timestamp as an argument to force rebuild without cache
ENV BUILD_TIMESTAMP=20250806202328

# Install system dependencies including FFmpeg for OPUS audio conversion
RUN apt-get update && apt-get install -y     ffmpeg     && rm -rf /var/lib/apt/lists/*

# Install Python dependencies with deterministic approach
COPY requirements.txt .

# Install pipdeptree for dependency inspection
RUN pip install --no-cache-dir pipdeptree

# Install all dependencies EXCEPT OpenAI first (langchain might try to downgrade it)
RUN pip install --no-cache-dir -r requirements.txt

# Force reinstall OpenAI 1.95.0 AFTER other packages to override any downgrades
RUN pip install --no-cache-dir --force-reinstall openai==1.95.0

# Verify OpenAI version is correct and show dependency tree
RUN python -c "import openai; print(f'OpenAI SDK version: {openai.__version__}'); assert openai.__version__ == '1.95.0', f'Wrong OpenAI version: {openai.__version__}'" &&     echo "=== OpenAI dependency tree ===" &&     pipdeptree -p openai

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

# Create SQLite database directory with proper permissions
RUN mkdir -p /app/data
RUN touch /app/data/app.db
RUN chmod 777 /app/data/app.db

# Environment variables
ENV PORT=8080
ENV ENVIRONMENT=production
ENV GOOGLE_CLOUD=1
ENV DATABASE_URL=sqlite:///./data/app.db
ENV OPENAI_API_KEY=***REMOVED***
ENV GOOGLE_API_KEY=***REMOVED***
ENV GROQ_API_KEY=***REMOVED***
ENV OPENAI_LLM_MODEL=gpt-3.5-turbo
ENV OPENAI_TTS_MODEL=gpt-4o-mini-tts
ENV OPENAI_TTS_VOICE=sage
ENV OPENAI_TRANSCRIPTION_MODEL=whisper-1
ENV PYTHONUNBUFFERED=1
ENV USE_GROQ=0

# Force the application to run on port 8080 for Cloud Run
CMD uvicorn app.main:app --host 0.0.0.0 --port 8080
