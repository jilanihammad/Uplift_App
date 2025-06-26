import uvicorn
from fastapi import FastAPI, Request, status, HTTPException, APIRouter, UploadFile, File, WebSocket, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
import logging
import os
from fastapi.staticfiles import StaticFiles
from fastapi.openapi.docs import get_swagger_ui_html
from pydantic import BaseModel
import httpx
import uuid
import json
from typing import Optional, List, Dict, Any
from datetime import datetime
import traceback
import base64
import sys
from sqlalchemy.orm import Session as DBSession
from fastapi import Depends

# Database initialization imports
from app.db.base import Base
from app.db.session import engine, get_db

# Create database tables on startup
def init_db():
    try:
        # Try to connect to database first
        from app.core.config import settings
        connection = engine.connect()
        logger.info(f"Successfully connected to database: {settings.SQLALCHEMY_DATABASE_URI}")
        connection.close()
        
        # Create tables
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created successfully")
    except Exception as e:
        logger.error(f"Error connecting to database: {str(e)}")
        logger.error(traceback.format_exc())
        raise  # Re-raise to indicate critical error

# Verify database connection on startup
try:
    # Setup basic logging first
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Initialize database - must happen after logger is created but before app starts
    init_db()
    logger.info("Database initialization successful")
except Exception as e:
    # Setup basic logging first
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    logger.error(f"CRITICAL: Database initialization failed: {str(e)}")
    logger.error("The application will start but database operations will be simulated")

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
        # Remove old LLM-specific settings - now handled by unified LLM manager
        OPENAI_API_KEY=os.environ.get("OPENAI_API_KEY", ""),
        GROQ_API_KEY=os.environ.get("GROQ_API_KEY", ""),
        GROQ_API_BASE_URL=os.environ.get("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1"),
        GROQ_LLM_MODEL_ID=os.environ.get("GROQ_LLM_MODEL_ID", "meta-llama/llama-4-scout-17b-16e-instruct")
        # Removed OPENAI_TTS_MODEL, OPENAI_TTS_VOICE, OPENAI_TRANSCRIPTION_MODEL - now in unified config
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
    logger.info(f"[API] Successfully mounted static files directory: {static_files_path}")
except Exception as e:
    logger.error(f"[API] Error mounting static files: {str(e)}")
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
    """Check if the LLM API is available using unified LLM manager."""
    try:
        # Use unified LLM manager instead of checking individual API keys
        if not llm_manager:
            return {"status": "unavailable", "reason": "Unified LLM manager not available"}
        
        # Get status from unified LLM manager
        status_info = llm_manager.get_status()
        
        return {
            "status": "available" if status_info.get("available_providers") else "unavailable",
            "manager_status": status_info,
            "unified_system": True
        }
    except Exception as e:
        logger.error("Error checking LLM status: %s", str(e))
        return {"status": "unavailable", "reason": str(e)}

class AIRequest(BaseModel):
    message: str
    system_prompt: str = ""
    model: Optional[str] = None
    temperature: float = 0.7
    max_tokens: int = 1000
    history: Optional[List[Dict[str, Any]]] = None

class VoiceRequest(BaseModel):
    text: str
    voice: Optional[str] = None  # No default, config handles it
    model: Optional[str] = None

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

class ChatStreamRequestBody(BaseModel):
    history: List[Dict[str, Any]] # Expects keys like 'role', 'content', 'sequence'
    # You could add other optional parameters here if needed, e.g.,
    # model_config: Optional[Dict[str, Any]] = None

@app.post("/ai/response")
async def ai_response(request: AIRequest):
    """Handle AI response requests using unified LLM manager."""
    try:
        logger.info(f"Received AI response request for message: '{request.message[:50]}...'")
        if request.history:
            logger.info(f"Request includes history with {len(request.history)} messages.")
        else:
            logger.info("Request does not include history.")
        
        # Use unified LLM manager instead of individual services
        if not llm_manager:
            logger.error("Unified LLM manager not available")
            raise HTTPException(status_code=500, detail="LLM service not available")
        
        # Generate response using unified LLM manager
        response_text = await llm_manager.generate_response(
            message=request.message,
            system_prompt=request.system_prompt, 
            context=request.history,
            # Don't pass model - unified LLM manager handles this internally
            temperature=request.temperature,
            max_tokens=request.max_tokens
        )
        
        logger.info("AI response generated successfully using unified LLM manager")
        return {"response": response_text}
            
    except Exception as e:
        logger.error("Error generating AI response: %s", str(e))
        logger.error("Exception traceback: %s", traceback.format_exc())
        
        # Return the actual error instead of a fallback response
        raise HTTPException(status_code=500, detail=f"Error generating AI response: {str(e)}")

