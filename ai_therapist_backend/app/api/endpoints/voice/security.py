"""
WebSocket security validation and JWT session management.

Contains:
- WebSocketSecurityValidator: Origin/sub-protocol validation (Step 11)
- JWTSecurityManager: Enhanced JWT security for WebSocket connections
"""
import logging
import time
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any, Set, List
import re

from fastapi import WebSocket
from jose import jwt, JWTError

from app.core.config import settings

logger = logging.getLogger(__name__)


class WebSocketSecurityValidator:
    """
    WebSocket security validator for origin and sub-protocol validation
    Implements Step 11: Origin/Sub-protocol Validation
    """

    @staticmethod
    def normalize_origin(origin: str) -> str:
        """Normalize origin for comparison (handle case sensitivity and trailing slashes)"""
        if not origin:
            return ""

        # Convert to lowercase for case-insensitive comparison
        normalized = origin.lower().rstrip('/')

        # Handle port normalization
        if normalized.startswith('https://') and ':443' in normalized:
            normalized = normalized.replace(':443', '')
        elif normalized.startswith('http://') and ':80' in normalized:
            normalized = normalized.replace(':80', '')

        return normalized

    @staticmethod
    def is_origin_allowed(origin: str, allowed_origins: List[str]) -> bool:
        """
        Check if origin is allowed based on patterns in allowed_origins

        Args:
            origin: The origin header from the WebSocket request
            allowed_origins: List of allowed origin patterns

        Returns:
            bool: True if origin is allowed
        """
        if not origin:
            logger.warning("WebSocket connection attempted without Origin header")
            return False

        # Allow all origins if "*" is in the list (development mode)
        if "*" in allowed_origins:
            logger.info(f"Origin {origin} allowed (wildcard mode)")
            return True

        normalized_origin = WebSocketSecurityValidator.normalize_origin(origin)

        for pattern in allowed_origins:
            normalized_pattern = WebSocketSecurityValidator.normalize_origin(pattern)

            # Handle wildcard patterns
            if '*' in normalized_pattern:
                # Convert pattern to regex
                regex_pattern = normalized_pattern.replace('*', '.*')
                if re.match(f'^{regex_pattern}$', normalized_origin):
                    logger.info(f"Origin {origin} matched pattern {pattern}")
                    return True
            else:
                # Exact match
                if normalized_origin == normalized_pattern:
                    logger.info(f"Origin {origin} exactly matched {pattern}")
                    return True

        logger.warning(f"Origin {origin} not allowed. Allowed patterns: {allowed_origins}")
        return False

    @staticmethod
    def is_subprotocol_allowed(subprotocol: Optional[str], allowed_subprotocols: List[str]) -> bool:
        """
        Check if the WebSocket sub-protocol is allowed

        Args:
            subprotocol: The sub-protocol to validate (can be None)
            allowed_subprotocols: List of allowed sub-protocols

        Returns:
            bool: True if allowed, False otherwise
        """
        if subprotocol is None:
            logger.warning("Sub-protocol is None - not allowed")
            return False

        if subprotocol not in allowed_subprotocols:
            logger.warning(f"Sub-protocol {subprotocol} not allowed. Allowed: {allowed_subprotocols}")
            return False

        return True

    @staticmethod
    def validate_websocket_headers(websocket: WebSocket) -> Dict[str, Any]:
        """
        Validate WebSocket security headers

        Args:
            websocket: The WebSocket connection

        Returns:
            Dict containing validation results and extracted headers
        """
        headers = {}
        validation_result = {
            "origin_valid": False,
            "subprotocol_valid": False,
            "origin": None,
            "subprotocol": None,
            "user_agent": None,
            "host": None
        }

        # Extract headers
        if hasattr(websocket, 'headers'):
            for name, value in websocket.headers.items():
                headers[name.lower()] = value

            # Extract specific security headers
            validation_result["origin"] = headers.get('origin')
            validation_result["host"] = headers.get('host')
            validation_result["user_agent"] = headers.get('user-agent')

            # WebSocket sub-protocol might be in Sec-WebSocket-Protocol header
            subprotocol_header = headers.get('sec-websocket-protocol')
            if subprotocol_header:
                # Handle multiple sub-protocols (comma-separated)
                subprotocols = [p.strip() for p in subprotocol_header.split(',')]
                validation_result["subprotocol"] = subprotocols[0] if subprotocols else None

        # Validate origin
        validation_result["origin_valid"] = WebSocketSecurityValidator.is_origin_allowed(
            validation_result["origin"],
            settings.WEBSOCKET_ALLOWED_ORIGINS
        )

        # Validate sub-protocol
        validation_result["subprotocol_valid"] = WebSocketSecurityValidator.is_subprotocol_allowed(
            validation_result["subprotocol"],
            settings.WEBSOCKET_ALLOWED_SUBPROTOCOLS
        )

        # Log security validation
        logger.info(
            f"WebSocket security validation: "
            f"origin={validation_result['origin']} (valid: {validation_result['origin_valid']}), "
            f"subprotocol={validation_result['subprotocol']} (valid: {validation_result['subprotocol_valid']}), "
            f"host={validation_result['host']}, "
            f"user_agent={validation_result['user_agent'][:50] if validation_result['user_agent'] else None}..."
        )

        return validation_result


