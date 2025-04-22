import uvicorn
from fastapi import FastAPI, Request, status, HTTPException, APIRouter
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
from typing import Optional, List
from datetime import datetime
import traceback
import base64

from app.api.api_v1.api import api_router
from app.core.config import settings
from app.core.rate_limiter import RateLimitMiddleware
from app.core.security_middleware import SecurityMiddleware
from app.core.logger import setup_logging
from app.services.groq_service import GroqService

# Configure logging
setup_logging()
logger = logging.getLogger(__name__)

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
        allow_origins=["*"] if settings.BACKEND_CORS_ORIGINS == ["*"] else [str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
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
    import os
    port = os.environ.get("PORT", "8080")
    return {"message": "Welcome to AI Therapist API", "status": "healthy", "port": port}

@app.get("/health")
def health_check():
    """Health check endpoint for Google Cloud Run."""
    return {"status": "healthy"}

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
    voice: str = "Jennifer-PlayAI"  # Default voice for PlayAI TTS model
    model: str = None

class TranscriptionRequest(BaseModel):
    audio_url: Optional[str] = None
    audio_data: Optional[str] = None  # Base64 encoded audio data
    audio_format: Optional[str] = "mp3"  # Format of the audio (mp3, wav, aac, etc.)
    model: Optional[str] = None

class EndSessionRequest(BaseModel):
    messages: list
    system_prompt: str = ""
    memory_context: str = ""
    therapeutic_approach: str = "supportive"
    visited_nodes: list = []

@app.post("/ai/response")
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
        
        # Use the modern client approach with httpx for async support
        async with httpx.AsyncClient() as client:
            headers = {
                "Authorization": f"Bearer {settings.GROQ_API_KEY}",
                "Content-Type": "application/json"
            }
            payload = {
                "model": model_id,
                "messages": messages,
                "temperature": request.temperature,
                "max_tokens": request.max_tokens
            }
            
            url = f"{settings.GROQ_API_BASE_URL}/chat/completions"
            response = await client.post(url, json=payload, headers=headers)
            
            if response.status_code != 200:
                logger.error(f"Error from Groq API: {response.status_code} - {response.text}")
                raise HTTPException(status_code=500, detail=f"Error from Groq API: {response.text}")
            
            # Parse the JSON response directly from the HTTP response
            response_data = response.json()
            logger.info("AI response generated successfully")
            return {"response": response_data["choices"][0]["message"]["content"]}
            
    except Exception as e:
        logger.error("Error generating AI response: %s", str(e))
        # Log more detailed error information for debugging
        logger.error("Exception type: %s", type(e).__name__)
        logger.error("Exception traceback: %s", traceback.format_exc())
        
        # Fall back to a template-based response rather than crashing
        return {"response": "I'm listening and I'm here to support you. What strategies have you tried so far?"}

@app.post("/therapy/end_session")
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
        
        # Use direct HTTP call to the Groq API to avoid the async issue
        async with httpx.AsyncClient() as client:
            headers = {
                "Authorization": f"Bearer {settings.GROQ_API_KEY}",
                "Content-Type": "application/json"
            }
            payload = {
                "model": settings.GROQ_LLM_MODEL_ID,
                "messages": [{"role": "user", "content": summary_prompt}],
                "temperature": 0.7,
                "max_tokens": 1000
            }
            
            url = f"{settings.GROQ_API_BASE_URL}/chat/completions"
            response = await client.post(url, json=payload, headers=headers)
            
            if response.status_code != 200:
                logger.error(f"Error from Groq API: {response.status_code} - {response.text}")
                # Fall back to template if API call fails
                return {
                    "summary": "In this session, we discussed various aspects of your current challenges and explored potential coping strategies.",
                    "action_items": [
                        "Practice deep breathing for 5 minutes when feeling anxious",
                        "Keep a mood journal to track emotional patterns",
                        "Schedule one self-care activity this week"
                    ],
                    "insights": [
                        "You've been making progress in recognizing your triggers",
                        "Your self-awareness is a significant strength",
                        "Small consistent steps can lead to meaningful change"
                    ]
                }
            
            # Parse the JSON response
            try:
                response_data = response.json()
                content = response_data["choices"][0]["message"]["content"]
                
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
            except (json.JSONDecodeError, KeyError) as e:
                # If JSON parsing fails, create a structured response manually
                logger.warning(f"Failed to parse LLM response as JSON: {str(e)}, creating structured response manually")
                return {
                    "summary": response_data["choices"][0]["message"]["content"] if "choices" in response_data else "Session summary not available.",
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
        logger.info("Received TTS request: %s", request.text[:30] + "..." if len(request.text) > 30 else request.text)
        
        # Import voice_service here to avoid circular imports
        from app.services.voice_service import voice_service
        
        # Set the requested voice if provided
        if request.voice:
            voice_service.set_voice(request.voice)
        
        # Generate speech using the GROQ API via voice_service
        audio_url = await voice_service.generate_speech(request.text)
        
        # Log the result for debugging
        logger.info("Voice service returned audio_url: %s", audio_url)
        
        # Ensure we always have a URL, even if generation failed
        if not audio_url:
            logger.error("Failed to generate audio, returning fallback audio")
            audio_url = "/audio/error.mp3"
            
            # Check if the fallback file exists
            import os
            fallback_path = os.path.join("static/audio", "error.mp3")
            if not os.path.exists(fallback_path):
                logger.error("Fallback audio file %s does not exist", fallback_path)
                # Create a directory for audio files if it doesn't exist
                os.makedirs("static/audio", exist_ok=True)
                # Create an empty file as absolute fallback
                with open(fallback_path, "wb") as f:
                    f.write(b"")
                logger.info("Created empty fallback audio file at %s", fallback_path)
        
        logger.info("Audio generated successfully at: %s", audio_url)
        
        # Return the URL to the audio file - note we use 'url' key to match Flutter app expectations
        response_data = {"url": audio_url}
        logger.info("Returning response: %s", response_data)
        return response_data
    
    except Exception as e:
        logger.error("Error synthesizing speech: %s", str(e))
        logger.error("Exception traceback: %s", traceback.format_exc())
        
        # Return a fallback audio URL
        fallback_url = "/audio/error.mp3"
        logger.info("Returning fallback URL: %s", fallback_url)
        return {"url": fallback_url}

@app.post("/voice/transcribe")
async def transcribe_audio(request: Request):
    """Endpoint to transcribe audio sent as base64 encoded data."""
    try:
        # Get the request body as JSON
        json_data = await request.json()
        audio_data = json_data.get("audio_data")
        audio_format = json_data.get("audio_format", "aac")  # Default to aac if not specified
        model = json_data.get("model", "distil-whisper-large-v3-en")  # Default to GROQ's distil-whisper model
        
        logger.info(f"Received transcription request. Format: {audio_format}, Model: {model}")
        
        # Check if audio data was provided
        if not audio_data:
            logger.warning("No audio data provided for transcription")
            return {"text": "I couldn't hear anything. Please try again or type your message."}
        
        # Log the size of the received audio data
        audio_data_length = len(audio_data) if audio_data else 0
        logger.info(f"Audio data received: {audio_data_length} characters")
        
        # Decode the base64 audio data
        try:
            audio_bytes = base64.b64decode(audio_data)
            logger.info(f"Successfully decoded audio: {len(audio_bytes)} bytes, format: {audio_format}")
            
            if len(audio_bytes) < 100:
                logger.warning(f"Audio data too small ({len(audio_bytes)} bytes), likely invalid")
                return {"text": "The recorded audio was too short. Please try again or type your message."}
            
            # Save to a temporary file
            import tempfile
            import os
            
            temp_dir = tempfile.gettempdir()
            unique_id = uuid.uuid4()
            temp_file_path = os.path.join(temp_dir, f"audio_transcription_{unique_id}.{audio_format}")
            
            logger.info(f"Will save audio to temporary file: {temp_file_path}")
            
            with open(temp_file_path, "wb") as f:
                f.write(audio_bytes)
            
            # Verify the file was written successfully
            if os.path.exists(temp_file_path):
                file_size = os.path.getsize(temp_file_path)
                logger.info(f"Saved audio to temporary file: {temp_file_path}, size: {file_size} bytes")
            else:
                logger.error(f"Failed to save audio file at {temp_file_path}")
                return {"text": "Error saving the audio file. Please try again."}
            
            # Check if file exists and has content
            if not os.path.exists(temp_file_path) or os.path.getsize(temp_file_path) == 0:
                logger.error(f"Temporary file creation failed or file is empty: {temp_file_path}")
                return {"text": "There was an issue processing your audio. Please try again or type your message."}
            
            # Call GROQ API for transcription
            from app.services.groq_service import groq_service
            
            logger.info(f"Calling transcription service with model: {model}")
            try:
                transcription = await groq_service.transcribe_audio(temp_file_path, model)
                logger.info(f"Transcription service returned: '{transcription}'")
            except Exception as e:
                logger.error(f"Error from transcription service: {str(e)}")
                logger.error(f"Traceback: {traceback.format_exc()}")
                return {"text": "There was an error with the transcription service. Please try again or type your message."}
            
            # Clean up the temporary file
            try:
                os.remove(temp_file_path)
                logger.info("Temporary audio file removed")
            except Exception as e:
                logger.error(f"Error removing temporary file: {str(e)}")
            
            if transcription and transcription.strip():
                logger.info(f"Transcription successful: {transcription}")
                return {"text": transcription}
            else:
                logger.warning("Empty transcription result")
                return {"text": "I couldn't understand what you said. Please try again or type your message."}
                
        except Exception as e:
            logger.error(f"Error processing audio data: {str(e)}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            return {"text": "I had trouble understanding your audio. Please try again or type your message."}
            
    except Exception as e:
        logger.error(f"Error in transcribe_audio endpoint: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        return {"text": "There was an issue with the transcription. Please try again or type your message."}

# Session-related schemas
class SessionUpdateRequest(BaseModel):
    title: Optional[str] = None
    summary: Optional[str] = None

class SessionResponse(BaseModel):
    id: str
    title: str
    summary: Optional[str] = None
    created_at: str
    last_modified: str
    isSynced: bool = True

@app.get("/sessions", status_code=status.HTTP_200_OK)
async def get_sessions():
    """Get all sessions"""
    try:
        logger.info("Getting all sessions")
        # In a real implementation, you would query the database
        # For now, return a mock response with a couple of sessions
        now = datetime.now().isoformat()
        return [
            {
                "id": str(uuid.uuid4()),
                "title": "First Session",
                "summary": "Introduction and goal setting",
                "created_at": now,
                "last_modified": now,
                "isSynced": True
            },
            {
                "id": str(uuid.uuid4()),
                "title": "Follow-up Session",
                "summary": "Progress check and new exercises",
                "created_at": now,
                "last_modified": now,
                "isSynced": True
            }
        ]
    except Exception as e:
        logger.error(f"Error getting sessions: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error getting sessions: {str(e)}")

@app.post("/sessions", status_code=status.HTTP_201_CREATED, response_model=SessionResponse)
async def create_session():
    """Create a new session"""
    try:
        logger.info("Creating new session")
        # In a real implementation, you would save to the database
        session_id = str(uuid.uuid4())
        now = datetime.now().isoformat()
        return {
            "id": session_id,
            "title": f"New Session {session_id[:8]}",
            "summary": None,
            "created_at": now,
            "last_modified": now,
            "isSynced": True
        }
    except Exception as e:
        logger.error(f"Error creating session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error creating session: {str(e)}")

@app.get("/sessions/{session_id}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def get_session(session_id: str):
    """Get a specific session"""
    try:
        logger.info(f"Getting session {session_id}")
        # In a real implementation, you would query the database
        now = datetime.now().isoformat()
        # For now, return a mock response
        return {
            "id": session_id,
            "title": f"Session {session_id[:8]}",
            "summary": "Session summary not available",
            "created_at": now,
            "last_modified": now,
            "isSynced": True
        }
    except Exception as e:
        logger.error(f"Error getting session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error getting session: {str(e)}")

@app.patch("/sessions/{session_id}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def update_session(session_id: str, request: SessionUpdateRequest):
    """Update a session"""
    try:
        logger.info(f"Updating session {session_id}")
        # In a real implementation, you would update the database
        now = datetime.now().isoformat()
        # Return the updated session
        return {
            "id": session_id,
            "title": request.title or f"Session {session_id[:8]}",
            "summary": request.summary or "No summary available",
            "created_at": now,
            "last_modified": now,
            "isSynced": True
        }
    except Exception as e:
        logger.error(f"Error updating session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error updating session: {str(e)}")

@app.delete("/sessions/{session_id}", status_code=status.HTTP_200_OK)
async def delete_session(session_id: str):
    """Delete a session"""
    try:
        logger.info(f"Deleting session {session_id}")
        # In a real implementation, you would delete from the database
        # For now, just return success
        return {"status": "success", "message": f"Session {session_id} deleted"}
    except Exception as e:
        logger.error(f"Error deleting session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error deleting session: {str(e)}")

@app.post("/sessions/{session_id}/messages", status_code=status.HTTP_200_OK)
async def add_session_message(session_id: str, message: dict):
    """Add a message to a session"""
    try:
        logger.info(f"Adding message to session {session_id}")
        # In a real implementation, you would save the message to the database
        # For now, we'll return a mock response
        return {"status": "success", "message_id": str(uuid.uuid4())}
    except Exception as e:
        logger.error(f"Error adding message: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error adding message: {str(e)}")

# Legacy API endpoints with /api/v1 prefix included explicitly
@app.get(f"{settings.API_V1_STR}/sessions", status_code=status.HTTP_200_OK)
async def get_sessions_legacy():
    """Legacy endpoint for getting all sessions"""
    return await get_sessions()

@app.get(f"{settings.API_V1_STR}/sessions/{{session_id}}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def get_session_legacy(session_id: str):
    """Legacy endpoint for getting a specific session"""
    return await get_session(session_id)

@app.patch(f"{settings.API_V1_STR}/sessions/{{session_id}}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def update_session_legacy(session_id: str, request: SessionUpdateRequest):
    """Legacy endpoint for updating a session"""
    return await update_session(session_id, request)

@app.delete(f"{settings.API_V1_STR}/sessions/{{session_id}}", status_code=status.HTTP_200_OK)
async def delete_session_legacy(session_id: str):
    """Legacy endpoint for deleting a session"""
    return await delete_session(session_id)

@app.post(f"{settings.API_V1_STR}/sessions/{{session_id}}/messages", status_code=status.HTTP_200_OK)
async def add_session_message_legacy(session_id: str, message: dict):
    """Legacy endpoint for adding a message to a session"""
    return await add_session_message(session_id, message)

# Replace the catch-all route with more specific error handlers
@app.exception_handler(404)
async def custom_404_handler(request: Request, exc):
    logger.warning(f"Route not found: {request.method} {request.url.path}")
    return JSONResponse(
        status_code=status.HTTP_404_NOT_FOUND,
        content={"detail": f"Route not found: {request.url.path}"}
    )

@app.exception_handler(405)
async def custom_405_handler(request: Request, exc):
    logger.warning(f"Method {request.method} not allowed for {request.url.path}")
    return JSONResponse(
        status_code=status.HTTP_405_METHOD_NOT_ALLOWED,
        content={"detail": f"Method {request.method} not allowed for {request.url.path}"}
    )

# Define a router for root paths (non-prefixed) for compatibility
root_router = APIRouter()

@root_router.post("/ai/response")
async def root_ai_response(request: AIRequest):
    return await ai_response(request)

@root_router.post("/voice/synthesize")
async def root_voice_synthesize(request: VoiceRequest):
    return await voice_synthesize(request)

@root_router.post("/voice/transcribe")
async def root_transcribe_audio(request: TranscriptionRequest):
    return await transcribe_audio(request)

@root_router.post("/therapy/end_session")
async def root_end_session(request: EndSessionRequest):
    return await end_session(request)

@root_router.get("/sessions")
async def root_get_sessions():
    return await get_sessions()

@root_router.post("/sessions")
async def root_create_session():
    return await create_session()

@root_router.get("/sessions/{session_id}")
async def root_get_session(session_id: str):
    return await get_session(session_id)

@root_router.patch("/sessions/{session_id}")
async def root_update_session(session_id: str, request: SessionUpdateRequest):
    return await update_session(session_id, request)

@root_router.delete("/sessions/{session_id}")
async def root_delete_session(session_id: str):
    return await delete_session(session_id)

@root_router.post("/sessions/{session_id}/messages")
async def root_add_session_message(session_id: str, message: dict):
    return await add_session_message(session_id, message)

# Include the root router
app.include_router(root_router)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)