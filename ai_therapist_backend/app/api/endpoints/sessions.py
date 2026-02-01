"""Session management endpoints"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session as DBSession
from typing import List, Optional
from datetime import datetime
import logging

from app.api.deps.auth import get_current_user, AuthenticatedUser
from app.db.session import get_db
from app.crud import session as crud_session
from app.schemas.session import SessionCreate, SessionUpdate, SessionResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("", response_model=List[SessionResponse])
async def get_sessions(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
) -> List[SessionResponse]:
    """Get all sessions for the current user."""
    try:
        sessions = crud_session.get_sessions_by_user(db, current_user.user.id)
        
        # Create default sessions if none exist
        if not sessions:
            session1 = crud_session.create_session(
                db, 
                user_id=current_user.user.id, 
                title="Your First Session"
            )
            session2 = crud_session.create_session(
                db, 
                user_id=current_user.user.id, 
                title="Your Follow-up Session"
            )
            sessions = [session1, session2]
        
        return [
            SessionResponse(
                id=str(s.id),
                title=s.title or f"Session {s.id}",
                summary=s.summary or "No summary available",
                action_items=s.action_items or [],
                created_at=s.start_time.isoformat() if s.start_time else datetime.utcnow().isoformat(),
                last_modified=(s.end_time or s.start_time).isoformat() if s.end_time or s.start_time else datetime.utcnow().isoformat(),
                is_synced=True
            )
            for s in sessions
        ]
    except Exception as e:
        logger.error(f"Error fetching sessions: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch sessions: {str(e)}")


@router.post("", response_model=SessionResponse, status_code=status.HTTP_201_CREATED)
async def create_session(
    request: SessionCreate,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
) -> SessionResponse:
    """Create a new session."""
    try:
        session = crud_session.create_session(
            db, 
            user_id=current_user.user.id, 
            title=request.title
        )
        
        return SessionResponse(
            id=str(session.id),
            title=request.title or f"Session {session.id}",
            summary=session.summary or "",
            action_items=session.action_items or [],
            created_at=session.start_time.isoformat() if session.start_time else datetime.utcnow().isoformat(),
            last_modified=session.start_time.isoformat() if session.start_time else datetime.utcnow().isoformat(),
            is_synced=True
        )
    except Exception as e:
        logger.error(f"Error creating session: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create session: {str(e)}")


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
) -> SessionResponse:
    """Get a specific session by ID."""
    session = crud_session.get_session(db, session_id)
    
    if not session or session.user_id != current_user.user.id:
        raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
    
    return SessionResponse(
        id=str(session.id),
        title=session.title or f"Session {session.id}",
        summary=session.summary or "",
        action_items=session.action_items or [],
        created_at=session.start_time.isoformat() if session.start_time else datetime.utcnow().isoformat(),
        last_modified=(session.end_time or session.start_time).isoformat() if session.end_time or session.start_time else datetime.utcnow().isoformat(),
        is_synced=True
    )


@router.patch("/{session_id}", response_model=SessionResponse)
async def update_session(
    session_id: str,
    request: SessionUpdate,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
) -> SessionResponse:
    """Update a session."""
    existing = crud_session.get_session(db, session_id)
    
    if existing and existing.user_id != current_user.user.id:
        raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
    
    update_data = {}
    if request.title is not None:
        update_data["title"] = request.title
    if request.summary is not None:
        update_data["summary"] = request.summary
    
    if existing:
        session = crud_session.update_session(db, session_id, update_data)
    else:
        # Create new session if not found
        session = crud_session.create_session(
            db,
            user_id=current_user.user.id,
            title=request.title,
            summary=request.summary
        )
    
    return SessionResponse(
        id=str(session.id),
        title=session.title or f"Session {session.id}",
        summary=session.summary or "",
        action_items=session.action_items or [],
        created_at=session.start_time.isoformat() if session.start_time else datetime.utcnow().isoformat(),
        last_modified=(session.end_time or session.start_time).isoformat() if session.end_time or session.start_time else datetime.utcnow().isoformat(),
        is_synced=True
    )


@router.delete("/{session_id}", status_code=status.HTTP_200_OK)
async def delete_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: DBSession = Depends(get_db),
) -> dict:
    """Delete a session."""
    session = crud_session.get_session(db, session_id)
    
    if not session or session.user_id != current_user.user.id:
        raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
    
    success = crud_session.delete_session(db, session_id)
    
    if not success:
        raise HTTPException(status_code=500, detail=f"Failed to delete session {session_id}")
    
    return {"status": "success", "message": f"Session {session_id} deleted"}
