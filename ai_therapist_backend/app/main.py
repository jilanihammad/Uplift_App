# Load environment variables first, before any other imports
from dotenv import load_dotenv
load_dotenv(".env.dev", override=False)  # Try .env.dev first
load_dotenv(".env", override=False)      # Fallback to .env

import uvicorn
from fastapi import FastAPI, Request, status, HTTPException, APIRouter, UploadFile, File, WebSocket, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from contextlib import asynccontextmanager
import logging
import os
import io
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
import uuid
import json
from typing import Optional, List, Dict, Any
from datetime import datetime
from app.core.datetime_utils import serialize_datetime, utcnow_isoformat
import traceback
import base64
from sqlalchemy.orm import Session as DBSession
from fastapi import Depends
from app.api.deps.auth import AuthenticatedUser, get_current_user

# Database initialization imports
from app.db.session import get_db

# Setup enhanced logging (single source of truth)
from app.core.enhanced_logging import setup_logging, get_logger
setup_logging()
logger = get_logger(__name__)

# Core imports -- fail loudly if any are missing
from app.api.api_v1.api import api_router
from app.core.config import settings
from app.core.rate_limiter import RateLimitMiddleware
from app.core.security_middleware import SecurityMiddleware
from app.core.health import get_health_status
from app.services.llm_manager import llm_manager, _groq_stt_client

