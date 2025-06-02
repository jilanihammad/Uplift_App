from fastapi import APIRouter, UploadFile, File, HTTPException, Depends, Request, Form, BackgroundTasks, WebSocket, WebSocketDisconnect, Query
from fastapi.responses import JSONResponse
from typing import Optional, Dict, Any, Set, List
import logging
import base64
import json
import os
import aiofiles
import time
import tempfile
import asyncio
import weakref
from datetime import datetime, timezone, timedelta
import fnmatch
import re

# Use unified LLM manager instead of individual services
from app.services.llm_manager import llm_manager

# Import our enhanced streaming pipeline
from app.services.streaming_pipeline import (
    EnhancedAsyncPipeline, 
    StreamingMessage, 
    FlowControlConfig,
    create_pipeline
)

# JWT authentication with enhanced security
from jose import jwt, JWTError
from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()

# Global pipeline instances for connection pooling
_pipeline_pool: Dict[str, weakref.ReferenceType] = {}
_pool_lock = asyncio.Lock()

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

class TextInputRateLimiter:
    """
    Rate limiter for text input to prevent abuse
    Implements Step 12: Text Input Rate Limiting (30 requests/minute per user)
    """
    
    def __init__(self):
        # Track requests per user ID
        self.user_requests: Dict[str, List[float]] = {}
        # Track requests per IP (fallback)
        self.ip_requests: Dict[str, List[float]] = {}
        # Lock for thread-safe operations
        self._lock = asyncio.Lock()
        # Rate limit configuration
        self.requests_per_minute = 30  # Step 12: 30 requests per minute per user
        
    async def is_allowed(self, user_id: str, client_ip: Optional[str] = None) -> Dict[str, Any]:
        """
        Check if user is allowed to make a request based on rate limiting
        
        Args:
            user_id: User identifier
            client_ip: Client IP address (fallback if user_id is None)
            
        Returns:
            Dict with allowed status, request count, and reset time
        """
        async with self._lock:
            current_time = time.time()
            
            # Use user_id or fall back to IP
            key = user_id if user_id else client_ip
            if not key:
                return {
                    "allowed": False,
                    "user_request_count": 0,
                    "reason": "No identifier provided",
                    "reset_time": current_time + 60
                }
            
            # Choose the appropriate tracking dict
            requests_dict = self.user_requests if user_id else self.ip_requests
            
            # Clean up old requests (older than 1 minute)
            if key in requests_dict:
                cutoff_time = current_time - 60
                requests_dict[key] = [req_time for req_time in requests_dict[key] if req_time > cutoff_time]
            else:
                requests_dict[key] = []
            
            # Add current request
            requests_dict[key].append(current_time)
            
            current_count = len(requests_dict[key])
            
            # Check if limit exceeded
            allowed = current_count <= self.requests_per_minute
            
            # Calculate reset time (when oldest request will be outside the window)
            reset_time = current_time + 60
            if requests_dict[key]:
                oldest_request = min(requests_dict[key])
                reset_time = oldest_request + 60
            
            return {
                "allowed": allowed,
                "user_request_count": current_count,
                "requests_per_minute": self.requests_per_minute,
                "reset_time": reset_time,
                "window_start": current_time - 60
            }

    async def get_user_status(self, user_id: str) -> Dict[str, Any]:
        """
        Get current rate limit status for a user
        
        Args:
            user_id: User identifier
            
        Returns:
            Dict with user rate limit status
        """
        async with self._lock:
            current_time = time.time()
            
            # Clean up old requests
            if user_id in self.user_requests:
                cutoff_time = current_time - 60
                self.user_requests[user_id] = [req_time for req_time in self.user_requests[user_id] if req_time > cutoff_time]
                current_count = len(self.user_requests[user_id])
            else:
                current_count = 0
            
            return {
                "requests_made": current_count,
                "limit_per_minute": self.requests_per_minute,
                "remaining": max(0, self.requests_per_minute - current_count),
                "reset_time": current_time + 60
            }

# Global instances
text_rate_limiter = TextInputRateLimiter()

class JWTSecurityManager:
    """Enhanced JWT security manager for WebSocket connections"""
    
    def __init__(self):
        # Track invalidated tokens (in production, use Redis)
        self.invalidated_tokens: Set[str] = set()
        # Track active WebSocket sessions
        self.active_sessions: Dict[str, Dict[str, Any]] = {}
        # Maximum session lifetime (8 hours)
        self.max_session_lifetime_seconds = 8 * 60 * 60
        # Token refresh grace period (5 minutes)
        self.token_refresh_grace_period = 5 * 60
        # Maximum concurrent sessions
        self.max_concurrent_sessions = 3
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
        
        # In production, store in Redis with expiration
        # redis.setex(f"invalidated_token:{token}", settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60, reason)
        
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
        
        logger.info(f"Registered WebSocket session {client_id} for user {user_id}")
        return True
        
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

