FROM python:3.10-slim

WORKDIR /app

# Install minimal dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy all application code
COPY . .

# Make sure the static directory exists
RUN mkdir -p static/audio

# Set environment variables - API keys should be passed at deployment time
ENV PORT=8080
# LLM model config
ENV OPENAI_LLM_MODEL=gpt-3.5-turbo

# TTS model config
ENV OPENAI_TTS_MODEL=gpt-4o-mini-tts
ENV OPENAI_TTS_VOICE=sage

# Transcription model config
ENV OPENAI_TRANSCRIPTION_MODEL=whisper-1

# App config
ENV ENVIRONMENT=production
ENV PYTHONUNBUFFERED=1
ENV UVICORN_TIMEOUT=300

# Expose the port
EXPOSE 8080

# Start the application with appropriate timeout
CMD uvicorn app.main:app --host 0.0.0.0 --port $PORT --timeout-keep-alive 300 