logger.info("Starting AI Therapist Backend")
logger.info(f"Environment: {os.environ.get('ENVIRONMENT', 'development')}")
logger.info(f"PORT: {os.environ.get('PORT', '8080')}")


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan handler for container warm-up and cleanup."""
    # --- Startup ---
    logger.info("Starting container warm-up on application startup")

    # Check OpenAI SDK version
    try:
        import openai
        from packaging import version

        logger.info(f"OpenAI SDK version: {openai.__version__}")
        if version.parse(openai.__version__) < version.parse("1.85.0"):
            error_msg = f"OpenAI SDK >= 1.85.0 required for TTS streaming; found {openai.__version__}"
            logger.error(error_msg)
            raise RuntimeError(error_msg)
        logger.info(f"OpenAI SDK version {openai.__version__} is compatible with TTS streaming")
    except ImportError:
        logger.warning("OpenAI SDK not installed - TTS features will be unavailable")

    # Initialize observability system
    try:
        from app.core.observability import observability_manager
        await observability_manager.start()
        logger.info("Observability system started successfully")
    except Exception as e:
        logger.warning(f"Failed to start observability system: {str(e)}")

    # Container warm-up
    try:
        from app.core.container_warmup import quick_warmup
        warmup_result = await quick_warmup()
        logger.info(f"Container warm-up completed: {warmup_result.get('successful_stages', 0)}/{warmup_result.get('total_stages', 0)} stages successful")
    except Exception as e:
        logger.warning(f"Container warm-up failed, continuing startup: {str(e)}")

    yield

    # --- Shutdown ---
    logger.info("Shutting down HTTP clients and connections")
    try:
        from app.core.http_client_manager import get_http_client_manager
        http_manager = get_http_client_manager()
        await http_manager.stop_all_clients()
        logger.info("HTTP clients shut down successfully")
    except Exception as e:
        logger.warning(f"Error during HTTP client shutdown: {str(e)}")

    try:
        from app.core.observability import observability_manager
        await observability_manager.stop()
        logger.info("Observability system shut down successfully")
    except Exception as e:
        logger.warning(f"Error during observability shutdown: {str(e)}")


# ---------------------------------------------------------------------------
# App creation & middleware
# ---------------------------------------------------------------------------

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="AI Therapist API for mental health support",
    version="1.0.0",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=None,
    redoc_url=None,
    lifespan=lifespan
)

# Middleware (order matters)
try:
    from app.core.request_middleware import RequestTracingMiddleware
    app.add_middleware(RequestTracingMiddleware)
    app.add_middleware(SecurityMiddleware)
    app.add_middleware(RateLimitMiddleware, requests_per_minute=60)
    logger.info("Successfully added all middleware")
except Exception as e:
    logger.error(f"Error adding middleware: {str(e)}")
    logger.warning("Continuing without middleware - limited functionality")

if settings.BACKEND_CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=(
            ["*"] if settings.BACKEND_CORS_ORIGINS == ["*"]
            else [str(origin) for origin in settings.BACKEND_CORS_ORIGINS]
        ),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# Include API router
app.include_router(api_router, prefix=settings.API_V1_STR)


# ---------------------------------------------------------------------------
# Global exception handler
# ---------------------------------------------------------------------------

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "An unexpected error occurred"},
    )


# ---------------------------------------------------------------------------
# Static files for audio
# ---------------------------------------------------------------------------

if os.environ.get("GOOGLE_CLOUD") == "1":
    logger.info("Running in Cloud Run, using cloud-friendly static file handling")
    static_files_path = "/tmp/static/audio"
else:
    static_files_path = "static/audio"

os.makedirs(static_files_path, exist_ok=True)
logger.info(f"Using static files path: {static_files_path}")

try:
    app.mount("/audio", StaticFiles(directory=static_files_path), name="audio")
    logger.info(f"[API] Successfully mounted static files directory: {static_files_path}")
except Exception as e:
    logger.error(f"[API] Error mounting static files: {str(e)}")


# ---------------------------------------------------------------------------
# Core endpoints
# ---------------------------------------------------------------------------

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


@app.get("/performance")
def performance_report():
    """Performance monitoring endpoint for optimization tracking."""
    try:
        from app.core.performance_monitor import get_performance_report
        from app.core.http_client_manager import get_http_client_manager

        performance_data = get_performance_report()
        http_manager = get_http_client_manager()
        http_health = http_manager.get_health_status()

        return {
            "status": "ok",
            "timestamp": datetime.now().isoformat(),
            "performance_metrics": performance_data,
            "http_client_health": http_health,
            "optimization_notes": {
                "http2_enabled": "HTTP/2 enabled for OpenAI, Anthropic, Groq, Google",
                "connection_pooling": "Per-provider connection pooling active",
                "dns_caching": "DNS cache TTL: 300s",
                "container_warmup": "Quick warmup on cold start (30s timeout)",
                "openai_tts_streaming": f"New streaming API: {settings.OPENAI_TTS_STREAM} (150-300ms TTFB vs 700-1200ms)"
            }
        }
    except Exception as e:
        logger.error(f"Error in performance endpoint: {str(e)}")
        return {"status": "error", "timestamp": datetime.now().isoformat(), "error": str(e)}


@app.get("/metrics")
def metrics_endpoint():
    """Real-time performance metrics endpoint for TTFB tracking."""
    try:
        from app.core.observability import observability_manager
        metrics_summary = observability_manager.get_health_status()
        return {
            "status": "ok",
            "timestamp": datetime.now().isoformat(),
            "metrics": metrics_summary.get("metrics_summary", {}),
            "critical_metrics": {
                "description": "Key latency metrics for Phase 0 baseline",
                "targets": {
                    "llm_chat_ttfb_ms": {"target": "<500ms", "p95_target": "<1000ms"},
                    "tts_first_byte_ms": {"target": "<300ms", "p95_target": "<500ms"},
                    "provider_error_rate": {"target": "<5%", "p95_target": "<10%"}
                }
            },
            "phase_0_status": {"baseline_metrics_implemented": True, "ready_for_phase_1": True},
            "phase_1_status": {"http_client_hotrodding_implemented": True, "connection_prewarming_active": True, "ready_for_phase_2": True}
        }
    except Exception as e:
        logger.error(f"Error in metrics endpoint: {str(e)}")
        return {"status": "error", "timestamp": datetime.now().isoformat(), "error": str(e)}


# ---------------------------------------------------------------------------
# LLM / AI endpoints
# ---------------------------------------------------------------------------

@app.get(f"{settings.API_V1_STR}/llm/status")
async def llm_status():
    """Check if the LLM API is available using unified LLM manager."""
    try:
        if not llm_manager:
            return {"status": "unavailable", "reason": "Unified LLM manager not available"}
        status_info = llm_manager.get_status()
        return {
            "status": "available" if status_info.get("available_providers") else "unavailable",
            "manager_status": status_info,
            "unified_system": True
        }
    except Exception as e:
        logger.error("Error checking LLM status: %s", str(e))
        return {"status": "unavailable", "reason": str(e)}


# ---------------------------------------------------------------------------
# Request/response models
# ---------------------------------------------------------------------------

class AIRequest(BaseModel):
    message: str
    system_prompt: str = ""
    model: Optional[str] = None
    temperature: float = 0.7
    max_tokens: int = 1000
    history: Optional[List[Dict[str, Any]]] = None

class VoiceRequest(BaseModel):
    text: str
    voice: Optional[str] = None
    model: Optional[str] = None

class TranscriptionRequest(BaseModel):
    audio_url: Optional[str] = None
    audio_data: Optional[str] = None
    audio_format: Optional[str] = "mp3"
    model: Optional[str] = None

class EndSessionRequest(BaseModel):
    messages: list
    system_prompt: str = ""
    memory_context: str = ""
    therapeutic_approach: str = "supportive"
    visited_nodes: list = []
    session_title: Optional[str] = None
    user_id: Optional[int] = None

class ChatStreamRequestBody(BaseModel):
    history: List[Dict[str, Any]]


# ---------------------------------------------------------------------------
# /ai/response
# ---------------------------------------------------------------------------

@app.post("/ai/response")
async def ai_response(request: AIRequest):
    """Handle AI response requests using unified LLM manager."""
    try:
        logger.info(f"Received AI response request for message: '{request.message[:50]}...'")
        if request.history:
            logger.info(f"Request includes history with {len(request.history)} messages.")
        else:
            logger.info("Request does not include history.")

        if not llm_manager:
            raise HTTPException(status_code=500, detail="LLM service not available")

        response_text = await llm_manager.generate_response(
            message=request.message,
            system_prompt=request.system_prompt,
            context=request.history,
            temperature=request.temperature,
            max_tokens=request.max_tokens
        )
        logger.info("AI response generated successfully using unified LLM manager")
        return {"response": response_text}
    except Exception as e:
        logger.error("Error generating AI response: %s", str(e))
        logger.error("Exception traceback: %s", traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Error generating AI response: {str(e)}")


# ---------------------------------------------------------------------------
# /therapy/end_session
# ---------------------------------------------------------------------------

@app.post("/therapy/end_session")
async def end_session(
    request: EndSessionRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db)
):
    """Generate therapy session summary and create session record with rich data."""
    try:
        logger.info("Received end session request with %d messages", len(request.messages))

        if not llm_manager:
            raise HTTPException(status_code=500, detail="LLM service not available")

        from app.services.profile_service import get_profile
        user_id = current_user.user.id
        preferred_name = None
        profile = get_profile(db, user_id=user_id)
        if profile:
            preferred_name = profile.preferred_name
        display_name = preferred_name if preferred_name else "you"

        conversation_text = ""
        for msg in request.messages:
            role = display_name.capitalize() if msg.get("isUser", False) else "Maya"
            content = msg.get('content', '')
            conversation_text += f"{role}: {content}\n\n"

        summary_prompt = f"""Based on this conversation with Maya (an AI companion), provide a comprehensive summary with personalized action items for {display_name}.