@app.post("/therapy/end_session")
async def end_session(request: EndSessionRequest):
    """Generate therapy session summary using unified LLM manager."""
    try:
        logger.info("Received end session request with %d messages", len(request.messages))
        
        # Use unified LLM manager instead of individual services
        if not llm_manager:
            logger.error("Unified LLM manager not available")
            raise HTTPException(status_code=500, detail="LLM service not available")
        
        # Create a comprehensive summarization prompt for better action items
        conversation_text = ""
        user_concerns = []
        therapist_suggestions = []
        
        for msg in request.messages:
            role = "User" if msg.get("isUser", False) else "Therapist"
            content = msg.get('content', '')
            conversation_text += f"{role}: {content}\n\n"
            
            # Extract key themes for better action items
            if msg.get("isUser", False):
                user_concerns.append(content)
            else:
                therapist_suggestions.append(content)

        summary_prompt = f"""Based on this therapy session, provide a comprehensive summary with personalized action items.

THERAPEUTIC APPROACH: {request.therapeutic_approach}

CONVERSATION:
{conversation_text}

{request.memory_context if request.memory_context else ""}

Please analyze this conversation and provide:

1. **SUMMARY**: A compassionate 2-3 sentence summary highlighting the main topics discussed and progress made

2. **ACTION ITEMS**: 3-5 specific, actionable steps tailored to this client's situation. Make these:
   - Specific to what was discussed in this session
   - Realistic and achievable
   - Related to the coping strategies or insights mentioned
   - Personal to the client's expressed concerns

3. **INSIGHTS**: 2-3 observations about patterns, progress, or strengths noticed

IMPORTANT: Respond ONLY with valid JSON in this exact format:
{{
    "summary": "Your compassionate summary here",
    "action_items": [
        "Specific action based on conversation topic 1",
        "Specific action based on conversation topic 2", 
        "Specific action based on conversation topic 3"
    ],
    "insights": [
        "Insight about patterns or progress",
        "Insight about strengths or observations"
    ]
}}"""
        
        try:
            # Get the assistant's response using the LLM manager
            response_text = await llm_manager.generate_response(
                message=summary_prompt,
                context=[],
                system_prompt="You are an expert therapist creating personalized session summaries. Focus on providing actionable, conversation-specific guidance.",
                temperature=0.3,  # Lower temperature for consistency
                max_tokens=1500
            )
            
            # Enhanced JSON parsing with multiple fallback strategies
            try:
                # First, try to extract clean JSON
                json_str = response_text.strip()
                
                # Remove common LLM response prefixes
                prefixes_to_remove = [
                    "Here is the session summary:",
                    "Based on the conversation, here is the summary:",
                    "Here's the session summary:",
                    "Session summary:"
                ]
                
                for prefix in prefixes_to_remove:
                    if json_str.lower().startswith(prefix.lower()):
                        json_str = json_str[len(prefix):].strip()
                
                # Handle markdown code blocks
                if "```json" in json_str:
                    json_str = json_str.split("```json")[1].split("```")[0].strip()
                elif "```" in json_str:
                    json_str = json_str.split("```")[1].strip()
                
                # Find JSON structure using regex if needed
                import re
                if not json_str.startswith('{'):
                    json_match = re.search(r'({[\s\S]*})', json_str)
                    if json_match:
                        json_str = json_match.group(1)
                
                logger.info(f"Attempting to parse JSON from LLM response...")
                
                # Parse the JSON string
                result = json.loads(json_str)
                
                # Validate and clean the result
                result = await _validate_and_clean_summary(result, request.messages)
                
                logger.info("Session summary generated successfully using LLM manager")
                return {
                    "summary": result.get("summary", ""),
                    "action_items": result.get("action_items", []),
                    "insights": result.get("insights", []),
                    "therapeutic_approach": request.therapeutic_approach
                }
                
            except (json.JSONDecodeError, KeyError, ValueError) as e:
                logger.warning(f"Failed to parse LLM response as JSON: {str(e)}")
                logger.warning(f"Raw response: {response_text[:300]}...")
                return await _generate_conversation_based_summary(request.messages, request.therapeutic_approach)
                
        except Exception as llm_error:
            logger.warning(f"Error using LLM manager for session summary: {str(llm_error)}")
            logger.warning("Falling back to conversation-based summary")
            return await _generate_conversation_based_summary(request.messages, request.therapeutic_approach)
            
    except Exception as e:
        logger.error("Error generating session summary: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error generating session summary: {str(e)}")

