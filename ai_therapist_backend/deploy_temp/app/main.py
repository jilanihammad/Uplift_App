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
import sys
from sqlalchemy.orm import Session as DBSession
from fastapi import Depends

# Database initialization imports
from app.db.base import Base
from app.db.session import engine

# Create database tables on startup
def init_db():
    try:
        # Create tables
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created successfully")
    except Exception as e:
        logger.error(f"Error creating database tables: {str(e)}")
        logger.error(traceback.format_exc())

# Setup basic logging first
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize database - must happen after logger is created but before app starts
init_db()

# Safely import dependencies with error handling
try:
    from app.api.api_v1.api import api_router
    from app.core.config import settings
    from app.core.rate_limiter import RateLimitMiddleware
    from app.core.security_middleware import SecurityMiddleware
    from app.core.logger import setup_logging
    from app.core.health import get_health_status
    
    # Configure structured logging
    setup_logging()
    
    # Log startup information
    logger.info("Starting AI Therapist Backend")
    logger.info(f"Environment: {os.environ.get('ENVIRONMENT', 'development')}")
    logger.info(f"PORT: {os.environ.get('PORT', '8080')}")
    
    try:
        from app.services.groq_service import GroqService
        logger.info("Successfully imported GroqService")
    except Exception as e:
        logger.warning(f"Error importing GroqService: {str(e)}")
        
except Exception as e:
    logger.error(f"Error during imports: {str(e)}")
    logger.error(traceback.format_exc())
    # Create fallback settings for minimal app functionality
    from types import SimpleNamespace
    settings = SimpleNamespace(
        PROJECT_NAME="AI Therapist API",
        API_V1_STR="/api/v1",
        BACKEND_CORS_ORIGINS=["*"],
        # Add API keys and model values for compatibility
        OPENAI_API_KEY=os.environ.get("OPENAI_API_KEY", ""),
        GROQ_API_KEY=os.environ.get("GROQ_API_KEY", ""),
        GROQ_API_BASE_URL=os.environ.get("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1"),
        GROQ_LLM_MODEL_ID=os.environ.get("GROQ_LLM_MODEL_ID", "meta-llama/llama-4-scout-17b-16e-instruct"),
        OPENAI_TTS_MODEL=os.environ.get("OPENAI_TTS_MODEL", "gpt-4o-mini-tts"),
        OPENAI_TTS_VOICE=os.environ.get("OPENAI_TTS_VOICE", "sage"),
        OPENAI_TRANSCRIPTION_MODEL=os.environ.get("OPENAI_TRANSCRIPTION_MODEL", "whisper-1")
    )
    
    # Create fallback middleware classes if they couldn't be imported
    try:
        from starlette.middleware.base import BaseHTTPMiddleware
        
        class FallbackSecurityMiddleware(BaseHTTPMiddleware):
            async def dispatch(self, request, call_next):
                logger.info(f"Security middleware (fallback) processing request: {request.url.path}")
                return await call_next(request)
                
        class FallbackRateLimitMiddleware(BaseHTTPMiddleware):
            def __init__(self, app, requests_per_minute=60):
                super().__init__(app)
                self.requests_per_minute = requests_per_minute
                
            async def dispatch(self, request, call_next):
                logger.info(f"Rate limit middleware (fallback) processing request: {request.url.path}")
                return await call_next(request)
    except ImportError:
        # If we can't import BaseHTTPMiddleware, create empty middleware classes
        # that won't be used (we'll skip adding middleware in this case)
        logger.warning("Could not import BaseHTTPMiddleware, skipping middleware setup")
        class FallbackSecurityMiddleware:
            pass
            
        class FallbackRateLimitMiddleware:
            def __init__(self, app, requests_per_minute=60):
                pass
    
    # Use the fallback middleware classes
    SecurityMiddleware = FallbackSecurityMiddleware
    RateLimitMiddleware = FallbackRateLimitMiddleware
    
    logger.warning("Using fallback settings and middleware due to import errors")
    # We'll create a minimal app that can respond to health checks

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
try:
    app.add_middleware(SecurityMiddleware)
    app.add_middleware(RateLimitMiddleware, requests_per_minute=60)
    logger.info("Successfully added middleware")
except Exception as e:
    logger.error(f"Error adding middleware: {str(e)}")
    logger.error(traceback.format_exc())
    logger.warning("Continuing without middleware - limited functionality")

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
try:
    app.include_router(api_router, prefix=settings.API_V1_STR)