# Global JWT security manager
jwt_security = JWTSecurityManager()

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
            
            # Decode and verify JWT token
            payload = jwt.decode(
                token, 
                settings.SECRET_KEY, 
                algorithms=["HS256"]
            )
            
            # Extract user information
            user_id = payload.get("sub")
            if not user_id:
                logger.warning("JWT token missing user ID")
                return None
                
            # Check token expiration with grace period for refresh
            exp = payload.get("exp")
            current_time = datetime.now(timezone.utc).timestamp()
            
            if exp and current_time > exp:
                logger.warning("JWT token expired")
                return None
                
            # Check if token is close to expiration (within grace period)
            if exp and (exp - current_time) < jwt_security.token_refresh_grace_period:
                logger.info(f"Token for user {user_id} is close to expiration, consider refresh")
                
            logger.info(f"WebSocket authentication successful for user: {user_id}")
            return {
                "user_id": user_id,
                "payload": payload,
                "token": token
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
        
        # Register session with JWT security manager
        token = user_info.get("token")
        jwt_security.register_websocket_session(client_id, token, user_info)
        
        self.active_connections[client_id] = {
            "websocket": websocket,
            "user_info": user_info,
            "connected_at": datetime.now(),
            "last_activity": datetime.now(),
            "token": token
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
                    logger.info(f"Reusing existing pipeline {pipeline_id} for client {client_id}")
                    return pipeline
                else:
                    # Clean up dead reference
                    del _pipeline_pool[pipeline_id]
                    
            # Create new pipeline
            pipeline = await create_pipeline(config)
            await pipeline.start()
            
            # Store weak reference to allow garbage collection
            _pipeline_pool[pipeline_id] = weakref.ref(pipeline)
            self.pipeline_sessions[client_id] = pipeline_id
            
            logger.info(f"Created new pipeline {pipeline_id} for client {client_id}")
            return pipeline

# Global connection manager
connection_manager = ConnectionManager()

@router.get("/ping")
async def ping_endpoint():
    """Health check endpoint"""
    return {"status": "alive", "timestamp": datetime.now().isoformat()}

@router.get("/rate-limit-status")
async def get_rate_limit_status(
    token: str = Query(..., description="JWT authentication token")
):
    """
    Get current rate limit status for the authenticated user
    Useful for frontend to display rate limit information
    """
    try:
        # Decode JWT token to get user ID
        payload = jwt.decode(
            token, 
            settings.SECRET_KEY, 
            algorithms=["HS256"]
        )
        
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token - missing user ID")
            
        # Check token expiration
        exp = payload.get("exp")
        current_time = datetime.now(timezone.utc).timestamp()
        
        if exp and current_time > exp:
            raise HTTPException(status_code=401, detail="Token expired")
        
        # Get rate limit status
        status = await text_rate_limiter.get_user_status(user_id)
        
        return {
            "user_id": user_id,
            "rate_limit_status": status,
            "timestamp": datetime.now().isoformat()
        }
        
    except JWTError as e:
        logger.warning(f"JWT decode error in rate limit status: {str(e)}")
        raise HTTPException(status_code=401, detail="Invalid token")
    except Exception as e:
        logger.error(f"Error getting rate limit status: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.websocket("/ws/tts/speech")
async def websocket_streaming_tts(
    websocket: WebSocket,
    token: str = Query(..., description="JWT authentication token"),
    conversation_id: str = Query(..., description="Unique conversation identifier"),
    voice: str = Query(default="sage", description="TTS voice to use"),
    format: str = Query(default="wav", description="Audio format (wav for lowest latency)")
):
    """
    Enhanced WebSocket endpoint for real-time streaming TTS speech generation
    Integrates with the enhanced pipeline for sub-400ms latency
    
    Features:
    - JWT authentication
    - Connection pooling and reuse
    - Flow control and backpressure
    - Jitter buffer support
    - Sequence preservation
    - Performance monitoring
    - Binary WebSocket frame support for 33% bandwidth reduction
    - Origin/Sub-protocol validation for security
    """
    client_id = f"client_{int(time.time() * 1000)}_{id(websocket)}"
    
    try:
        # Step 11: Validate WebSocket security headers (origin and sub-protocol)
        security_validation = WebSocketSecurityValidator.validate_websocket_headers(websocket)
        
        # Check origin validation
        if not security_validation["origin_valid"]:
            logger.warning(f"WebSocket connection rejected - invalid origin: {security_validation['origin']}")
            await websocket.close(code=1003, reason="Origin not allowed")
            return
            
        # Check sub-protocol validation
        if not security_validation["subprotocol_valid"]:
            logger.warning(f"WebSocket connection rejected - invalid sub-protocol: {security_validation['subprotocol']}")
            await websocket.close(code=1002, reason="Sub-protocol not supported")
            return
        
        # Log successful security validation
        logger.info(
            f"WebSocket security validation passed for client {client_id}: "
            f"origin={security_validation['origin']}, "
            f"subprotocol={security_validation['subprotocol']}"
        )
        
        # Authenticate WebSocket connection
        user_info = await connection_manager.authenticate_websocket(websocket, token)
        if not user_info:
            await websocket.close(code=1008, reason="Authentication failed")
            return
            
        # Check for binary frame support in headers
        supports_binary = False
        if hasattr(websocket, 'headers'):
            # Check for custom header indicating binary frame support
            binary_support_header = websocket.headers.get('x-supports-binary-frames', '').lower()
            supports_binary = binary_support_header == 'true'
        
        # Connect client
        await connection_manager.connect(websocket, client_id, user_info)
        
        # Set binary frame capability on websocket object
        websocket._supports_binary_frames = supports_binary
        
        # Get or create pipeline for this client
        config = FlowControlConfig()
        pipeline = await connection_manager.get_or_create_pipeline(client_id, config)
        
        # Register client with pipeline
        init_frame = await pipeline.register_client(client_id, websocket)
        
        # Add binary frame capability to init frame
        init_frame["capabilities"] = {
            "binary_frames": supports_binary,
            "max_frame_size": 65536,  # 64KB max frame size
            "supported_formats": ["wav", "opus", "aac"]
        }
        
        # Include security validation info in capabilities
        init_frame["security"] = {
            "origin_validated": security_validation["origin_valid"],
            "subprotocol": security_validation["subprotocol"],
            "secure_connection": True
        }
        
        # Send initialization frame with jitter buffer guidance
        await websocket.send_text(json.dumps(init_frame))
        
        logger.info(f"Streaming WebSocket client {client_id} ready for conversation {conversation_id} (binary_frames: {supports_binary})")
        
        # Main message processing loop
        while True:
            try:
                # Receive message from client
                data = await websocket.receive_text()
                message_data = json.loads(data)
                
                message_type = message_data.get("type", "text")
                
                if message_type == "text":
                    # Step 12: Check rate limiting before processing text message
                    client_ip = None
                    if hasattr(websocket, 'client') and hasattr(websocket.client, 'host'):
                        client_ip = websocket.client.host
                    
                    rate_limit_result = await text_rate_limiter.is_allowed(
                        user_info["user_id"], 
                        client_ip
                    )
                    
                    if not rate_limit_result["allowed"]:
                        # Send rate limit error with detailed information
                        await websocket.send_text(json.dumps({
                            "type": "rate_limit_exceeded",
                            "error": "Text input rate limit exceeded",
                            "limit_info": {
                                "requests_made": rate_limit_result["user_request_count"],
                                "limit_per_minute": rate_limit_result["requests_per_minute"],
                                "window_seconds": rate_limit_result["window_start"],
                                "reset_time": rate_limit_result["reset_time"],
                                "retry_after_seconds": max(0, rate_limit_result["reset_time"] - time.time())
                            },
                            "timestamp": datetime.now().isoformat()
                        }))
                        logger.warning(
                            f"Rate limit exceeded for user {user_info['user_id']} (client {client_id}): "
                            f"{rate_limit_result['user_request_count']}/{rate_limit_result['requests_per_minute']} requests"
                        )
                        continue
                    
                    # Process text message through pipeline
                    text_content = message_data.get("message", "")
                    priority = message_data.get("priority", 1)
                    
                    if not text_content.strip():
                        await websocket.send_text(json.dumps({
                            "type": "error",
                            "error": "Empty message content"
                        }))
                        continue
                        
                    # Create streaming message
                    streaming_message = StreamingMessage(
                        message_id=f"msg_{int(time.time() * 1000)}",
                        conversation_id=conversation_id,
                        user_message=text_content,
                        priority=priority,
                        metadata={
                            "client_id": client_id,
                            "voice": voice,
                            "format": format,
                            "user_id": user_info["user_id"],
                            "supports_binary": supports_binary,
                            "rate_limit_info": {
                                "requests_count": rate_limit_result["user_request_count"],
                                "remaining": rate_limit_result["requests_per_minute"] - rate_limit_result["user_request_count"]
                            }
                        }
                    )
                    
                    # Add message to pipeline
                    success = await pipeline.add_message(streaming_message)
                    
                    if not success:
                        await websocket.send_text(json.dumps({
                            "type": "error", 
                            "error": "Pipeline queue full - please try again"
                        }))
                        continue
                        
                    # Send acknowledgment with rate limit info
                    await websocket.send_text(json.dumps({
                        "type": "message_received",
                        "message_id": streaming_message.message_id,
                        "timestamp": streaming_message.timestamp.isoformat(),
                        "rate_limit_status": {
                            "requests_used": rate_limit_result["user_request_count"],
                            "limit": rate_limit_result["requests_per_minute"],
                            "remaining": rate_limit_result["requests_per_minute"] - rate_limit_result["user_request_count"],
                            "reset_time": rate_limit_result["reset_time"]
                        }
                    }))
                    
                elif message_type == "ping":
                    # Handle ping/pong for connection keepalive
                    await websocket.send_text(json.dumps({
                        "type": "pong",
                        "timestamp": datetime.now().isoformat()
                    }))
                    
                elif message_type == "interrupt":
                    # Handle client interruption with pipeline drainage
                    logger.info(f"Client {client_id} requested interruption")
                    
                    # Validate session before processing interrupt
                    if not await connection_manager.validate_client_session(client_id):
                        await websocket.send_text(json.dumps({
                            "type": "error",
                            "error": "Session expired or invalid"
                        }))
                        break
                    
                    # Request interrupt from pipeline
                    interrupt_success = await pipeline.request_interrupt(client_id)
                    
                    if interrupt_success:
                        # Pipeline will send interrupt_ack when drainage is complete
                        logger.info(f"Interrupt processing initiated for client {client_id}")
                    else:
                        # Send immediate response if interrupt couldn't be processed
                        await websocket.send_text(json.dumps({
                            "type": "interrupt_failed",
                            "reason": "Pipeline busy or already interrupting",
                            "timestamp": datetime.now().isoformat()
                        }))
                    
                else:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "error": f"Unknown message type: {message_type}"
                    }))
                    
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "error": "Invalid JSON format"
                }))
                continue
            except Exception as e:
                logger.error(f"Error processing WebSocket message for {client_id}: {str(e)}")
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "error": f"Processing error: {str(e)}"
                }))
                continue
                
    except WebSocketDisconnect:
        logger.info(f"WebSocket client {client_id} disconnected normally")
    except Exception as e:
        logger.error(f"WebSocket error for client {client_id}: {str(e)}")
        try:
            await websocket.close(code=1011, reason="Internal server error")
        except:
            pass  # WebSocket might already be closed
    finally:
        # Clean up client connection and pipeline session
        await connection_manager.disconnect(client_id)
        
        # Unregister from pipeline if it exists
        if client_id in connection_manager.pipeline_sessions:
            pipeline_id = connection_manager.pipeline_sessions[client_id]
            if pipeline_id in _pipeline_pool:
                pipeline_ref = _pipeline_pool[pipeline_id]
                pipeline = pipeline_ref()
                if pipeline:
                    try:
                        await pipeline.unregister_client(client_id)
                    except Exception as e:
                        logger.error(f"Error unregistering client {client_id}: {e}")