THERAPEUTIC APPROACH: {request.therapeutic_approach}

CONVERSATION:
{conversation_text}

{request.memory_context if request.memory_context else ""}

Please analyze this conversation and provide:

1. **SUMMARY**: A compassionate 2-3 sentence summary highlighting the main topics discussed and progress made. Address {display_name} directly using "you" language.

2. **ACTION ITEMS**: 3-5 specific, actionable steps tailored to what {display_name} discussed in this session. Make these:
   - Specific to what was discussed in this session
   - Realistic and achievable
   - Related to the coping strategies or insights mentioned
   - Personal and supportive in tone

3. **INSIGHTS**: 2-3 observations about patterns, progress, or strengths noticed

IMPORTANT:
- Refer to the AI companion as "Maya" (never "therapist" or "I")
- Address {display_name} directly using "you" language (never "the client" or "the user")
- Keep tone warm, supportive, and conversational

RESPOND ONLY with valid JSON in this exact format:
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
            response_text = await llm_manager.generate_response(
                message=summary_prompt,
                context=[],
                system_prompt="You are a compassionate AI assistant creating personalized conversation summaries for Maya, an AI companion app. Focus on providing actionable, conversation-specific guidance while maintaining a warm, supportive tone. Never refer to Maya as a therapist or the user as a client.",
                temperature=0.3,
                max_tokens=1500
            )

            try:
                json_str = response_text.strip()
                prefixes_to_remove = [
                    "Here is the session summary:",
                    "Based on the conversation, here is the summary:",
                    "Here's the session summary:",
                    "Session summary:"
                ]
                for prefix in prefixes_to_remove:
                    if json_str.lower().startswith(prefix.lower()):
                        json_str = json_str[len(prefix):].strip()

                if "```json" in json_str:
                    json_str = json_str.split("```json")[1].split("```")[0].strip()
                elif "```" in json_str:
                    json_str = json_str.split("```")[1].strip()

                import re
                if not json_str.startswith('{'):
                    json_match = re.search(r'({[\s\S]*})', json_str)
                    if json_match:
                        json_str = json_match.group(1)

                result = json.loads(json_str)
                result = await _validate_and_clean_summary(result, request.messages, display_name)

                session_id = await _create_session_with_summary(db=db, summary_data=result, request=request)

                return {
                    "id": session_id,
                    "summary": result.get("summary", ""),
                    "action_items": result.get("action_items", []),
                    "insights": result.get("insights", []),
                    "therapeutic_approach": request.therapeutic_approach
                }

            except (json.JSONDecodeError, KeyError, ValueError) as e:
                logger.warning(f"Failed to parse LLM response as JSON: {str(e)}")
                fallback_summary = await _generate_conversation_based_summary(
                    request.messages, request.therapeutic_approach,
                    user_id=current_user.user.id, db=db
                )
                session_id = await _create_session_with_summary(db=db, summary_data=fallback_summary, request=request)
                fallback_summary["id"] = session_id
                return fallback_summary

        except Exception as llm_error:
            logger.warning(f"Error using LLM manager for session summary: {str(llm_error)}")
            fallback_summary = await _generate_conversation_based_summary(
                request.messages, request.therapeutic_approach,
                user_id=current_user.user.id, db=db
            )
            session_id = await _create_session_with_summary(db=db, summary_data=fallback_summary, request=request)
            fallback_summary["id"] = session_id
            return fallback_summary

    except Exception as e:
        logger.error("Error generating session summary: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error generating session summary: {str(e)}")


# ---------------------------------------------------------------------------
# /voice/synthesize
# ---------------------------------------------------------------------------