except NameError:
    # Create a fallback API router if the original couldn't be imported
    from fastapi import APIRouter
    fallback_router = APIRouter()
    
    @fallback_router.get("/")
    def fallback_root():
        return {"message": "API router fallback - limited functionality available"}
    
    @fallback_router.get("/health")
    def fallback_health():
        return {
            "status": "limited",
            "message": "Running with fallback API router",
            "timestamp": datetime.now().isoformat()
        }
    
    app.include_router(fallback_router, prefix=settings.API_V1_STR)
    logger.warning("Using fallback API router due to import error")

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "An unexpected error occurred"},
    )

# Create directory for audio files if it doesn't exist
# In Cloud Run, we should use a more cloud-friendly approach
if os.environ.get("GOOGLE_CLOUD") == "1":
    # In Cloud Run, log instead of creating local directories
    logger.info("Running in Cloud Run, using cloud-friendly static file handling")
    static_files_path = "/tmp/static/audio"  # Use /tmp which is writable in Cloud Run
else:
    # For local development, use local directory
    static_files_path = "static/audio"

# Create the directory if needed
os.makedirs(static_files_path, exist_ok=True)
logger.info(f"Using static files path: {static_files_path}")

# Serve static files (for audio)
try:
    app.mount("/audio", StaticFiles(directory=static_files_path), name="audio")
    logger.info("Successfully mounted static files directory")
except Exception as e:
    logger.error(f"Error mounting static files: {str(e)}")
    logger.error(traceback.format_exc())

@app.get("/")
def read_root():
    """Root endpoint for the API."""
    try:
        health_status = get_health_status()
        return {
            "message": "Welcome to AI Therapist API",
            "status": health_status["status"],
            "port": health_status["port"],
            "timestamp": health_status["timestamp"]
        }
    except Exception as e:
        logger.error(f"Error in root endpoint: {str(e)}")
        return {
            "message": "Welcome to AI Therapist API",
            "status": "degraded",
            "port": os.environ.get("PORT", "8080"),
            "error": str(e)
        }

@app.get("/health")
def health_check():
    """Health check endpoint for Google Cloud Run."""
    try:
        return get_health_status()
    except Exception as e:
        logger.error(f"Error in health check endpoint: {str(e)}")
        return {
            "status": "degraded",
            "timestamp": datetime.now().isoformat(),
            "error": str(e)
        }

@app.get(f"{settings.API_V1_STR}/llm/status")
async def llm_status():
    """Check if the LLM API is available."""
    try:
        # Check that we have either a GROQ or OpenAI API key
        if not settings.GROQ_API_KEY and not settings.OPENAI_API_KEY:
            return {"status": "unavailable", "reason": "No API key configured"}
        
        # Return which API we're using
        if settings.OPENAI_API_KEY:
            return {"status": "available", "model": settings.OPENAI_TTS_MODEL, "provider": "openai"}
        else:
            return {"status": "available", "model": settings.GROQ_LLM_MODEL_ID, "provider": "groq"}
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
    voice: str = "nia-PlayAI"  # Default voice for PlayAI TTS model
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
        logger.info("Received AI response request: %s", request.message)
        
        # Import Groq service instead of OpenAI
        try:
            from app.services.groq_service import groq_service
            logger.info("Groq service imported successfully")
        except Exception as import_error:
            logger.error(f"Failed to import groq_service: {str(import_error)}")
            logger.error(traceback.format_exc())
            raise HTTPException(status_code=500, detail=f"Groq service import error: {str(import_error)}")
        
        # Generate response using Groq
        response_text = await groq_service.generate_response(
            message=request.message,
            system_prompt=request.system_prompt, 
            model=request.model,
            temperature=request.temperature,
            max_tokens=request.max_tokens
        )
        
        logger.info("AI response generated successfully using Groq")
        return {"response": response_text}
            
    except Exception as e:
        logger.error("Error generating AI response: %s", str(e))
        logger.error("Exception traceback: %s", traceback.format_exc())
        
        # Return the actual error instead of a fallback response
        raise HTTPException(status_code=500, detail=f"Error generating AI response: {str(e)}")

@app.post("/therapy/end_session")
async def end_session(request: EndSessionRequest):
    """Generate therapy session summary using OpenAI's LLM."""
    try:
        logger.info("Received end session request with %d messages", len(request.messages))
        
        # Import OpenAI service
        from app.services.openai_service import openai_service
        
        # Generate session summary using OpenAI
        result = await openai_service.generate_session_summary(
            messages=request.messages,
            therapeutic_approach=request.therapeutic_approach,
            system_prompt=request.system_prompt,
            memory_context=request.memory_context
        )
        
        logger.info("Session summary generated successfully")
        return result
            
    except Exception as e:
        logger.error("Error generating session summary: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error generating session summary: {str(e)}")

