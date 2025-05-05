"""CRUD operations for sessions."""
from typing import List, Optional, Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session as DBSession

from app.models.session import Session
from app.models.message import Message


def get_session(db: DBSession, session_id: str) -> Optional[Session]:
    """Get a session by ID."""
    return db.query(Session).filter(Session.id == session_id).first()


def get_sessions_by_user(db: DBSession, user_id: int) -> List[Session]:
    """Get all sessions for a user."""
    return db.query(Session).filter(Session.user_id == user_id).all()


def create_session(db: DBSession, user_id: int, title: str = None) -> Session:
    """Create a new session."""
    session = Session(
        user_id=user_id,
        summary=None,
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return session


def update_session(
    db: DBSession, 
    session_id: int, 
    data: Dict[str, Any]
) -> Optional[Session]:
    """Update a session."""
    session = get_session(db, session_id)
    if not session:
        return None
        
    for field, value in data.items():
        if hasattr(session, field):
            setattr(session, field, value)
            
    # Always update the last_modified field
    session.end_time = datetime.now()
    
    db.commit()
    db.refresh(session)
    return session


def delete_session(db: DBSession, session_id: int) -> bool:
    """Delete a session."""
    session = get_session(db, session_id)
    if not session:
        return False
        
    db.delete(session)
    db.commit()
    return True


def add_message_to_session(
    db: DBSession,
    session_id: int,
    content: str,
    is_user_message: bool = True,
    audio_url: str = None
) -> Message:
    """Add a message to a session."""
    message = Message(
        session_id=session_id,
        content=content,
        is_user_message=is_user_message,
        audio_url=audio_url
    )
    db.add(message)
    db.commit()
    db.refresh(message)
    return message


def get_messages_for_session(db: DBSession, session_id: int) -> List[Message]:
    """Get all messages for a session."""
    return db.query(Message).filter(Message.session_id == session_id).all()


def add_messages_batch(
    db: DBSession,
    session_id: int,
    messages: List[Dict[str, Any]]
) -> List[Message]:
    """Add multiple messages to a session in a batch."""
    message_objects = []
    for msg in messages:
        message = Message(
            session_id=session_id,
            content=msg.get("content", ""),
            is_user_message=msg.get("is_user_message", True),
            audio_url=msg.get("audio_url")
        )
        db.add(message)
        message_objects.append(message)
        
    db.commit()
    for msg in message_objects:
        db.refresh(msg)
        
    return message_objects 