@app.post("/voice/synthesize")
async def voice_synthesize(request: VoiceRequest):
    try:
        import time
        from app.core.observability import record_latency, record_counter

        # Phase 3: TTS Fast-Path Optimization
        phase3_enabled = os.getenv("PHASE3_TTS_OPTIMIZATION", "true").lower() == "true"

        if phase3_enabled:
            try:
                from app.services.tts_optimizer import route_tts_request_fast_path, RequestPriority

                request_start_time = time.time()
                logger.info(f"[API-Phase3] /voice/synthesize called. Text: '{request.text[:100]}' Voice: {request.voice}")

                if not request.text:
                    raise HTTPException(status_code=400, detail="No text provided for TTS")

                priority = RequestPriority.NORMAL
                if len(request.text) < 20:
                    priority = RequestPriority.HIGH
                elif len(request.text) > 200:
                    priority = RequestPriority.LOW

                audio_data, metadata = await route_tts_request_fast_path(
                    text=request.text, voice=request.voice, model=request.model, priority=priority
                )

                total_time_ms = (time.time() - request_start_time) * 1000
                ttfb_ms = metadata.get("processing_time_ms", total_time_ms)

                record_latency("tts_phase3", "total_time", total_time_ms, {
                    "provider": metadata.get("provider_used", "unknown"),
                    "strategy": metadata.get("fast_path_strategy", "unknown"),
                    "priority": priority.value
                })
                record_latency("tts_phase3", "first_byte", ttfb_ms, {
                    "provider": metadata.get("provider_used", "unknown"),
                    "optimization": metadata.get("optimization_level", "unknown")
                })
                record_counter("tts_phase3", "requests_total", labels={
                    "provider": metadata.get("provider_used", "unknown"),
                    "strategy": metadata.get("fast_path_strategy", "unknown")
                })

                logger.info(f"Phase 3 TTS completed: {ttfb_ms:.1f}ms TTFB, {total_time_ms:.1f}ms total")

                return StreamingResponse(
                    io.BytesIO(audio_data),
                    media_type="audio/mpeg",
                    headers={
                        "X-TTS-Provider": metadata.get("provider_used", "unknown"),
                        "X-Processing-Time": str(round(ttfb_ms, 1)),
                        "X-Fast-Path-Strategy": metadata.get("fast_path_strategy", "unknown"),
                        "X-Phase": "3",
                        "X-Optimization-Level": metadata.get("optimization_level", "unknown")
                    }
                )

            except Exception as phase3_error:
                logger.warning(f"Phase 3 TTS failed, falling back to legacy: {phase3_error}")

        # Legacy TTS implementation
        request_start_time = time.time()
        logger.info(f"[API-Legacy] /voice/synthesize called. Text: '{request.text[:100]}' Voice: {request.voice}")
        if not request.text:
            raise HTTPException(status_code=400, detail="No text provided for TTS")

        if not llm_manager:
            raise HTTPException(status_code=500, detail="LLM service not available")

        response_format = getattr(request, 'response_format', None)
        if not response_format:
            if hasattr(request, 'dict'):
                response_format = request.dict().get('response_format', None)
        if not response_format:
            response_format = 'mp3'

        first_chunk_received = False
        audio_chunks = []
        async for chunk in llm_manager.stream_text_to_speech(
            text=request.text, voice=request.voice, response_format=response_format
        ):
            if not first_chunk_received:
                ttfb_ms = (time.time() - request_start_time) * 1000
                record_latency("tts", "first_byte", ttfb_ms, {"provider": os.environ.get("ACTIVE_TTS_PROVIDER", "unknown")})
                record_counter("tts", "requests_total", labels={"provider": os.environ.get("ACTIVE_TTS_PROVIDER", "unknown")})
                logger.info(f"TTS TTFB: {ttfb_ms:.1f}ms for text length {len(request.text)}")
                first_chunk_received = True
            audio_chunks.append(chunk)

        combined_audio = base64.b64encode(base64.b64decode(''.join(audio_chunks))).decode('utf-8')

        if not combined_audio:
            raise HTTPException(status_code=500, detail="Failed to generate audio - empty data returned")

        logger.info(f"[API] Returning audio data to client (format: {response_format})")
        return {"audio_data": combined_audio, "format": response_format}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[API] Error in voice_synthesize endpoint: {str(e)}")
        raise HTTPException(status_code=500, detail=f"TTS error: {str(e)}")


# ---------------------------------------------------------------------------
# /voice/transcribe & /voice/transcribe_file
# ---------------------------------------------------------------------------

@app.post("/voice/transcribe")
async def transcribe_audio(request: Request):
    """Transcribe audio sent as base64 encoded data."""
    try:
        json_data = await request.json()
        audio_data = json_data.get("audio_data")
        audio_format = json_data.get("audio_format", "mp3")
        requested_model = json_data.get("model")

        logger.info(f"Received transcription request. Format: {audio_format}, Model: {requested_model or 'default'}")

        if not audio_data:
            raise HTTPException(status_code=400, detail="No audio data provided")
        if not llm_manager:
            raise HTTPException(status_code=500, detail="LLM service not available")

        audio_bytes = base64.b64decode(audio_data)
        if len(audio_bytes) < 100:
            raise HTTPException(status_code=400, detail="Audio data too small or invalid")

        import tempfile
        temp_dir = tempfile.gettempdir()
        unique_id = uuid.uuid4()
        temp_file_path = os.path.join(temp_dir, f"audio_transcription_{unique_id}.{audio_format}")

        with open(temp_file_path, "wb") as f:
            f.write(audio_bytes)

        try:
            transcription = await llm_manager.transcribe_audio(temp_file_path)
        finally:
            try:
                os.remove(temp_file_path)
            except Exception:
                pass

        if not transcription or not transcription.strip():
            raise HTTPException(status_code=500, detail="Transcription service returned empty result")

        return {"text": transcription}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in transcribe_audio endpoint: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error processing request: {str(e)}")