@app.post("/voice/synthesize")
async def voice_synthesize(request: VoiceRequest):
    """Handle text-to-speech requests using OpenAI voice model."""
    try:
        logger.info("Received TTS request: %s", request.text[:30] + "..." if len(request.text) > 30 else request.text)
        
        if not request.text:
            raise HTTPException(status_code=400, detail="No text provided for TTS")
        
        # Import voice_service here to avoid circular imports
        try:
            from app.services.voice_service import voice_service
            logger.info("Voice service imported successfully")
        except Exception as import_error:
            logger.error(f"Failed to import voice_service: {str(import_error)}")
            logger.error(traceback.format_exc())
            raise HTTPException(status_code=500, detail=f"Voice service import error: {str(import_error)}")
        
        # Set the requested voice if provided
        if request.voice:
            try:
                voice_service.set_voice(request.voice)
            except Exception as voice_error:
                logger.error(f"Error setting voice: {str(voice_error)}")
                raise HTTPException(status_code=500, detail=f"Error setting voice: {str(voice_error)}")
        
        # Generate speech using the OpenAI API via voice_service
        try:
            audio_url = await voice_service.generate_speech(request.text)
            if not audio_url:
                raise HTTPException(status_code=500, detail="Failed to generate audio - empty URL returned")
                
            logger.info(f"Audio generated successfully at: {audio_url}")
            return {"url": audio_url}
            
        except Exception as speech_error:
            logger.error(f"Error generating speech: {str(speech_error)}")
            logger.error(traceback.format_exc())
            raise HTTPException(status_code=500, detail=f"Error generating speech: {str(speech_error)}")
    
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Error in voice_synthesize endpoint: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"TTS error: {str(e)}")

