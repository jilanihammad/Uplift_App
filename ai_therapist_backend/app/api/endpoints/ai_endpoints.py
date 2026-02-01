"""AI and chat endpoints"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session as DBSession
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import logging
import json

from app.api.deps.auth import get_current_user, AuthenticatedUser
from app.db.session import get_db
from app.services.llm_manager import llm_manager
from app.services.session_summary_service import generate_session_summary

logger = logging.getLogger(__name__)
router = APIRouter()


class AIRequest(BaseModel):
    """Request model for AI responses"""
    message: str
    system_prompt: str = ""
    model: Optional[str] = None
    temperature: float = 0.7
    max_tokens: int = 1000
    history: Optional[List[Dict[str, Any]]] = None


class AIResponse(BaseModel):
    """Response model for AI requests"""
    response: str
    model_used: Optional[str] = None


class EndSessionRequest(BaseModel):
    """Request model for ending a session"""
    messages: List[Dict[str, Any]]
    system_prompt: str = ""
    memory_context: str = ""
    therapeutic_approach: str = "supportive"
    visited_nodes: List[str] = []
    session_title: Optional[str] = None
    user_id: Optional[int] = None


class SessionSummaryResponse(BaseModel):
    """Response model for session summary"""
    id: Optional[int] = None
    summary: str
    action_items: List[str]
    insights: List[str]
    therapeutic_approach: str


@router.post("/response", response_model=AIResponse)
async def ai_response(request: AIRequest) -> AIResponse:
    """Generate an AI response to a user message."""
    try:
        logger.info(f"AI request: '{request.message[:50]}...'")
        
        if not llm_manager:
            raise HTTPException(status_code=500, detail="LLM service not available")
        
        response_text = await llm_manager.generate_response(
            message=request.message,
            system_prompt=request.system_prompt,
            context=request.history,
            temperature=request.temperature,
            max_tokens=request.max_tokens
        )
        
        logger.info("AI response generated successfully")
        return AIResponse(response=response_text)
        
    except Exception as e:
        logger.error(f"Error generating AI response: {e}")
        raise HTTPException(status_code=500, detail=f"Error generating response: {str(e)}")


@router.post("/end_session", response_model=SessionSummaryResponse)
async def end_session(
    request: EndSessionRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
) -> SessionSummaryResponse:
    """End a therapy session and generate a summary."""
    try:
        logger.info(f"Ending session with {len(request.messages)} messages")
        
        if not llm_manager:
            raise HTTPException(status_code=500, detail="LLM service not available")
        
        # Generate summary
        summary_result = await generate_session_summary(
            messages=request.messages,
            therapeutic_approach=request.therapeutic_approach,
            memory_context=request.memory_context,
            user_id=current_user.user.id,
            db=db
        )
        
        return SessionSummaryResponse(
            id=summary_result.get("id"),
            summary=summary_result["summary"],
            action_items=summary_result["action_items"],
            insights=summary_result["insights"],
            therapeutic_approach=request.therapeutic_approach
        )
        
    except Exception as e:
        logger.error(f"Error ending session: {e}")
        raise HTTPException(status_code=500, detail=f"Error ending session: {str(e)}")


@router.get("/llm/status")
async def llm_status() -> Dict[str, Any]:
    """Check LLM API availability."""
    try:
        if not llm_manager:
            return {"status": "unavailable", "reason": "LLM manager not initialized"}
        
        status_info = llm_manager.get_status()
        
        return {
            "status": "available" if status_info.get("available_providers") else "unavailable",
            "manager_status": status_info,
            "unified_system": True
        }
    except Exception as e:
        logger.error(f"Error checking LLM status: {e}")
        return {"status": "unavailable", "reason": str(e)}
