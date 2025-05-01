FROM python:3.10-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Environment variables
ENV PORT=8080
ENV ENVIRONMENT=production
ENV GOOGLE_CLOUD=1
ENV OPENAI_API_KEY=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
ENV OPENAI_LLM_MODEL=gpt-3.5-turbo
ENV OPENAI_TTS_MODEL=gpt-4o-mini-tts
ENV OPENAI_TTS_VOICE=sage
ENV OPENAI_TRANSCRIPTION_MODEL=whisper-1
ENV PYTHONUNBUFFERED=1
ENV USE_GROQ=0

# Force the application to run on port 8080 for Cloud Run
CMD uvicorn app.main:app --host 0.0.0.0 --port 8080