@app.post("/voice/transcribe")
async def transcribe_audio(request: Request):
    """Endpoint to transcribe audio sent as base64 encoded data using OpenAI."""
    try:
        # Get the request body as JSON
        json_data = await request.json()
        audio_data = json_data.get("audio_data")
        audio_format = json_data.get("audio_format", "aac")  # Default to aac if not specified
        # Use environment variable for model if specified in request
        requested_model = json_data.get("model", settings.OPENAI_TRANSCRIPTION_MODEL)
        
        logger.info(f"Received transcription request. Format: {audio_format}, Model: {requested_model}")
        
        # Check if audio data was provided
        if not audio_data:
            logger.warning("No audio data provided for transcription")
            raise HTTPException(status_code=400, detail="No audio data provided")
        
        # Log the size of the received audio data
        audio_data_length = len(audio_data) if audio_data else 0
        logger.info(f"Audio data received: {audio_data_length} characters")
        
        # Decode the base64 audio data
        try:
            audio_bytes = base64.b64decode(audio_data)
            logger.info(f"Successfully decoded audio: {len(audio_bytes)} bytes, format: {audio_format}")
            
            if len(audio_bytes) < 100:
                logger.warning(f"Audio data too small ({len(audio_bytes)} bytes), likely invalid")
                raise HTTPException(status_code=400, detail="Audio data too small or invalid")
            
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
                raise HTTPException(status_code=500, detail="Failed to save audio file")
            
            # Import OpenAI service
            from app.services.openai_service import openai_service
            
            # Set the requested model in the service if it was provided
            if requested_model != settings.OPENAI_TRANSCRIPTION_MODEL:
                logger.info(f"Using non-default transcription model: {requested_model}")
                # Save original model to restore later
                original_model = openai_service.transcription_model
                openai_service.transcription_model = requested_model
            
            # Transcribe the audio using OpenAI service
            logger.info(f"Calling OpenAI transcription service with model: {openai_service.transcription_model}")
            try:
                transcription = await openai_service.transcribe_audio(temp_file_path)
                logger.info(f"Transcription service returned: '{transcription}'")
                
                # Restore original model if we changed it
                if requested_model != settings.OPENAI_TRANSCRIPTION_MODEL:
                    openai_service.transcription_model = original_model
                    
            except Exception as e:
                # Restore original model if we changed it
                if requested_model != settings.OPENAI_TRANSCRIPTION_MODEL:
                    openai_service.transcription_model = original_model
                    
                logger.error(f"Error from transcription service: {str(e)}")
                logger.error(f"Traceback: {traceback.format_exc()}")
                # Clean up the temporary file
                try:
                    os.remove(temp_file_path)
                except:
                    pass
                raise HTTPException(status_code=500, detail=f"Transcription service error: {str(e)}")
            
            # Clean up the temporary file
            try:
                os.remove(temp_file_path)
                logger.info("Temporary audio file removed")
            except Exception as e:
                logger.error(f"Error removing temporary file: {str(e)}")
            
            if not transcription or not transcription.strip():
                logger.warning("Empty transcription result")
                raise HTTPException(status_code=500, detail="Transcription service returned empty result")
            
            return {"text": transcription}
                
        except HTTPException:
            raise  # Re-raise HTTP exceptions
        except Exception as e:
            logger.error(f"Error processing audio data: {str(e)}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            raise HTTPException(status_code=500, detail=f"Error processing audio: {str(e)}")
            
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Error in transcribe_audio endpoint: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error processing request: {str(e)}")

# Add the database and CRUD imports
from app.db.session import get_db
from app.crud import session as crud_session

# Session-related schemas
class SessionUpdateRequest(BaseModel):
    title: Optional[str] = None
    summary: Optional[str] = None
    user_id: Optional[int] = None

class SessionResponse(BaseModel):
    id: str
    title: str
    summary: Optional[str] = None
    created_at: str
    last_modified: str
    isSynced: bool = True

class MessageRequest(BaseModel):
    content: str
    is_user_message: bool = True
    audio_url: Optional[str] = None

@app.get("/sessions", status_code=status.HTTP_200_OK)
async def get_sessions(db: DBSession = Depends(get_db), user_id: Optional[int] = None):
    """Get all sessions, optionally filtered by user_id"""
    try:
        logger.info(f"Getting sessions for user {user_id if user_id else 'all users'}")
        
        # Get all sessions - for now we use a default user_id (1) if none is provided
        # In a real implementation with auth, you would use the authenticated user's ID
        sessions = crud_session.get_sessions_by_user(db, user_id or 1)
        
        # Convert SQLAlchemy models to response format
        result = []
        for session in sessions:
            result.append({
                "id": str(session.id),
                "title": f"Session {session.id}" if not hasattr(session, 'title') or not session.title else session.title,
                "summary": session.summary or "",
                "created_at": session.start_time.isoformat(),
                "last_modified": session.end_time.isoformat() if session.end_time else session.start_time.isoformat(),
                "isSynced": True
            })
            
        return result
    except Exception as e:
        logger.error(f"Error getting sessions: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error getting sessions: {str(e)}")

@app.post("/sessions", status_code=status.HTTP_201_CREATED, response_model=SessionResponse)
async def create_session(request: SessionUpdateRequest = None, db: DBSession = Depends(get_db)):
    """Create a new session"""
    try:
        logger.info("Creating new session")
        
        # If no request body was provided, create an empty one
        if not request:
            request = SessionUpdateRequest()
        
        # For now, use a default user_id if none was provided
        # In a real implementation, you would get the user_id from the authentication
        user_id = request.user_id if request and request.user_id else 1
        
        # Create session in database
        session = crud_session.create_session(db, user_id=user_id, title=request.title)
        
        # Return the created session in the expected format
        return {
            "id": str(session.id),
            "title": request.title or f"Session {session.id}",
            "summary": session.summary or "",
            "created_at": session.start_time.isoformat(),
            "last_modified": session.start_time.isoformat(),
            "isSynced": True
        }
    except Exception as e:
        logger.error(f"Error creating session: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error creating session: {str(e)}")

@app.get("/sessions/{session_id}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def get_session(session_id: str, db: DBSession = Depends(get_db)):
    """Get a specific session"""
    try:
        logger.info(f"Getting session {session_id}")
        
        # Query the database for the session
        session = crud_session.get_session(db, session_id)
        
        # If session not found, return 404
        if not session:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        
        # Return the session in the expected format
        return {
            "id": str(session.id),
            "title": f"Session {session.id}" if not hasattr(session, 'title') or not session.title else session.title,
            "summary": session.summary or "",
            "created_at": session.start_time.isoformat(),
            "last_modified": session.end_time.isoformat() if session.end_time else session.start_time.isoformat(),
            "isSynced": True
        }
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Error getting session: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error getting session: {str(e)}")

@app.patch("/sessions/{session_id}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def update_session(session_id: str, request: SessionUpdateRequest, db: DBSession = Depends(get_db)):
    """Update a session"""
    try:
        logger.info(f"Updating session {session_id}")
        
        # Build the update data
        update_data = {}
        if request.title is not None:
            update_data["title"] = request.title
        if request.summary is not None:
            update_data["summary"] = request.summary
        
        # Update the session in the database
        session = crud_session.update_session(db, session_id, update_data)
        
        # If session not found, return 404
        if not session:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        
        # Return the updated session
        return {
            "id": str(session.id),
            "title": f"Session {session.id}" if not hasattr(session, 'title') or not session.title else session.title,
            "summary": session.summary or "",
            "created_at": session.start_time.isoformat(),
            "last_modified": session.end_time.isoformat() if session.end_time else session.start_time.isoformat(),
            "isSynced": True
        }
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Error updating session: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error updating session: {str(e)}")

@app.delete("/sessions/{session_id}", status_code=status.HTTP_200_OK)
async def delete_session(session_id: str, db: DBSession = Depends(get_db)):
    """Delete a session"""
    try:
        logger.info(f"Deleting session {session_id}")
        
        # Delete the session from the database
        success = crud_session.delete_session(db, session_id)
        
        # If session not found, return 404
        if not success:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        
        # Return success
        return {"status": "success", "message": f"Session {session_id} deleted"}
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Error deleting session: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error deleting session: {str(e)}")

@app.post("/sessions/{session_id}/messages", status_code=status.HTTP_200_OK)
async def add_session_message(session_id: str, message: MessageRequest, db: DBSession = Depends(get_db)):
    """Add a message to a session"""
    try:
        logger.info(f"Adding message to session {session_id}")
        
        # Check if session exists
        session = crud_session.get_session(db, session_id)
        if not session:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        
        # Add message to database
        msg = crud_session.add_message_to_session(
            db, 
            session_id=session_id,
            content=message.content,
            is_user_message=message.is_user_message,
            audio_url=message.audio_url
        )
        
        # Return success with the message ID
        return {"status": "success", "message_id": str(msg.id)}
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Error adding message: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error adding message: {str(e)}")

@app.post("/sessions/{session_id}/messages/batch", status_code=status.HTTP_200_OK)
async def add_session_messages_batch(session_id: str, messages: List[MessageRequest], db: DBSession = Depends(get_db)):
    """Add multiple messages to a session in a single batch"""
    try:
        logger.info(f"Adding batch of {len(messages)} messages to session {session_id}")
        
        # Check if session exists
        session = crud_session.get_session(db, session_id)
        if not session:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        
        # Convert requests to dict format for the crud function
        message_dicts = []
        for msg in messages:
            message_dicts.append({
                "content": msg.content,
                "is_user_message": msg.is_user_message,
                "audio_url": msg.audio_url
            })
        
        # Add messages to database
        saved_messages = crud_session.add_messages_batch(db, session_id, message_dicts)
        
        # Return success with the message IDs
        message_ids = [str(msg.id) for msg in saved_messages]
        return {
            "status": "success", 
            "message_count": len(saved_messages),
            "message_ids": message_ids
        }
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Error adding batch messages: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Error adding batch messages: {str(e)}")

# Legacy API endpoints with /api/v1 prefix included explicitly
@app.get(f"{settings.API_V1_STR}/sessions", status_code=status.HTTP_200_OK)
async def get_sessions_legacy(db: DBSession = Depends(get_db), user_id: Optional[int] = None):
    """Legacy endpoint for getting all sessions"""
    return await get_sessions(db=db, user_id=user_id)

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

@app.post(f"{settings.API_V1_STR}/sessions/{{session_id}}/messages/batch", status_code=status.HTTP_200_OK)
async def add_session_messages_batch_legacy(session_id: str, messages: List[dict]):
    """Legacy endpoint for adding multiple messages to a session in a single batch"""
    return await add_session_messages_batch(session_id, messages)

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
    """Root endpoint for AI responses using Groq's LLM."""
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
async def root_get_sessions(db: DBSession = Depends(get_db), user_id: Optional[int] = None):
    return await get_sessions(db=db, user_id=user_id)

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

@root_router.post("/sessions/{session_id}/messages/batch")
async def root_add_session_messages_batch(session_id: str, messages: List[dict]):
    return await add_session_messages_batch(session_id, messages)

# Include the root router
app.include_router(root_router)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)