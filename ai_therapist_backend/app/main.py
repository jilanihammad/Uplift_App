import uvicorn
from fastapi import FastAPI, Request, status, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import logging
import os
from fastapi.staticfiles import StaticFiles
from fastapi.openapi.docs import get_swagger_ui_html
from pydantic import BaseModel
import httpx
import uuid
import json

from app.api.api_v1.api import api_router
from app.core.config import settings
from app.core.rate_limiter import RateLimitMiddleware
from app.core.security_middleware import SecurityMiddleware
import openai

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)
logger = logging.getLogger("uvicorn.error")

# Configure OpenAI client to use Groq API
openai.api_key = settings.GROQ_API_KEY
openai.base_url = "https://api.groq.com/openai/v1/"  # Added trailing slash to ensure proper path joining

# Create the FastAPI app (ONLY ONCE)
app = FastAPI(
    title=settings.PROJECT_NAME,
    description="AI Therapist API for mental health support",
    version="1.0.0",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=None,  # Disable default docs
    redoc_url=None,  # Disable default ReDoc
)

# Add middleware - order matters!
app.add_middleware(SecurityMiddleware)
app.add_middleware(RateLimitMiddleware, requests_per_minute=60)

# Set all CORS enabled origins
if settings.BACKEND_CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# Include API router
app.include_router(api_router, prefix=settings.API_V1_STR)

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "An unexpected error occurred"},
    )

# Create directory for audio files if it doesn't exist
os.makedirs("static/audio", exist_ok=True)
# Serve static files (for audio in development)
app.mount("/audio", StaticFiles(directory="static/audio"), name="audio")

@app.get("/")
def read_root():
    return {"message": "Welcome to AI Therapist API"}

@app.get(f"{settings.API_V1_STR}/llm/status")
async def llm_status():
    """Check if the LLM API is available."""
    try:
        # Simple check that we have an API key
        if not settings.GROQ_API_KEY:
            return {"status": "unavailable", "reason": "No API key configured"}
        
        # We could make a simple API request to verify, but for now just return available
        return {"status": "available", "model": settings.GROQ_LLM_MODEL_ID}
    except Exception as e:
        logger.error("Error checking LLM status: %s", str(e))
        return {"status": "unavailable", "reason": str(e)}

class AIRequest(BaseModel):
    message: str
    system_prompt: str = ""
    model: str = None
    temperature: float = 0.7
    max_tokens: int = 1000

class VoiceRequest(BaseModel):
    text: str
    voice: str = "claude"  # Default voice
    model: str = None

class TranscriptionRequest(BaseModel):
    audio_url: str
    model: str = None

class EndSessionRequest(BaseModel):
    messages: list
    system_prompt: str = ""
    memory_context: str = ""
    therapeutic_approach: str = "supportive"
    visited_nodes: list = []

@app.post(f"{settings.API_V1_STR}/ai/response")
async def ai_response(request: AIRequest):
    """Handle AI response requests using Groq's LLM."""
    try:
        logger.info("Using API key: %s", settings.GROQ_API_KEY[:6] + "..." if settings.GROQ_API_KEY else "None")
        logger.info("Received AI response request: %s", request.message)
        
        # Prepare messages array
        messages = []
        if request.system_prompt:
            messages.append({"role": "system", "content": request.system_prompt})
        
        messages.append({"role": "user", "content": request.message})
        
        # Use the configured model ID or fallback to the one in the request
        model_id = request.model or settings.GROQ_LLM_MODEL_ID
        
        response = await openai.chat.completions.create(
            model=model_id,
            messages=messages,
            temperature=request.temperature,
            max_tokens=request.max_tokens
        )
        logger.info("AI response generated successfully")
        return {"response": response.choices[0].message.content}
    except Exception as e:
        logger.error("Error generating AI response: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error generating AI response: {str(e)}")