@router.post("/synthesize", response_class=JSONResponse)
async def synthesize_voice(request: Request):
    """
    Generate voice from text using TTS service via unified LLM manager
    """
    try:
        data = await request.json()
        text = data.get("text", "")
        voice = data.get("voice", None)
        
        # Extract format parameters
        format_params = {}
        
        # Default to opus/ogg for optimal compatibility
        format_params["response_format"] = data.get("format", "opus")  # Default format is now opus
        
        # Add voice if provided
        if voice:
            format_params["voice"] = voice
            
        if not text:
            return JSONResponse({"error": "No text provided"}, status_code=400)
            
        logger.info(f"Synthesizing voice for text: {text[:30]}... with format: {format_params}")
        
        # Create output directory if it doesn't exist
        os.makedirs("static/audio", exist_ok=True)
        
        # Generate unique filename
        timestamp = int(time.time())
        extension = ".ogg" if format_params["response_format"] in ["opus", "ogg_opus"] else ".mp3"
        output_file = f"static/audio/tts_{timestamp}{extension}"
        
        # Generate audio using unified manager
        success = await llm_manager.text_to_speech(text, output_file, **format_params)
        
        if not success:
            return JSONResponse({"error": "Failed to generate speech"}, status_code=500)
            
        # Return URL to the generated audio file
        audio_url = f"/static/audio/{os.path.basename(output_file)}"
        return JSONResponse({"url": audio_url})
        
    except Exception as e:
        logger.error(f"Error synthesizing voice: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)

@router.post("/transcribe", response_class=JSONResponse)
async def transcribe_audio(file: UploadFile = File(...)):
    """
    Transcribe audio file to text using unified LLM manager
    """
    try:
        if not file:
            return JSONResponse({"error": "No file provided"}, status_code=400)
            
        logger.info(f"Transcribing audio file: {file.filename}")
        
        # Save uploaded file to temporary location
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=f".{file.filename.split('.')[-1]}")
        temp.write(await file.read())
        temp.close()
        
        try:
            # Use unified LLM manager for transcription
            text = await llm_manager.transcribe_audio(temp.name)
            
            if not text:
                return JSONResponse({"error": "Failed to transcribe audio"}, status_code=500)
                
            return JSONResponse({"text": text})
            
        finally:
            # Clean up temp file
            os.remove(temp.name)
        
    except Exception as e:
        logger.error(f"Error transcribing audio: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)

@router.post("/tts", description="Convert text to speech")
async def text_to_speech(
    text: str = Form(...), 
    format: str = Form("opus"), 
    voice: str = Form("sage"),
    background_tasks: BackgroundTasks = None
):
    logger.info(f"Received TTS request: {text[:50]}...")
    
    try:
        # Create output directory if it doesn't exist
        os.makedirs("static/audio", exist_ok=True)
        
        # Handle file extension based on format
        extension = ".ogg" if format in ["opus", "ogg_opus"] else ".mp3"
        output_file = f"static/audio/tts_{int(time.time())}{extension}"
        
        logger.info(f"Using TTS parameters: format={format}, voice={voice}")
        
        # Use unified LLM manager for TTS
        success = await llm_manager.text_to_speech(
            text, 
            output_file, 
            response_format=format,
            voice=voice
        )
        
        if not success:
            logger.error("TTS failed via unified LLM manager")
            raise HTTPException(status_code=500, detail="Failed to convert text to speech")
        
        logger.info(f"TTS successful, audio saved to {output_file}")
        return {
            "status": "success",
            "message": "Text converted to speech successfully",
            "audio_url": f"/static/audio/{os.path.basename(output_file)}"
        }
        
    except Exception as e:
        logger.error(f"Error in TTS endpoint: {str(e)}")
        logger.exception("TTS error details:")
        raise HTTPException(status_code=500, detail=f"Failed to convert text to speech: {str(e)}")

@router.post("/voice/transcribe_file")
async def transcribe_file(file: UploadFile = File(...)):
    try:
        # Save the uploaded file to a temp location
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp3")
        temp.write(await file.read())
        temp.close()

        try:
            # Use unified LLM manager for transcription
            transcription = await llm_manager.transcribe_audio(temp.name)
            return {"text": transcription}
            
        finally:
            # Clean up temp file
            os.remove(temp.name)
            
    except Exception as e:
        logger.error(f"Error in transcribe_file: {str(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)

@router.websocket("/ws/tts")
async def websocket_tts(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
                text = payload.get("text")
                voice = payload.get("voice", "sage")
                params = payload.get("params", {})
                response_format = params.get("response_format", "opus")  # Default to opus

                if not text:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "detail": "No text provided"
                    }))
                    continue

                try:
                    # Stream audio using unified manager
                    async for b64_chunk in llm_manager.stream_text_to_speech(
                        text,
                        voice=voice,
                        response_format=response_format
                    ):
                        await websocket.send_text(json.dumps({
                            "type": "audio_chunk",
                            "data": b64_chunk,
                            "format": response_format
                        }))
                    # When done, send a 'done' message
                    await websocket.send_text(json.dumps({
                        "type": "done",
                        "format": response_format
                    }))
                except Exception as tts_error:
                    logger.error(f"TTS WebSocket error: {str(tts_error)}")
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "detail": f"TTS error: {str(tts_error)}"
                    }))
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "detail": "Invalid JSON"
                }))
    except WebSocketDisconnect:
        logger.info("WebSocket TTS disconnected")
    except Exception as e:
        logger.error(f"WebSocket TTS error: {str(e)}")
        try:
            await websocket.send_text(json.dumps({
                "type": "error",
                "detail": str(e)
            }))
            await websocket.close()
        except:
            pass  # WebSocket might already be closed 