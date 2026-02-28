from fastapi import APIRouter, Depends, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from typing import List, Optional, Dict, Any
import logging
import traceback
import json
from datetime import datetime
from app.core.datetime_utils import serialize_datetime, utcnow_isoformat
import uuid

# Replace individual service imports with unified manager
from app.services.llm_manager import llm_manager
from app.core.config import settings
from app.api.deps.auth import get_current_user


# --- Request validation models ---

class HistoryMessage(BaseModel):
    role: str = Field(..., max_length=20)
    content: str = Field(..., max_length=10000)

class GenerateRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=10000, description="User message")
    history: List[HistoryMessage] = Field(default_factory=list, max_length=50)
    system_prompt: str = Field(default="", max_length=5000)
    user_info: Optional[Dict[str, Any]] = None

logger = logging.getLogger(__name__)

router = APIRouter()

# In-memory session store: {session_id: {"history": [...], "created_at": ...}}
session_store = {}

@router.post("/generate", response_class=JSONResponse)
async def generate_response(body: GenerateRequest):
    """
    Generate response from AI model using the unified LLM manager.
    Input is validated via Pydantic (max message length, bounded history, etc.).
    """
    try:
        logger.info(f"Generating AI response for message: {body.message[:30]}...")
        
        # Convert validated history to dicts for LLM manager
        conversation_history = [h.model_dump() for h in body.history]
        
        # Generate AI response using unified LLM manager
        response = await llm_manager.generate_response(
            message=body.message,
            context=conversation_history,
            system_prompt=body.system_prompt,
            user_info=body.user_info
        )
        
        if not response:
            return JSONResponse({"error": "Failed to generate response"}, status_code=500)
            
        return JSONResponse({"response": response})
        
    except Exception as e:
        logger.error(f"Error generating AI response: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)

@router.get("/status", response_class=JSONResponse)
async def check_service_status():
    """
    Diagnostic endpoint to check the status of all AI services using unified manager
    """
    try:
        # Get comprehensive status from unified manager
        status = llm_manager.get_status()
        
        logger.info(f"Service status check completed")
        
        return JSONResponse(status)
    except Exception as e:
        logger.error(f"Error checking service status: {str(e)}")
        return JSONResponse({"error": str(e), "traceback": str(traceback.format_exc())}, status_code=500)

@router.get("/test-key", response_class=JSONResponse)
async def test_api_keys(current_user=Depends(get_current_user)):
    """
    Test all API keys to ensure they're working correctly using unified manager
    """
    try:
        logger.info("Testing API keys via unified LLM manager")
        
        # Test all APIs through unified manager
        result = await llm_manager.test_api()
        
        logger.info(f"API key test results completed")
        
        return JSONResponse(result)
    except Exception as e:
        logger.error(f"Error testing API keys: {str(e)}")
        return JSONResponse({"error": str(e), "traceback": str(traceback.format_exc())}, status_code=500)

@router.get("/config", response_class=JSONResponse)
async def get_configuration():
    """
    Get detailed configuration information and validation status
    """
    try:
        from app.core.llm_config import LLMConfig
        
        # Get validation results
        validation = LLMConfig.validate_configuration()
        
        # Get current status from manager
        manager_status = llm_manager.get_status()
        
        result = {
            "validation": validation,
            "manager_status": manager_status,
            "active_providers": {
                "llm": LLMConfig.ACTIVE_LLM_PROVIDER,
                "tts": LLMConfig.ACTIVE_TTS_PROVIDER,
                "transcription": LLMConfig.ACTIVE_TRANSCRIPTION_PROVIDER
            }
        }
        
        logger.info("Configuration status retrieved successfully")
        
        return JSONResponse(result)
    except Exception as e:
        logger.error(f"Error getting configuration: {str(e)}")
        return JSONResponse({"error": str(e), "traceback": str(traceback.format_exc())}, status_code=500)

@router.websocket("/ws/chat")
async def websocket_chat(websocket: WebSocket):
    await websocket.accept()
    session_id = None
    session = None
    new_session = False
    sequence = 1
    try:
        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
            except Exception:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "detail": "Invalid JSON input",
                    "timestamp": utcnow_isoformat()
                }))
                continue
            message = payload.get("message", "")
            history = payload.get("history")
            incoming_session_id = payload.get("session_id")
            system_prompt = payload.get("system_prompt", "")
            user_info = payload.get("user_info")
            
            # Session management
            if incoming_session_id and incoming_session_id in session_store:
                session_id = incoming_session_id
                session = session_store[session_id]
                if history is None:
                    history = session["history"]
            else:
                # Generate new session_id and session
                session_id = str(uuid.uuid4())
                session = {"history": [], "created_at": utcnow_isoformat()}
                session_store[session_id] = session
                new_session = True
                if history is None:
                    history = []
            
            # Append current user message to session history
            session["history"].append({"isUser": True, "content": message})
            
            # Stream response using unified LLM manager
            try:
                async for chunk in llm_manager.stream_chat_completion(
                    message=message,
                    context=history,
                    system_prompt=system_prompt,
                    user_info=user_info
                ):
                    response = {
                        "type": "chunk",
                        "content": chunk,
                        "sequence": sequence,
                        "timestamp": utcnow_isoformat(),
                        "session_id": session_id
                    }
                    await websocket.send_text(json.dumps(response))
                    sequence += 1
                
                await websocket.send_text(json.dumps({
                    "type": "done",
                    "sequence": sequence,
                    "timestamp": utcnow_isoformat(),
                    "session_id": session_id
                }))
                sequence += 1
                
            except Exception as stream_error:
                logger.error(f"Error in streaming: {str(stream_error)}")
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "detail": f"Streaming error: {str(stream_error)}",
                    "timestamp": utcnow_isoformat(),
                    "session_id": session_id
                }))
                
    except WebSocketDisconnect:
        logger.info("WebSocket chat disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {str(e)}")
        try:
            await websocket.send_text(json.dumps({
                "type": "error",
                "detail": str(e),
                "timestamp": utcnow_isoformat(),
                "session_id": session_id
            }))
            await websocket.close()
        except:
            pass  # WebSocket might already be closed 