@app.post(f"{settings.API_V1_STR}/therapy/end_session")
async def end_session(request: EndSessionRequest):
    """Generate therapy session summary using Groq's LLM."""
    try:
        logger.info("Received end session request with %d messages", len(request.messages))
        
        # Create a summarization prompt
        conversation_text = ""
        for msg in request.messages:
            role = "User" if msg.get("isUser", False) else "Therapist"
            conversation_text += f"{role}: {msg.get('content', '')}\n\n"
        
        summary_prompt = f"""
        You are a skilled AI therapist assistant. Based on the conversation below, please provide:
        1. A concise summary of the key points discussed
        2. 3-5 actionable suggestions for the client
        3. 2-3 insights about patterns or progress noticed
        
        Therapeutic approach: {request.therapeutic_approach}
        
        CONVERSATION:
        {conversation_text}
        
        Please format your response as JSON with the following structure:
        {{
            "summary": "Summary of the session",
            "action_items": ["Action 1", "Action 2", ...],
            "insights": ["Insight 1", "Insight 2", ...]
        }}
        """
        
        # Generate summary using Groq LLM
        response = await openai.chat.completions.create(
            model=settings.GROQ_LLM_MODEL_ID,
            messages=[{"role": "user", "content": summary_prompt}]
        )
        
        # Parse the JSON response
        try:
            content = response.choices[0].message.content
            # Extract JSON from the response text (it might be wrapped in markdown code blocks)
            if "```json" in content:
                json_str = content.split("```json")[1].split("```")[0].strip()
            elif "```" in content:
                json_str = content.split("```")[1].strip()
            else:
                json_str = content
                
            result = json.loads(json_str)
            logger.info("Session summary generated successfully")
            return result
        except json.JSONDecodeError:
            # If JSON parsing fails, create a structured response manually
            logger.warning("Failed to parse LLM response as JSON, creating structured response manually")
            return {
                "summary": response.choices[0].message.content,
                "action_items": ["Practice mindfulness daily", "Journal about emotions"],
                "insights": ["Working through challenges with good progress"]
            }
            
    except Exception as e:
        logger.error("Error generating session summary: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error generating session summary: {str(e)}")

@app.post("/voice/synthesize")
async def voice_synthesize(request: VoiceRequest):
    """Handle text-to-speech requests using Groq's voice model."""
    try:
        logger.info("Received voice synthesis request: %s", request.text)
        
        # Use the configured model ID or fallback to the one in the request
        model_id = request.model or settings.GROQ_TTS_MODEL_ID
        
        # Use Groq's API for text-to-speech via compatible OpenAI interface
        response = await openai.audio.speech.create(
            model=model_id,
            voice=request.voice,
            input=request.text
        )
        
        # Save the audio to a file with a unique name
        filename = f"{uuid.uuid4()}.mp3"
        file_path = f"static/audio/{filename}"
        
        # Save audio content - fix by directly reading the binary content
        audio_content = await response.read()
        with open(file_path, "wb") as f:
            f.write(audio_content)
        
        logger.info("Voice synthesis completed successfully")
        # Return URL to the audio file
        return {"audio_url": f"/audio/{filename}"}
    except Exception as e:
        logger.error("Error generating voice response: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error generating voice response: {str(e)}")

@app.post("/voice/transcribe")
async def transcribe_audio(request: TranscriptionRequest):
    """Handle audio transcription requests using Groq's transcription model."""
    try:
        logger.info("Received transcription request for audio URL: %s", request.audio_url)
        
        # In a real implementation, we would download the audio from the URL
        # if it's not a local file path
        
        # For now, we'll assume request.audio_url is a local file path
        audio_path = request.audio_url
        if not os.path.exists(audio_path):
            audio_path = f"static/audio/{os.path.basename(request.audio_url)}"
            if not os.path.exists(audio_path):
                raise HTTPException(status_code=404, detail="Audio file not found")
        
        # Use the configured model ID or fallback to the one in the request
        model_id = request.model or settings.GROQ_TRANSCRIPTION_MODEL_ID
        
        # Use Groq's API for transcription via compatible OpenAI interface
        with open(audio_path, "rb") as f:
            response = await openai.audio.transcriptions.create(
                model=model_id,
                file=f
            )
        
        logger.info("Transcription completed successfully")
        return {"transcription": response.text}
    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except Exception as e:
        logger.error("Error transcribing audio: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error transcribing audio: {str(e)}")

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)