@app.post("/voice/transcribe_file")
async def transcribe_file(file: UploadFile = File(...)):
    """Transcribe uploaded audio file."""
    import tempfile

    if not llm_manager:
        raise HTTPException(status_code=500, detail="LLM service not available")

    temp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp3")
    temp.write(await file.read())
    temp.close()

    try:
        transcription = await llm_manager.transcribe_audio(temp.name)
        return {"text": transcription}
    finally:
        os.remove(temp.name)


# ---------------------------------------------------------------------------
# Session CRUD
# ---------------------------------------------------------------------------

from app.crud import session as crud_session
from app.crud import reminder as crud_reminder

class SessionUpdateRequest(BaseModel):
    title: Optional[str] = None
    summary: Optional[str] = None
    user_id: Optional[int] = None

class SessionResponse(BaseModel):
    id: str
    title: str
    summary: Optional[str] = None
    action_items: List[str] = Field(default_factory=list)
    created_at: str
    last_modified: str
    isSynced: bool = True

class SessionReminderRequest(BaseModel):
    scheduled_time: datetime
    title: Optional[str] = None
    description: Optional[str] = None
    user_id: Optional[int] = None

class SessionReminderResponse(BaseModel):
    id: Optional[int] = None
    scheduled_time: Optional[datetime] = None
    title: Optional[str] = None
    description: Optional[str] = None
    is_completed: bool = False

class MessageRequest(BaseModel):
    content: str
    is_user_message: bool = True
    audio_url: Optional[str] = None
    sequence: Optional[int] = None