class JWTSecurityManager:
    """Enhanced JWT security manager for WebSocket connections"""

    def __init__(self):
        # Track invalidated tokens (in production, use Redis)
        self.invalidated_tokens: Set[str] = set()
        # Track active WebSocket sessions
        self.active_sessions: Dict[str, Dict[str, Any]] = {}
        # Track client sequence numbers for replay attack prevention
        self.client_sequences: Dict[str, int] = {}
        # Maximum session lifetime (8 hours)
        self.max_session_lifetime_seconds = 8 * 60 * 60
        # Token refresh grace period (5 minutes)
        self.token_refresh_grace_period = 5 * 60
        # Maximum concurrent sessions (reduced from 3 to 2 per engineer recommendation)
        self.max_concurrent_sessions = 2
        # Session lifetime in hours
        self.session_lifetime_hours = 8

    def invalidate_token(self, token: str, reason: str = "refresh") -> None:
        """
        Invalidate a JWT token to prevent replay attacks

        Args:
            token: JWT token to invalidate
            reason: Reason for invalidation
        """
        self.invalidated_tokens.add(token)
        logger.info(f"Token invalidated: reason={reason}")

    def is_token_invalidated(self, token: str) -> bool:
        """Check if token has been invalidated"""
        return token in self.invalidated_tokens

    def register_websocket_session(self, client_id: str, token: str, user_info: Dict[str, Any]) -> bool:
        """
        Register a new WebSocket session with session limits

        Args:
            client_id: Unique client identifier
            token: JWT token
            user_info: User information from token

        Returns:
            bool: True if registration successful, False if session limit reached
        """
        user_id = user_info.get("user_id")
        current_time = datetime.now(timezone.utc)

        # Count current sessions for this user
        user_session_count = sum(
            1 for session in self.active_sessions.values()
            if session.get("user_id") == user_id
        )

        # If limit reached, reject new session
        if user_session_count >= self.max_concurrent_sessions:
            logger.warning(f"Session limit reached for user {user_id}, rejecting new session {client_id}")
            return False

        # Initialize client sequence tracking
        self.client_sequences[client_id] = 0
        logger.info(f"Initialized sequence tracking for client {client_id}")

        # Register new session
        self.active_sessions[client_id] = {
            "client_id": client_id,
            "user_id": user_id,
            "token": token,
            "user_info": user_info,
            "session_start": current_time,
            "created_at": time.time(),
            "last_activity": time.time(),
            "max_lifetime": time.time() + self.session_lifetime_hours * 3600
        }

        logger.info(f"Registered WebSocket session {client_id} for user {user_id} ({user_session_count + 1}/{self.max_concurrent_sessions} sessions)")
        return True

    def validate_client_sequence(self, client_id: str, sequence: int) -> bool:
        """
        Validate client sequence number to prevent replay attacks

        Args:
            client_id: Client identifier
            sequence: Sequence number from client frame

        Returns:
            bool: True if sequence is valid, False if replay detected
        """
        if client_id not in self.client_sequences:
            logger.warning(f"No sequence tracking for client {client_id}")
            return False

        last_seen = self.client_sequences[client_id]

        # Sequence must be strictly increasing
        if sequence <= last_seen:
            logger.warning(f"Replay attack detected: client {client_id} sent sequence {sequence}, last seen {last_seen}")
            return False

        # Update last seen sequence
        self.client_sequences[client_id] = sequence
        logger.debug(f"Client {client_id} sequence validated: {sequence}")
        return True

    def reset_client_sequence(self, client_id: str) -> None:
        """Reset client sequence counter (e.g., on reconnection)"""
        if client_id in self.client_sequences:
            self.client_sequences[client_id] = 0
            logger.info(f"Client {client_id} sequence reset")

    def get_client_sequence_status(self, client_id: str) -> Dict[str, Any]:
        """Get sequence tracking status for client"""
        return {
            "client_id": client_id,
            "last_seen_sequence": self.client_sequences.get(client_id, 0),
            "tracking_active": client_id in self.client_sequences
        }

    def validate_session_lifetime(self, client_id: str) -> bool:
        """
        Check if session is within lifetime limits

        Args:
            client_id: Client identifier

        Returns:
            bool: True if session is valid, False if expired
        """
        if client_id not in self.active_sessions:
            return False

        session = self.active_sessions[client_id]
        current_time = datetime.now(timezone.utc)
        session_start = session.get("session_start")

        if not session_start:
            return False

        # Check if session has exceeded maximum lifetime
        session_duration = current_time - session_start
        max_duration = timedelta(hours=self.session_lifetime_hours)

        if session_duration > max_duration:
            logger.warning(f"Session {client_id} expired after {session_duration}")
            return False

        return True

    def terminate_session(self, client_id: str) -> None:
        """Terminate a WebSocket session"""
        if client_id in self.active_sessions:
            session = self.active_sessions[client_id]
            # Invalidate the session token
            self.invalidate_token(session["token"], "session_terminated")
            del self.active_sessions[client_id]
            logger.info(f"Session terminated: {client_id}")

        # Clean up sequence tracking
        if client_id in self.client_sequences:
            del self.client_sequences[client_id]
            logger.debug(f"Sequence tracking cleaned up for client {client_id}")

    def cleanup_expired_sessions(self):
        """Remove expired sessions from active tracking"""
        current_time = datetime.now(timezone.utc)
        expired_clients = []

        for client_id, session in self.active_sessions.items():
            session_start = session.get("session_start")
            if session_start:
                session_duration = current_time - session_start
                max_duration = timedelta(hours=self.session_lifetime_hours)

                if session_duration > max_duration:
                    expired_clients.append(client_id)

        # Remove expired sessions
        for client_id in expired_clients:
            logger.info(f"Cleaning up expired session: {client_id}")
            del self.active_sessions[client_id]
            # Clean up sequence tracking
            if client_id in self.client_sequences:
                del self.client_sequences[client_id]


# Global JWT security manager
jwt_security = JWTSecurityManager()
