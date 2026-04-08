"""
WebSocket connection manager with JWT authentication and connection pooling.
"""
import asyncio
import logging
import time
import weakref
from datetime import datetime, timezone
from typing import Optional, Dict, Any

from fastapi import WebSocket
from jose import jwt, JWTError

from app.core.config import settings
from app.core.llm_config import LLMConfig
from app.services.llm_manager import llm_manager
from app.services.streaming_pipeline import (
    EnhancedAsyncPipeline,
    FlowControlConfig,
    create_pipeline,
)

from .security import jwt_security

logger = logging.getLogger(__name__)

# Global pipeline instances for connection pooling
_pipeline_pool: Dict[str, weakref.ReferenceType] = {}
_pool_lock = asyncio.Lock()


class ConnectionManager:
    """Manage WebSocket connections with JWT authentication and connection pooling"""

    def __init__(self):
        self.active_connections: Dict[str, Dict[str, Any]] = {}
        self.pipeline_sessions: Dict[str, str] = {}  # session_id -> pipeline_id

    async def authenticate_websocket(self, websocket: WebSocket, token: str) -> Optional[Dict[str, Any]]:
        """Authenticate WebSocket connection using JWT token with enhanced security"""
        try:
            # Check if token has been invalidated
            if jwt_security.is_token_invalidated(token):
                logger.warning("Attempted use of invalidated JWT token")
                return None

            # Try Firebase JWT verification first (RS256 with Google's public keys)
            try:
                # Import Firebase verification (requires firebase-admin)
                import firebase_admin
                from firebase_admin import auth as firebase_auth
                from firebase_admin import credentials

                # Initialize Firebase Admin if not already done
                if not firebase_admin._apps:
                    # In production, use default credentials (works on Google Cloud)
                    # In development, you can set GOOGLE_APPLICATION_CREDENTIALS
                    try:
                        cred = credentials.ApplicationDefault()
                        firebase_admin.initialize_app(cred)
                        logger.info("Firebase Admin SDK initialized with Application Default Credentials")
                    except Exception as e:
                        logger.warning(f"Could not initialize Firebase Admin with default credentials: {e}")
                        # Fall back to manual verification for development
                        raise ValueError("Firebase Admin not available")

                # Verify Firebase ID token
                decoded_token = firebase_auth.verify_id_token(token)
                user_id = decoded_token.get('uid') or decoded_token.get('user_id') or decoded_token.get('sub')

                if not user_id:
                    logger.warning("Firebase JWT token missing user ID")
                    return None

                logger.info(f"Firebase WebSocket authentication successful for user: {user_id}")
                return {
                    "user_id": user_id,
                    "payload": decoded_token,
                    "token": token,
                    "auth_method": "firebase"
                }

            except Exception as firebase_error:
                logger.info(f"Firebase verification failed, trying manual RS256 verification: {firebase_error}")

                # Try manual RS256 verification with Google's public keys
                try:
                    import requests

                    # Get Google's public keys
                    google_keys_url = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
                    response = requests.get(google_keys_url, timeout=10)
                    google_public_keys = response.json()

                    # Extract key ID from token header
                    unverified_header = jwt.get_unverified_header(token)
                    kid = unverified_header.get('kid')

                    if not kid or kid not in google_public_keys:
                        raise ValueError("Invalid key ID in token header")

                    # Get the public key for this token
                    public_key = google_public_keys[kid]

                    # Verify the token with RS256
                    payload = jwt.decode(
                        token,
                        public_key,
                        algorithms=["RS256"],
                        audience="upliftapp-cd86e",  # Your Firebase project ID
                        issuer="https://securetoken.google.com/upliftapp-cd86e"
                    )

                    user_id = payload.get('user_id') or payload.get('sub')
                    if not user_id:
                        logger.warning("Manual RS256 JWT token missing user ID")
                        return None

                    logger.info(f"Manual RS256 WebSocket authentication successful for user: {user_id}")
                    return {
                        "user_id": user_id,
                        "payload": payload,
                        "token": token,
                        "auth_method": "manual_rs256"
                    }

                except Exception as rs256_error:
                    logger.warning(f"Manual RS256 verification failed: {rs256_error}")

                    # Fall back to local HS256 for development tokens
                    logger.info("Falling back to local HS256 verification for development")

                    payload = jwt.decode(
                        token,
                        settings.SECRET_KEY,
                        algorithms=["HS256"]
                    )

                    # Extract user information
                    user_id = payload.get("sub")
                    if not user_id:
                        logger.warning("Local HS256 JWT token missing user ID")
                        return None

                    # Check token expiration with grace period for refresh
                    exp = payload.get("exp")
                    current_time = datetime.now(timezone.utc).timestamp()

                    if exp and current_time > exp:
                        logger.warning("Local HS256 JWT token expired")
                        return None

                    # Check if token is close to expiration (within grace period)
                    if exp and (exp - current_time) < jwt_security.token_refresh_grace_period:
                        logger.info(f"Local HS256 token for user {user_id} is close to expiration, consider refresh")

                    logger.info(f"Local HS256 WebSocket authentication successful for user: {user_id}")
                    return {
                        "user_id": user_id,
                        "payload": payload,
                        "token": token,
                        "auth_method": "local_hs256"
                    }

        except JWTError as e:
            logger.warning(f"JWT authentication failed: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"Authentication error: {str(e)}")
            return None

    async def connect(self, websocket: WebSocket, client_id: str, user_info: Dict[str, Any]):
        """Accept WebSocket connection and register client with enhanced security"""
        await websocket.accept()

        # Session registration is now handled in the WebSocket endpoint before calling connect
        # to allow for proper session limit enforcement

        self.active_connections[client_id] = {
            "websocket": websocket,
            "user_info": user_info,
            "connected_at": datetime.now(),
            "last_activity": datetime.now(),
            "token": user_info.get("token")
        }

        logger.info(f"WebSocket client {client_id} connected for user {user_info['user_id']}")

    async def disconnect(self, client_id: str):
        """Remove client from active connections with security cleanup"""
        if client_id in self.active_connections:
            # Terminate JWT session
            jwt_security.terminate_session(client_id)

            del self.active_connections[client_id]
            logger.info(f"WebSocket client {client_id} disconnected")

        # Clean up pipeline session if exists
        if client_id in self.pipeline_sessions:
            pipeline_id = self.pipeline_sessions[client_id]
            del self.pipeline_sessions[client_id]

            # Clean up pipeline if no more clients using it
            await self._cleanup_unused_pipeline(pipeline_id)

    async def validate_client_session(self, client_id: str) -> bool:
        """Validate client session lifetime and token status"""
        if client_id not in self.active_connections:
            return False

        # Validate session lifetime
        if not jwt_security.validate_session_lifetime(client_id):
            await self.disconnect(client_id)
            return False

        # Update last activity
        self.active_connections[client_id]["last_activity"] = datetime.now()
        return True

    async def _cleanup_unused_pipeline(self, pipeline_id: str):
        """Clean up pipeline if no clients are using it"""
        clients_using_pipeline = [
            client_id for client_id, pid in self.pipeline_sessions.items()
            if pid == pipeline_id
        ]

        if not clients_using_pipeline:
            async with _pool_lock:
                if pipeline_id in _pipeline_pool:
                    pipeline_ref = _pipeline_pool[pipeline_id]
                    pipeline = pipeline_ref()
                    if pipeline:
                        try:
                            await pipeline.stop()
                            logger.info(f"Cleaned up unused pipeline: {pipeline_id}")
                        except Exception as e:
                            logger.error(f"Error cleaning up pipeline {pipeline_id}: {e}")
                    del _pipeline_pool[pipeline_id]

    async def get_or_create_pipeline(self, client_id: str, config: Optional[FlowControlConfig] = None) -> EnhancedAsyncPipeline:
        """Get existing pipeline or create new one for client"""
        # Use user-based pipeline pooling to share across sessions
        user_info = self.active_connections.get(client_id, {}).get("user_info", {})
        user_id = user_info.get("user_id", "anonymous")
        pipeline_id = f"pipeline_{user_id}"

        async with _pool_lock:
            # Check if pipeline exists and is still valid
            if pipeline_id in _pipeline_pool:
                pipeline_ref = _pipeline_pool[pipeline_id]
                pipeline = pipeline_ref()
                if pipeline and pipeline.state.value != "error":
                    self.pipeline_sessions[client_id] = pipeline_id
                    logger.info(f"Reusing existing pipeline {pipeline_id} for client {client_id} (state: {pipeline.state.value})")
                    return pipeline
                else:
                    # Clean up dead reference
                    del _pipeline_pool[pipeline_id]

            # Create new pipeline - create_pipeline already calls start() internally
            pipeline = await create_pipeline(config, llm_manager)
            # Note: pipeline is already started by create_pipeline function

            # Store weak reference to allow garbage collection
            _pipeline_pool[pipeline_id] = weakref.ref(pipeline)
            self.pipeline_sessions[client_id] = pipeline_id

            logger.info(f"Created new pipeline {pipeline_id} for client {client_id} (state: {pipeline.state.value})")
            return pipeline


# Global connection manager
connection_manager = ConnectionManager()