@app.get("/sessions", status_code=status.HTTP_200_OK)
async def get_sessions(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Get all sessions for the current user."""
    try:
        effective_user_id = current_user.user.id
        logger.info(f"Getting sessions for user {effective_user_id}")

        try:
            sessions = crud_session.get_sessions_by_user(db, effective_user_id)
            if not sessions:
                logger.info(f"No sessions found for user {effective_user_id}, creating defaults")
                try:
                    s1 = crud_session.create_session(db, user_id=effective_user_id, title="Your First Session")
                    s2 = crud_session.create_session(db, user_id=effective_user_id, title="Your Follow-up Session")
                    crud_session.update_session(db, s1.id, {"summary": "Welcome to your therapy journey. This is where your completed sessions will appear."})
                    crud_session.update_session(db, s2.id, {"summary": "Regular sessions help build progress. Complete another session to see it here."})
                    sessions = [s1, s2]
                except Exception as create_error:
                    logger.error(f"Error creating default sessions: {str(create_error)}")
                    now = utcnow_isoformat()
                    return [
                        {"id": str(uuid.uuid4()), "title": "First Therapy Session", "summary": "Welcome to your therapy journey.", "created_at": now, "last_modified": now, "isSynced": True},
                        {"id": str(uuid.uuid4()), "title": "Follow-up Session", "summary": "Regular sessions help build progress.", "created_at": now, "last_modified": now, "isSynced": True}
                    ]
        except Exception as db_error:
            logger.error(f"Database error fetching sessions: {str(db_error)}")
            now = utcnow_isoformat()
            return [
                {"id": str(uuid.uuid4()), "title": "First Therapy Session", "summary": "Database connectivity issue. Please try again later.", "created_at": now, "last_modified": now, "isSynced": True}
            ]

        result = []
        for session in sessions:
            result.append({
                "id": str(session.id),
                "title": session.title or f"Session {session.id}",
                "summary": session.summary or "No summary available",
                "action_items": session.action_items or [],
                "created_at": serialize_datetime(session.start_time),
                "last_modified": serialize_datetime(session.end_time) if session.end_time else serialize_datetime(session.start_time),
                "isSynced": True
            })
        return result
    except Exception as e:
        logger.error(f"Unhandled error in get_sessions: {str(e)}")
        now = utcnow_isoformat()
        return [{"id": str(uuid.uuid4()), "title": "Service Temporarily Unavailable", "summary": "Please try again later.", "created_at": now, "last_modified": now, "isSynced": True}]


@app.post("/sessions", status_code=status.HTTP_201_CREATED, response_model=SessionResponse)
async def create_session(
    request: SessionUpdateRequest = None,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Create a new session"""
    try:
        if not request:
            request = SessionUpdateRequest()
        user_id = current_user.user.id
        session = crud_session.create_session(db, user_id=user_id, title=request.title)
        return {
            "id": str(session.id),
            "title": request.title or f"Session {session.id}",
            "summary": session.summary or "",
            "created_at": serialize_datetime(session.start_time),
            "last_modified": serialize_datetime(session.start_time),
            "isSynced": True
        }
    except Exception as e:
        logger.error(f"Error creating session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error creating session: {str(e)}")


@app.get("/sessions/{session_id}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def get_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Get a specific session"""
    try:
        session = crud_session.get_session(db, session_id)
        if not session or session.user_id != current_user.user.id:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        return {
            "id": str(session.id),
            "title": session.title or f"Session {session.id}",
            "summary": session.summary or "",
            "action_items": session.action_items or [],
            "created_at": serialize_datetime(session.start_time),
            "last_modified": serialize_datetime(session.end_time) if session.end_time else serialize_datetime(session.start_time),
            "isSynced": True
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error getting session: {str(e)}")


@app.patch("/sessions/{session_id}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def update_session(
    session_id: str,
    request: SessionUpdateRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Update a session"""
    try:
        update_data = {}
        if request.title is not None:
            update_data["title"] = request.title
        if request.summary is not None:
            update_data["summary"] = request.summary

        existing_session = crud_session.get_session(db, session_id)
        if existing_session and existing_session.user_id != current_user.user.id:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")

        session = None
        if existing_session:
            session = crud_session.update_session(db, session_id, update_data)

        if not session:
            session = crud_session.create_session(db, user_id=current_user.user.id, title=request.title, summary=request.summary)

        return {
            "id": str(session.id),
            "title": session.title or f"Session {session.id}",
            "summary": session.summary or "",
            "created_at": serialize_datetime(session.start_time),
            "last_modified": serialize_datetime(session.end_time) if session.end_time else serialize_datetime(session.start_time),
            "isSynced": True
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating session: {str(e)}")
        now = utcnow_isoformat()
        return {
            "id": session_id,
            "title": request.title or f"Session {session_id}",
            "summary": request.summary or "Error saving session, please try again",
            "created_at": now, "last_modified": now, "isSynced": True
        }


@app.delete("/sessions/{session_id}", status_code=status.HTTP_200_OK)
async def delete_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Delete a session"""
    try:
        session = crud_session.get_session(db, session_id)
        if not session or session.user_id != current_user.user.id:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        success = crud_session.delete_session(db, session_id)
        if not success:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        return {"status": "success", "message": f"Session {session_id} deleted"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting session: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error deleting session: {str(e)}")


# ---------------------------------------------------------------------------
# Session reminder
# ---------------------------------------------------------------------------

@app.get("/session-reminder", status_code=status.HTTP_200_OK, response_model=SessionReminderResponse)
async def get_session_reminder(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Fetch the next scheduled therapy session reminder."""
    try:
        reminder = crud_reminder.get_next_session_reminder(db, current_user.user.id)
        if not reminder:
            return SessionReminderResponse()
        return SessionReminderResponse(
            id=reminder.id, scheduled_time=reminder.scheduled_time,
            title=reminder.title, description=reminder.description,
            is_completed=reminder.is_completed,
        )
    except Exception as e:
        logger.error(f"Error fetching session reminder: {str(e)}")
        raise HTTPException(status_code=500, detail="Unable to fetch session reminder")


@app.put("/session-reminder", status_code=status.HTTP_200_OK, response_model=SessionReminderResponse)
async def upsert_session_reminder(
    request: SessionReminderRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Create or update the user's next session reminder."""
    try:
        reminder = crud_reminder.upsert_session_reminder(
            db, user_id=current_user.user.id,
            scheduled_time=request.scheduled_time,
            title=request.title, description=request.description,
        )
        return SessionReminderResponse(
            id=reminder.id, scheduled_time=reminder.scheduled_time,
            title=reminder.title, description=reminder.description,
            is_completed=reminder.is_completed,
        )
    except Exception as e:
        logger.error(f"Error upserting session reminder: {str(e)}")
        raise HTTPException(status_code=500, detail="Unable to update session reminder")


# ---------------------------------------------------------------------------
# Session messages
# ---------------------------------------------------------------------------

@app.post("/sessions/{session_id}/messages", status_code=status.HTTP_200_OK)
async def add_session_message(
    session_id: str,
    message: MessageRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Add a message to a session"""
    try:
        session = crud_session.get_session(db, session_id)
        if not session or session.user_id != current_user.user.id:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        msg = crud_session.add_message_to_session(
            db, session_id=session_id, content=message.content,
            is_user_message=message.is_user_message,
            audio_url=message.audio_url, sequence=message.sequence
        )
        return {"status": "success", "message_id": str(msg.id)}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error adding message: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error adding message: {str(e)}")


@app.post("/sessions/{session_id}/messages/batch", status_code=status.HTTP_200_OK)
async def add_session_messages_batch(
    session_id: str,
    messages: List[MessageRequest],
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Add multiple messages to a session in a single batch"""
    try:
        session = crud_session.get_session(db, session_id)
        if not session or session.user_id != current_user.user.id:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
        message_dicts = [
            {"content": m.content, "is_user_message": m.is_user_message, "audio_url": m.audio_url, "sequence": m.sequence}
            for m in messages
        ]
        saved = crud_session.add_messages_batch(db, session_id, message_dicts)
        return {"status": "success", "message_count": len(saved), "message_ids": [str(m.id) for m in saved]}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error adding batch messages: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error adding batch messages: {str(e)}")


# ---------------------------------------------------------------------------
# Legacy API endpoints (/api/v1 prefix)
# ---------------------------------------------------------------------------

@app.get(f"{settings.API_V1_STR}/sessions", status_code=status.HTTP_200_OK)
async def get_sessions_legacy(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    return await get_sessions(current_user=current_user, db=db)

@app.get(f"{settings.API_V1_STR}/sessions/{{session_id}}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def get_session_legacy(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    return await get_session(session_id, current_user=current_user, db=db)

@app.patch(f"{settings.API_V1_STR}/sessions/{{session_id}}", status_code=status.HTTP_200_OK, response_model=SessionResponse)
async def update_session_legacy(
    session_id: str,
    request: SessionUpdateRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    return await update_session(session_id, request, current_user=current_user, db=db)

@app.delete(f"{settings.API_V1_STR}/sessions/{{session_id}}", status_code=status.HTTP_200_OK)
async def delete_session_legacy(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    return await delete_session(session_id, current_user=current_user, db=db)

@app.post(f"{settings.API_V1_STR}/sessions/{{session_id}}/messages", status_code=status.HTTP_200_OK)
async def add_session_message_legacy(
    session_id: str,
    message: MessageRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    return await add_session_message(session_id, message, current_user=current_user, db=db)

@app.post(f"{settings.API_V1_STR}/sessions/{{session_id}}/messages/batch", status_code=status.HTTP_200_OK)
async def add_session_messages_batch_legacy(
    session_id: str,
    messages: List[MessageRequest],
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    return await add_session_messages_batch(session_id, messages, current_user=current_user, db=db)


# ---------------------------------------------------------------------------
# Error handlers
# ---------------------------------------------------------------------------

@app.exception_handler(404)
async def custom_404_handler(request: Request, exc):
    logger.warning(f"Route not found: {request.method} {request.url.path}")
    return JSONResponse(status_code=status.HTTP_404_NOT_FOUND, content={"detail": f"Route not found: {request.url.path}"})

@app.exception_handler(405)
async def custom_405_handler(request: Request, exc):
    logger.warning(f"Method {request.method} not allowed for {request.url.path}")
    return JSONResponse(status_code=status.HTTP_405_METHOD_NOT_ALLOWED, content={"detail": f"Method {request.method} not allowed for {request.url.path}"})


# ---------------------------------------------------------------------------
# Chat streaming
# ---------------------------------------------------------------------------

@app.post("/sessions/{session_id}/chat_stream")
async def stream_chat_from_llm(
    session_id: str,
    request_data: ChatStreamRequestBody,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
):
    """Streams chat completions from the LLM for a given session."""
    if not llm_manager:
        raise HTTPException(status_code=500, detail="LLM service not configured or unavailable.")

    try:
        import time
        from app.core.observability import record_latency, record_counter

        session = crud_session.get_session(db, session_id)
        if not session or session.user_id != current_user.user.id:
            raise HTTPException(status_code=404, detail=f"Session {session_id} not found")

        request_start_time = time.time()
        logger.info(f"Chat stream request for session_id: {session_id} with {len(request_data.history)} messages")

        system_prompt_for_session = "You are Maya, a caring and empathetic AI therapist. Respond naturally and supportively."

        if not request_data.history:
            raise HTTPException(status_code=400, detail="Chat history cannot be empty.")

        latest_message = request_data.history[-1].get("content", "") if request_data.history else ""
        context = request_data.history[:-1] if len(request_data.history) > 1 else []

        first_chunk_received = False

        async def text_stream():
            nonlocal first_chunk_received
            try:
                async for chunk in llm_manager.stream_chat_completion(
                    message=latest_message, context=context,
                    system_prompt=system_prompt_for_session, temperature=0.7
                ):
                    if not first_chunk_received:
                        ttfb_ms = (time.time() - request_start_time) * 1000
                        record_latency("llm", "chat_ttfb", ttfb_ms, {"provider": os.environ.get("ACTIVE_LLM_PROVIDER", "unknown")})
                        record_counter("llm", "chat_requests_total", labels={"provider": os.environ.get("ACTIVE_LLM_PROVIDER", "unknown")})
                        logger.info(f"LLM TTFB: {ttfb_ms:.1f}ms for session {session_id}")
                        first_chunk_received = True
                    yield chunk
            except Exception as e:
                record_counter("llm", "chat_errors_total", labels={"provider": os.environ.get("ACTIVE_LLM_PROVIDER", "unknown"), "error_type": type(e).__name__})
                raise

        return StreamingResponse(text_stream(), media_type="text/plain; charset=utf-8")

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in stream_chat_from_llm for session {session_id}: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"An error occurred while streaming the chat response: {str(e)}")


# ---------------------------------------------------------------------------
# Helper functions (end_session support)
# ---------------------------------------------------------------------------

async def _create_session_with_summary(db: DBSession, summary_data: Dict[str, Any], request: EndSessionRequest) -> int:
    """Create a session record in the database with rich summary data and return the session ID."""
    try:
        user_id = request.user_id or 1
        session_title = request.session_title or f"Therapy Session {datetime.now().strftime('%b %d, %Y')}"
        session = crud_session.create_session(
            db=db, user_id=user_id, title=session_title,
            action_items=summary_data.get("action_items", []),
            summary=summary_data.get("summary", "")
        )
        return session.id
    except Exception as e:
        logger.error(f"Error creating session record: {str(e)}")
        try:
            fallback = crud_session.create_session(
                db=db, user_id=1, title="Therapy Session",
                action_items=summary_data.get("action_items", []),
                summary=summary_data.get("summary", "")
            )
            return fallback.id
        except Exception:
            return 1


async def _validate_and_clean_summary(result: Dict[str, Any], messages: List[Dict[str, Any]], display_name: str = "you") -> Dict[str, Any]:
    """Validate and clean the summary result."""
    if not isinstance(result, dict):
        raise ValueError("Response is not a dictionary")

    if not result.get("summary") or len(result["summary"].strip()) < 20:
        result["summary"] = "Thank you for sharing your thoughts and feelings in this session. We explored important topics together."

    action_items = result.get("action_items", [])
    if not action_items:
        action_items = await _generate_basic_action_items(messages, display_name)
    else:
        cleaned = [item.strip() for item in action_items if isinstance(item, str) and len(item.strip()) > 10]
        if len(cleaned) < 2:
            cleaned.extend((await _generate_basic_action_items(messages, display_name))[:3])
        action_items = cleaned[:5]

    result["action_items"] = action_items
    result["insights"] = result.get("insights") or [
        "You showed courage by sharing your experiences today",
        "Your self-awareness is a valuable strength"
    ]
    return result


async def _generate_basic_action_items(messages: List[Dict[str, Any]], display_name: str = "you") -> List[str]:
    """Generate basic action items based on conversation content."""
    user_messages = [msg.get('content', '').lower() for msg in messages if msg.get("isUser", False)]
    text = ' '.join(user_messages)

    items = []
    if any(w in text for w in ['stress', 'anxious', 'worry', 'overwhelmed']):
        items.append("Practice deep breathing exercises when feeling stressed or anxious")
    if any(w in text for w in ['sleep', 'tired', 'exhausted']):
        items.append("Focus on improving your sleep routine and getting adequate rest")
    if any(w in text for w in ['relationship', 'family', 'friends', 'partner']):
        items.append("Consider having an open conversation with someone you trust")
    if any(w in text for w in ['work', 'job', 'career']):
        items.append("Take regular breaks during work to maintain balance")
    if any(w in text for w in ['exercise', 'physical', 'activity']):
        items.append("Incorporate some physical activity into your daily routine")

    defaults = [
        "Take time for self-reflection and journaling",
        "Practice mindfulness or meditation for a few minutes daily",
        "Engage in one activity that brings you joy this week",
        "Be kind and patient with yourself as you work through challenges"
    ]
    return list(dict.fromkeys(items + defaults))[:4]


async def _generate_conversation_based_summary(
    messages: List[Dict[str, Any]], therapeutic_approach: str,
    user_id: Optional[int] = None, db: Optional[DBSession] = None
) -> Dict[str, Any]:
    """Generate a fallback summary based on conversation analysis."""
    from app.services.profile_service import get_profile

    preferred_name = None
    if user_id and db:
        profile = get_profile(db, user_id=user_id)
        preferred_name = profile.preferred_name if profile else None
    display_name = preferred_name if preferred_name else "you"

    user_message_count = len([msg for msg in messages if msg.get("isUser", False)])
    if user_message_count > 5:
        summary = "Thank you for sharing so openly with Maya today. You covered several important topics and explored different perspectives together."
    else:
        summary = "Thank you for taking the time to connect with Maya today. Even brief conversations can provide valuable insights."

    return {
        "summary": summary,
        "action_items": await _generate_basic_action_items(messages, display_name),
        "insights": [
            "You engaged thoughtfully in your conversation with Maya today",
            "Your willingness to explore these topics shows strength and self-awareness"
        ]
    }


# ---------------------------------------------------------------------------
# Root WebSocket proxies
# ---------------------------------------------------------------------------

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
        from app.api.endpoints.voice import websocket_streaming_tts
        return await websocket_streaming_tts(websocket, token, conversation_id, voice, format)
    except Exception as e:
        logger.error(f"Root WebSocket TTS error: {str(e)}")
        try:
            await websocket.close(code=1011, reason="Internal server error")
        except Exception:
            pass


@app.websocket("/ws/tts")
async def root_websocket_tts(websocket: WebSocket):
    """Root-level WebSocket endpoint for basic TTS"""
    try:
        from app.api.endpoints.voice import websocket_tts
        return await websocket_tts(websocket)
    except Exception as e:
        logger.error(f"Root WebSocket basic TTS error: {str(e)}")
        try:
            await websocket.close(code=1011, reason="Internal server error")
        except Exception:
            pass


# ---------------------------------------------------------------------------
# App lifecycle events
# ---------------------------------------------------------------------------

@app.on_event("shutdown")
async def close_groq_stt_client():
    """Clean up httpx client on app shutdown"""
    if _groq_stt_client:
        try:
            await _groq_stt_client.aclose()
            logger.info("Groq STT client closed successfully")
        except Exception as e:
            logger.error(f"Error closing Groq STT client: {e}")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
