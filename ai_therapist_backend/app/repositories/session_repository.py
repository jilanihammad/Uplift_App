"""Session + Message repository — migrated from app/crud/session.py.

Message persistence lives here because it is exclusively coupled to a
session today (no Message endpoints exist outside session-scoped routes).
If Message access ever leaks beyond sessions, split into its own repo.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional, Protocol

from sqlalchemy.orm import Session as DBSession

from app.models.message import Message
from app.models.session import Session


class ISessionRepository(Protocol):
    def get_session(self, session_id: str) -> Optional[Session]: ...
    def get_sessions_by_user(self, user_id: int) -> List[Session]: ...
    def create_session(
        self,
        user_id: int,
        title: Optional[str] = None,
        action_items: Optional[List[str]] = None,
        summary: Optional[str] = None,
    ) -> Session: ...
    def update_session(self, session_id: str, data: Dict[str, Any]) -> Optional[Session]: ...
    def delete_session(self, session_id: str) -> bool: ...
    def add_message_to_session(
        self,
        session_id: str,
        content: str,
        is_user_message: bool = True,
        audio_url: Optional[str] = None,
        sequence: Optional[int] = None,
    ) -> Message: ...
    def get_messages_for_session(self, session_id: str) -> List[Message]: ...
    def add_messages_batch(
        self,
        session_id: str,
        messages: List[Dict[str, Any]],
    ) -> List[Message]: ...


class SessionRepository:
    def __init__(self, db: DBSession) -> None:
        self.db = db

    def get_session(self, session_id: str) -> Optional[Session]:
        return self.db.query(Session).filter(Session.id == session_id).first()

    def get_sessions_by_user(self, user_id: int) -> List[Session]:
        return self.db.query(Session).filter(Session.user_id == user_id).all()

    def create_session(
        self,
        user_id: int,
        title: Optional[str] = None,
        action_items: Optional[List[str]] = None,
        summary: Optional[str] = None,
    ) -> Session:
        if not title:
            title = f"Therapy Session {datetime.now().strftime('%b %d, %Y')}"
        session = Session(
            user_id=user_id,
            title=title,
            summary=summary,
            action_items=action_items or [],
        )
        self.db.add(session)
        self.db.commit()
        self.db.refresh(session)
        return session

    def update_session(self, session_id: str, data: Dict[str, Any]) -> Optional[Session]:
        session = self.get_session(session_id)
        if not session:
            return None
        for field, value in data.items():
            if hasattr(session, field):
                setattr(session, field, value)
        session.end_time = datetime.utcnow()
        self.db.commit()
        self.db.refresh(session)
        return session

    def delete_session(self, session_id: str) -> bool:
        session = self.get_session(session_id)
        if not session:
            return False
        self.db.delete(session)
        self.db.commit()
        return True

    def add_message_to_session(
        self,
        session_id: str,
        content: str,
        is_user_message: bool = True,
        audio_url: Optional[str] = None,
        sequence: Optional[int] = None,
    ) -> Message:
        message = Message(
            session_id=session_id,
            content=content,
            is_user_message=is_user_message,
            audio_url=audio_url,
            sequence=sequence,
        )
        self.db.add(message)
        self.db.commit()
        self.db.refresh(message)
        return message

    def get_messages_for_session(self, session_id: str) -> List[Message]:
        return self.db.query(Message).filter(Message.session_id == session_id).all()

    def add_messages_batch(
        self,
        session_id: str,
        messages: List[Dict[str, Any]],
    ) -> List[Message]:
        message_objects: List[Message] = []
        for msg in messages:
            message = Message(
                session_id=session_id,
                content=msg.get("content", ""),
                is_user_message=msg.get("is_user_message", True),
                audio_url=msg.get("audio_url"),
                sequence=msg.get("sequence"),
            )
            self.db.add(message)
            message_objects.append(message)
        self.db.commit()
        for msg in message_objects:
            self.db.refresh(msg)
        return message_objects
