FROM python:3.10-slim

WORKDIR /app

# Add build timestamp as an argument to force rebuild without cache
ENV BUILD_TIMESTAMP=20250607104713

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
ENV OPENAI_API_KEY=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
ENV GOOGLE_API_KEY=AIzaSyAa525sLf7FPId43NgvVTJECO8K79SJHzM
ENV OPENAI_LLM_MODEL=gpt-3.5-turbo
ENV OPENAI_TTS_MODEL=gpt-4o-mini-tts
ENV OPENAI_TTS_VOICE=sage
ENV OPENAI_TRANSCRIPTION_MODEL=whisper-1
ENV PYTHONUNBUFFERED=1
ENV USE_GROQ=0

# Force the application to run on port 8080 for Cloud Run
CMD uvicorn app.main:app --host 0.0.0.0 --port 8080