@app.post("/voice/synthesize")
async def voice_synthesize(request: VoiceRequest):
    try:
        logger.info(f"[API] /voice/synthesize called. Text: '{request.text[:100]}' Voice: {request.voice} Model: {request.model}")
        if not request.text:
            logger.warning("[API] No text provided for TTS")
            raise HTTPException(status_code=400, detail="No text provided for TTS")
            
        # Use unified LLM manager instead of individual services
        if not llm_manager:
            logger.error("Unified LLM manager not available")
            raise HTTPException(status_code=500, detail="LLM service not available")
        
        try:
            logger.info(f"[API] Using unified LLM manager for TTS")
            
            # Accept response_format from request if present (for OPUS/OGG support)
            response_format = getattr(request, 'response_format', None)
            if not response_format:
                # Try to get from request body if sent as dict
                if hasattr(request, 'dict'):
                    response_format = request.dict().get('response_format', None)
            if not response_format:
                response_format = 'mp3'  # Default for backward compatibility

            # Generate speech using unified LLM manager
            audio_data = await llm_manager.text_to_speech(
                text=request.text,
                voice=request.voice,
                response_format=response_format
            )
            
            logger.info(f"[API] TTS generated successfully via unified LLM manager")
            
            if not audio_data:
                logger.error("[API] Failed to generate audio - empty data returned")
                raise HTTPException(status_code=500, detail="Failed to generate audio - empty data returned")
            
            # Return the audio data and format
            logger.info(f"[API] Returning audio data to client (format: {response_format})")
            return {"audio_data": audio_data, "format": response_format}
            
        except Exception as speech_error:
            logger.error(f"[API] Error generating speech: {str(speech_error)}")
            logger.error(traceback.format_exc())
            raise HTTPException(status_code=500, detail=f"Error generating speech: {str(speech_error)}")
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[API] Error in voice_synthesize endpoint: {str(e)}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"TTS error: {str(e)}")

@app.post("/voice/transcribe")
async def transcribe_audio(request: Request):
    """Endpoint to transcribe audio sent as base64 encoded data using unified LLM manager."""
    try:
        # Get the request body as JSON
        json_data = await request.json()
        audio_data = json_data.get("audio_data")
        audio_format = json_data.get("audio_format", "aac")  # Default to aac if not specified
        # Model selection is now handled by unified LLM manager
        requested_model = json_data.get("model")  # Optional override
        
        logger.info(f"Received transcription request. Format: {audio_format}, Model: {requested_model or 'default'}")
        
        # Check if audio data was provided
        if not audio_data:
            logger.warning("No audio data provided for transcription")
            raise HTTPException(status_code=400, detail="No audio data provided")
        
        # Log the size of the received audio data
        audio_data_length = len(audio_data) if audio_data else 0
        logger.info(f"Audio data received: {audio_data_length} characters")
        
        # Use unified LLM manager instead of individual services
        if not llm_manager:
            logger.error("Unified LLM manager not available")
            raise HTTPException(status_code=500, detail="LLM service not available")
        
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
            
            # Transcribe the audio using unified LLM manager
            logger.info(f"Calling unified LLM manager transcription service")
            try:
                # Don't pass model parameter - unified LLM manager handles this internally
                transcription = await llm_manager.transcribe_audio(temp_file_path)
                logger.info(f"Transcription service returned: '{transcription}'")
                    
            except Exception as e:
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

@app.post("/voice/transcribe_file")
async def transcribe_file(file: UploadFile = File(...)):
    """Transcribe uploaded audio file using unified LLM manager."""
    import tempfile, os
    
    # Use unified LLM manager instead of individual services
    if not llm_manager:
        logger.error("Unified LLM manager not available")
        raise HTTPException(status_code=500, detail="LLM service not available")
    
    temp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp3")
    temp.write(await file.read())
    temp.close()
    
    try:
        transcription = await llm_manager.transcribe_audio(temp.name)
        return {"text": transcription}
    finally:
        os.remove(temp.name)

# Add the database and CRUD imports
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
    sequence: Optional[int] = None

@app.get("/sessions", status_code=status.HTTP_200_OK)
async def get_sessions(db: DBSession = Depends(get_db), user_id: Optional[int] = None):
    """Get all sessions, optionally filtered by user_id"""
    try:
        logger.info(f"Getting sessions for user {user_id if user_id else 'DEFAULT'}")
        
        # IMPORTANT: In production, this would use JWT tokens for authentication
        # For now, we use a default user_id (1) if none is provided
        effective_user_id = user_id or 1
        logger.info(f"Using effective user_id: {effective_user_id} for fetching sessions")
        
        try:
            # Try to get sessions from database first
            sessions = crud_session.get_sessions_by_user(db, effective_user_id)
            logger.info(f"Database query returned {len(sessions)} sessions for user {effective_user_id}")
            
            # If no sessions found, create default starter sessions
            if not sessions:
                logger.info(f"No sessions found for user {effective_user_id}, creating default sessions")
                try:
                    # Create default sessions
                    session1 = crud_session.create_session(db, user_id=effective_user_id, title="Your First Session")
                    session2 = crud_session.create_session(db, user_id=effective_user_id, title="Your Follow-up Session")
                    
                    # Update with summaries
                    crud_session.update_session(db, session1.id, {
                        "summary": "Welcome to your therapy journey. This is where your completed sessions will appear."
                    })
                    crud_session.update_session(db, session2.id, {
                        "summary": "Regular sessions help build progress. Complete another session to see it here."
                    })
                    
                    # Get the sessions again
                    sessions = [session1, session2]
                    logger.info(f"Created {len(sessions)} default sessions for user {effective_user_id}")
                except Exception as create_error:
                    logger.error(f"Error creating default sessions: {str(create_error)}")
                    logger.error(traceback.format_exc())
                    # If we can't create sessions, return mock data
                    logger.warning("Falling back to mock data due to database error")
                    now = datetime.now().isoformat()
                    return [
                        {
                            "id": str(uuid.uuid4()),
                            "title": "First Therapy Session",
                            "summary": "Welcome to your therapy journey. This is where your completed sessions will appear.",
                            "created_at": now,
                            "last_modified": now,
                            "isSynced": True
                        },
                        {
                            "id": str(uuid.uuid4()),
                            "title": "Follow-up Session",
                            "summary": "Regular sessions help build progress. Complete another session to see it here.",
                            "created_at": now,
                            "last_modified": now,
                            "isSynced": True
                        }
                    ]
        except Exception as db_error:
            logger.error(f"Database error fetching sessions: {str(db_error)}")
            logger.error(traceback.format_exc())
            # If database operations fail, return mock data as fallback
            logger.warning("Falling back to mock data due to database error")
            now = datetime.now().isoformat()
            return [
                {
                    "id": str(uuid.uuid4()),
                    "title": "First Therapy Session",
                    "summary": "Database connectivity issue. Please try again later.",
                    "created_at": now,
                    "last_modified": now,
                    "isSynced": True
                },
                {
                    "id": str(uuid.uuid4()),
                    "title": "Support",
                    "summary": "If issues persist, please contact support.",
                    "created_at": now,
                    "last_modified": now,
                    "isSynced": True
                }
            ]
        
        # Convert SQLAlchemy models to response format
        result = []
        for session in sessions:
            # Add detailed logging for each session
            logger.info(f"Processing session: id={session.id}, title={session.title}")
            result.append({
                "id": str(session.id),
                "title": session.title or f"Session {session.id}",
                "summary": session.summary or "No summary available",
                "created_at": session.start_time.isoformat(),
                "last_modified": session.end_time.isoformat() if session.end_time else session.start_time.isoformat(),
                "isSynced": True
            })
            
        return result
    except Exception as e:
        logger.error(f"Unhandled error in get_sessions: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        # Return a user-friendly error response
        now = datetime.now().isoformat()
        return [
            {
                "id": str(uuid.uuid4()),
                "title": "Service Temporarily Unavailable",
                "summary": "We're experiencing technical difficulties. Please try again later.",
                "created_at": now,
                "last_modified": now,
                "isSynced": True
            }
        ]

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
        logger.info(f"Creating session for user_id: {user_id}")
        
        # Create session in database
        session = crud_session.create_session(db, user_id=user_id, title=request.title)
        logger.info(f"Session created in database: id={session.id}, title={session.title}")
        
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
        logger.info(f"Updating session {session_id} with data: {request}")
        
        # Build the update data
        update_data = {}
        if request.title is not None:
            update_data["title"] = request.title
        if request.summary is not None:
            update_data["summary"] = request.summary
        
        logger.info(f"Update data: {update_data}")
        
        try:
            # Update the session in the database
            session = crud_session.update_session(db, session_id, update_data)
            
            # If session not found, try to create it
            if not session:
                logger.warning(f"Session {session_id} not found, attempting to create it")
                user_id = request.user_id or 1  # Use default user_id if not provided
                
                # Create a new session with the provided ID and data
                session = crud_session.create_session(db, user_id=user_id, title=request.title)
                
                # Update the session if summary is provided
                if request.summary:
                    session = crud_session.update_session(db, session.id, {"summary": request.summary})
                
                logger.info(f"Created new session {session.id} as fallback")
            
            # Return the updated session
            response = {
                "id": str(session.id),
                "title": session.title or f"Session {session.id}",
                "summary": session.summary or "",
                "created_at": session.start_time.isoformat(),
                "last_modified": session.end_time.isoformat() if session.end_time else session.start_time.isoformat(),
                "isSynced": True
            }
            
            logger.info(f"Successfully updated session {session_id}")
            return response
        except Exception as db_error:
            logger.error(f"Database error updating session: {str(db_error)}")
            logger.error(traceback.format_exc())
            
            # Return a mock response as fallback
            now = datetime.now().isoformat()
            return {
                "id": session_id,
                "title": request.title or f"Session {session_id}",
                "summary": request.summary or "No summary available",
                "created_at": now,
                "last_modified": now,
                "isSynced": True
            }
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        logger.error(f"Unexpected error updating session: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Return a response rather than an error for better user experience
        now = datetime.now().isoformat()
        return {
            "id": session_id,
            "title": request.title or f"Session {session_id}",
            "summary": request.summary or "Error saving session, please try again",
            "created_at": now,
            "last_modified": now,
            "isSynced": True
        }

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
            audio_url=message.audio_url,
            sequence=message.sequence
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
                "audio_url": msg.audio_url,
                "sequence": msg.sequence
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
    """Root endpoint for text-to-speech requests."""
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

# API version routing - include routers with proper error handling
try:
    from app.api.api_v1.api import api_router
    app.include_router(api_router, prefix=settings.API_V1_STR)
    logger.info(f"Successfully mounted API router at {settings.API_V1_STR}")
except Exception as e:
    logger.error(f"Failed to mount API router: {str(e)}")
    fallback_app = True

# Include voice router at root level for backward compatibility
try:
    from app.api.endpoints import voice
    app.include_router(voice.router, prefix="/voice", tags=["voice"])
    logger.info("Successfully mounted voice router at /voice")
except Exception as e:
    logger.error(f"Failed to mount voice router: {str(e)}")
    fallback_app = True

# Replace old service imports with unified LLM manager
try:
    from app.services.llm_manager import llm_manager
    logger.info("Successfully imported unified LLM manager")
except Exception as e:
    logger.warning(f"Error importing unified LLM manager: {str(e)}")
    llm_manager = None

@app.get("/debug/env")
def debug_env():
    return {
        "OPENAI_API_KEY": os.environ.get("OPENAI_API_KEY"),
        "GROQ_API_KEY": os.environ.get("GROQ_API_KEY"),
        "GOOGLE_API_KEY": os.environ.get("GOOGLE_API_KEY"),
        "ACTIVE_LLM_PROVIDER": os.environ.get("ACTIVE_LLM_PROVIDER"),
        "ACTIVE_TTS_PROVIDER": os.environ.get("ACTIVE_TTS_PROVIDER"),
        "ACTIVE_TRANSCRIPTION_PROVIDER": os.environ.get("ACTIVE_TRANSCRIPTION_PROVIDER"),
    }

@app.post("/sessions/{session_id}/chat_stream")
async def stream_chat_from_llm(
    session_id: str,
    request_data: ChatStreamRequestBody,
):
    """
    Streams chat completions from the LLM for a given session.
    Expects a 'history' in the request body, where each message has 'role', 'content', and 'sequence'.
    The history should include the latest user message.
    """
    if not llm_manager:
        logger.error("LLM Manager not available for streaming chat.")
        raise HTTPException(status_code=500, detail="LLM service not configured or unavailable.")

    try:
        logger.info(f"Received chat stream request for session_id: {session_id} with {len(request_data.history)} messages in history.")
        
        # --- System Prompt ---
        # You'll need to decide how to get the system prompt.
        # It could be a default, or loaded based on session_id or user settings.
        # For now, let's use a generic one. Replace with your actual logic.
        system_prompt_for_session = "You are Maya, a caring and empathetic AI therapist. Respond naturally and supportively."
        # Example: Fetch from DB:
        # session_settings = crud_session.get_session_settings(db, session_id)
        # system_prompt_for_session = session_settings.system_prompt if session_settings else "Default prompt"

        # The history from request_data.history should already be in the format
        # that stream_google_chat_completion expects: List[Dict[str, str]]
        # with 'role' and 'content'. Ensure 'sequence' is also there if your llm_manager uses it.
        # The llm_manager.stream_google_chat_completion handles mapping this to Gemini's format.
        
        if not request_data.history:
            raise HTTPException(status_code=400, detail="Chat history cannot be empty.")

        # --- LLM Parameters ---
        # You can make these configurable or pass them from the request if needed
        llm_params = {
            "temperature": 0.7, # Example
            # "top_p": 1.0,
            # "max_tokens": 1000 # Gemini SDK usually handles this with its own limits/defaults for stream
        }

        # Log the history being sent to the LLM for debugging
        # logger.debug(f"History being sent to LLM for session {session_id}: {json.dumps(request_data.history, indent=2)}")

        # Extract the latest user message and context
        latest_message = request_data.history[-1].get("content", "") if request_data.history else ""
        context = request_data.history[:-1] if len(request_data.history) > 1 else []
        
        # Create async generator function for streaming
        async def text_stream():
            async for chunk in llm_manager.stream_chat_completion(
                message=latest_message,
                context=context,
                system_prompt=system_prompt_for_session,
                temperature=llm_params.get("temperature", 0.7)
            ):
                yield chunk
        
        return StreamingResponse(text_stream(), media_type="text/plain; charset=utf-8")

    except HTTPException as e:
        logger.error(f"HTTPException in stream_chat_from_llm for session {session_id}: {e.detail}")
        raise e
    except Exception as e:
        logger.error(f"Error in stream_chat_from_llm for session {session_id}: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"An error occurred while streaming the chat response: {str(e)}")

async def _validate_and_clean_summary(result: Dict[str, Any], messages: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Validate and clean the summary result, ensuring quality action items."""
    
    # Ensure result is a dictionary
    if not isinstance(result, dict):
        raise ValueError("Response is not a dictionary")
    
    # Validate summary
    if not result.get("summary") or len(result["summary"].strip()) < 20:
        result["summary"] = "Thank you for sharing your thoughts and feelings in this session. We explored important topics together."
    
    # Validate and improve action items
    action_items = result.get("action_items", [])
    if not action_items or len(action_items) == 0:
        # Generate basic action items based on conversation
        action_items = await _generate_basic_action_items(messages)
    else:
        # Clean existing action items
        cleaned_items = []
        for item in action_items:
            if isinstance(item, str) and len(item.strip()) > 10:
                cleaned_items.append(item.strip())
        
        if len(cleaned_items) < 2:
            # Add some basic items if we don't have enough
            basic_items = await _generate_basic_action_items(messages)
            cleaned_items.extend(basic_items[:3])
        
        action_items = cleaned_items[:5]  # Limit to 5 items
    
    result["action_items"] = action_items
    
    # Validate insights
    insights = result.get("insights", [])
    if not insights:
        insights = [
            "You showed courage by sharing your experiences today",
            "Your self-awareness is a valuable strength"
        ]
    
    result["insights"] = insights
    
    return result

async def _generate_basic_action_items(messages: List[Dict[str, Any]]) -> List[str]:
    """Generate basic action items based on conversation content."""
    
    # Extract keywords from user messages to create relevant action items
    user_messages = [msg.get('content', '').lower() for msg in messages if msg.get("isUser", False)]
    conversation_text = ' '.join(user_messages)
    
    action_items = []
    
    # Keyword-based action item suggestions
    if any(word in conversation_text for word in ['stress', 'anxious', 'worry', 'overwhelmed']):
        action_items.append("Practice deep breathing exercises when feeling stressed or anxious")
    
    if any(word in conversation_text for word in ['sleep', 'tired', 'exhausted']):
        action_items.append("Focus on improving your sleep routine and getting adequate rest")
    
    if any(word in conversation_text for word in ['relationship', 'family', 'friends', 'partner']):
        action_items.append("Consider having an open conversation with someone you trust")
    
    if any(word in conversation_text for word in ['work', 'job', 'career']):
        action_items.append("Take regular breaks during work to maintain balance")
    
    if any(word in conversation_text for word in ['exercise', 'physical', 'activity']):
        action_items.append("Incorporate some physical activity into your daily routine")
    
    # Add default items if we don't have enough specific ones
    default_items = [
        "Take time for self-reflection and journaling",
        "Practice mindfulness or meditation for a few minutes daily",
        "Engage in one activity that brings you joy this week",
        "Be kind and patient with yourself as you work through challenges"
    ]
    
    # Combine and ensure we have 3-4 items
    all_items = action_items + default_items
    return list(dict.fromkeys(all_items))[:4]  # Remove duplicates and limit to 4

async def _generate_conversation_based_summary(messages: List[Dict[str, Any]], therapeutic_approach: str) -> Dict[str, Any]:
    """Generate a fallback summary based on conversation analysis."""
    
    logger.info("Generating conversation-based fallback summary")
    
    # Basic conversation analysis
    user_message_count = len([msg for msg in messages if msg.get("isUser", False)])
    therapist_message_count = len([msg for msg in messages if not msg.get("isUser", False)])
    
    # Generate summary based on conversation length and content
    if user_message_count > 5:
        summary = "Thank you for sharing so openly in today's session. We covered several important topics and explored different perspectives together."
    else:
        summary = "Thank you for taking the time to connect today. Even brief conversations can provide valuable insights."
    
    # Generate action items based on conversation
    action_items = await _generate_basic_action_items(messages)
    
    insights = [
        f"You engaged thoughtfully in our conversation today",
        "Your willingness to explore these topics shows strength and self-awareness"
    ]
    
    return {
        "summary": summary,
        "action_items": action_items,
        "insights": insights
    }

# Add WebSocket endpoints at root level (without /voice prefix) for direct access
@app.websocket("/ws/tts/speech")
async def root_websocket_streaming_tts(
    websocket: WebSocket,
    token: str = Query(..., description="JWT authentication token"),
    conversation_id: str = Query(..., description="Unique conversation identifier"),
    voice: str = Query(default="sage", description="TTS voice to use"),
    format: str = Query(default="wav", description="Audio format (wav for lowest latency)")
):
    """Root-level WebSocket endpoint for streaming TTS"""
    try:
        # Import the websocket function from voice module
        from app.api.endpoints.voice import websocket_streaming_tts
        return await websocket_streaming_tts(websocket, token, conversation_id, voice, format)
    except Exception as e:
        logger.error(f"Root WebSocket TTS error: {str(e)}")
        try:
            await websocket.close(code=1011, reason="Internal server error")
        except:
            pass

@app.websocket("/ws/tts")
async def root_websocket_tts(websocket: WebSocket):
    """Root-level WebSocket endpoint for basic TTS"""
    try:
        # Import the websocket function from voice module
        from app.api.endpoints.voice import websocket_tts
        return await websocket_tts(websocket)
    except Exception as e:
        logger.error(f"Root WebSocket basic TTS error: {str(e)}")
        try:
            await websocket.close(code=1011, reason="Internal server error")
        except:
            pass

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)