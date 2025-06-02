"""
Test suite for streaming TTS enhancements (Steps 7-12)
Tests the new production features: Binary frames, multi-format support, JWT security, 
interrupt handling, origin validation, and rate limiting.
"""
import pytest
import asyncio
import json
import time
from datetime import datetime, timezone, timedelta
from fastapi import WebSocket
from unittest.mock import AsyncMock, MagicMock, patch
from app.api.endpoints.voice import (
    WebSocketSecurityValidator, 
    TextInputRateLimiter, 
    JWTSecurityManager,
    ConnectionManager
)
from app.services.streaming_pipeline import (
    EnhancedAsyncPipeline, 
    FlowControlConfig, 
    StreamingMessage,
    FlowControlState
)

class TestWebSocketSecurityValidator:
    """Test Step 11: Origin/Sub-protocol Validation"""
    
    def test_normalize_origin(self):
        """Test origin normalization"""
        validator = WebSocketSecurityValidator()
        
        # Test various origin formats
        assert validator.normalize_origin("https://localhost:3000") == "https://localhost:3000"
        assert validator.normalize_origin("http://localhost:3000/") == "http://localhost:3000"
        assert validator.normalize_origin("capacitor://localhost") == "capacitor://localhost"
        
    def test_origin_validation(self):
        """Test origin validation against allowed list"""
        validator = WebSocketSecurityValidator()
        allowed_origins = [
            "https://localhost:*",
            "capacitor://localhost",
            "https://*.vercel.app"
        ]
        
        # Test exact matches
        assert validator.is_origin_allowed("capacitor://localhost", allowed_origins)
        
        # Test wildcard matches
        assert validator.is_origin_allowed("https://localhost:3000", allowed_origins)
        assert validator.is_origin_allowed("https://myapp.vercel.app", allowed_origins)
        
        # Test rejections
        assert not validator.is_origin_allowed("https://evil.com", allowed_origins)
        assert not validator.is_origin_allowed("http://localhost:3000", allowed_origins)  # Wrong protocol
        
    def test_subprotocol_validation(self):
        """Test sub-protocol validation"""
        validator = WebSocketSecurityValidator()
        allowed_subprotocols = ["ai-therapist-v1", "streaming-tts"]
        
        # Test valid protocols
        assert validator.is_subprotocol_allowed("ai-therapist-v1", allowed_subprotocols)
        assert validator.is_subprotocol_allowed("streaming-tts", allowed_subprotocols)
        
        # Test invalid protocols
        assert not validator.is_subprotocol_allowed("evil-protocol", allowed_subprotocols)
        assert not validator.is_subprotocol_allowed(None, allowed_subprotocols)

class TestTextInputRateLimiter:
    """Test Step 12: Text Input Rate Limiting"""
    
    @pytest.mark.asyncio
    async def test_rate_limiting_basic(self):
        """Test basic rate limiting functionality"""
        limiter = TextInputRateLimiter()
        user_id = "test_user_123"
        
        # First request should be allowed
        result = await limiter.is_allowed(user_id)
        assert result["allowed"] is True
        assert result["user_request_count"] == 1
        
        # Rapid requests should be tracked
        for i in range(5):
            result = await limiter.is_allowed(user_id)
            assert result["user_request_count"] == i + 2
            
    @pytest.mark.asyncio
    async def test_rate_limit_exceeded(self):
        """Test rate limit exceeded scenario"""
        limiter = TextInputRateLimiter()
        limiter.requests_per_minute = 5  # Set low limit for testing
        user_id = "test_user_456"
        
        # Make requests up to the limit
        for i in range(5):
            result = await limiter.is_allowed(user_id)
            assert result["allowed"] is True
            
        # Next request should be denied
        result = await limiter.is_allowed(user_id)
        assert result["allowed"] is False
        assert result["user_request_count"] == 6
        assert "reset_time" in result
        
    @pytest.mark.asyncio
    async def test_rate_limit_per_ip_fallback(self):
        """Test IP-based rate limiting when user ID unavailable"""
        limiter = TextInputRateLimiter()
        client_ip = "192.168.1.100"
        
        # Test with just IP (no user ID)
        result = await limiter.is_allowed(None, client_ip)
        assert result["allowed"] is True
        assert result["user_request_count"] == 1  # Should track by IP
        
    @pytest.mark.asyncio
    async def test_rate_limit_cleanup(self):
        """Test cleanup of old request records"""
        limiter = TextInputRateLimiter()
        user_id = "test_user_cleanup"
        
        # Make request and manually age it
        await limiter.is_allowed(user_id)
        
        # Simulate old request by manipulating timestamp
        old_timestamp = time.time() - 120  # 2 minutes ago
        limiter.user_requests[user_id] = [old_timestamp]
        
        # New request should trigger cleanup
        result = await limiter.is_allowed(user_id)
        assert result["user_request_count"] == 1  # Old request cleaned up
        
    @pytest.mark.asyncio
    async def test_get_user_status(self):
        """Test user status retrieval"""
        limiter = TextInputRateLimiter()
        user_id = "test_user_status"
        
        # Make some requests
        await limiter.is_allowed(user_id)
        await limiter.is_allowed(user_id)
        
        # Check status
        status = await limiter.get_user_status(user_id)
        assert status["requests_made"] == 2
        assert status["limit_per_minute"] == limiter.requests_per_minute
        assert status["remaining"] == limiter.requests_per_minute - 2

class TestJWTSecurityManager:
    """Test Step 9: Enhanced JWT Security"""
    
    def test_token_invalidation(self):
        """Test token invalidation functionality"""
        manager = JWTSecurityManager()
        test_token = "test_token_123"
        
        # Initially token should not be invalidated
        assert not manager.is_token_invalidated(test_token)
        
        # Invalidate token
        manager.invalidate_token(test_token, "refresh")
        
        # Now token should be invalidated
        assert manager.is_token_invalidated(test_token)
        
    def test_websocket_session_registration(self):
        """Test WebSocket session registration and limits"""
        manager = JWTSecurityManager()
        user_info = {"user_id": "test_user", "email": "test@example.com"}
        token = "session_token_123"
        
        # Register first session
        result = manager.register_websocket_session("client_1", token, user_info)
        assert result is True
        
        # Register more sessions for same user
        manager.register_websocket_session("client_2", token, user_info)
        manager.register_websocket_session("client_3", token, user_info)
        
        # Fourth session should be rejected (limit is 3)
        result = manager.register_websocket_session("client_4", token, user_info)
        assert result is False
        
    def test_session_lifetime_validation(self):
        """Test session lifetime validation"""
        manager = JWTSecurityManager()
        client_id = "test_client"
        
        # Register session
        user_info = {"user_id": "test_user", "email": "test@example.com"}
        manager.register_websocket_session(client_id, "token", user_info)
        
        # Should be valid initially
        assert manager.validate_session_lifetime(client_id) is True
        
        # Manually set session start time to past the limit
        session_start = datetime.now(timezone.utc) - timedelta(hours=9)  # 9 hours ago
        manager.active_sessions[client_id]["session_start"] = session_start
        
        # Should now be invalid
        assert manager.validate_session_lifetime(client_id) is False
        
    def test_session_cleanup(self):
        """Test cleanup of expired sessions"""
        manager = JWTSecurityManager()
        
        # Create expired session
        client_id = "expired_client"
        user_info = {"user_id": "test_user", "email": "test@example.com"}
        manager.register_websocket_session(client_id, "token", user_info)
        
        # Manually expire the session
        session_start = datetime.now(timezone.utc) - timedelta(hours=9)
        manager.active_sessions[client_id]["session_start"] = session_start
        
        # Run cleanup
        manager.cleanup_expired_sessions()
        
        # Session should be removed
        assert client_id not in manager.active_sessions

class TestStreamingPipelineEnhancements:
    """Test Steps 7, 8, 10: Binary frames, multi-format, interrupt handling"""
    
    @pytest.mark.asyncio
    async def test_binary_frame_preparation(self):
        """Test Step 7: Binary WebSocket frame support"""
        config = FlowControlConfig()
        pipeline = EnhancedAsyncPipeline(config)
        
        # Create test audio chunk
        from app.services.streaming_pipeline import AudioChunk, BoundaryType
        test_chunk = AudioChunk(
            chunk_id="test_chunk_1",
            sentence_id="sentence_1", 
            sequence=1,
            audio_data=b"fake_audio_data",
            is_sentence_end=True,
            boundary_type=BoundaryType.SENTENCE_END
        )
        
        # Test binary frame preparation
        metadata, binary_data = pipeline._prepare_audio_frame(test_chunk, 1, use_binary=True)
        
        assert "type" in metadata
        assert metadata["type"] == "audio_chunk"
        assert binary_data == b"fake_audio_data"
        assert metadata["binary_size"] == len(b"fake_audio_data")
        assert "audio_data" not in metadata  # Should not be in metadata for binary
        
        # Test JSON frame preparation (backward compatibility)
        metadata, binary_data = pipeline._prepare_audio_frame(test_chunk, 1, use_binary=False)
        
        assert binary_data is None
        assert "audio_data" in metadata  # Should be base64 encoded in metadata
        assert "binary_size" not in metadata
        
    @pytest.mark.asyncio
    async def test_network_quality_assessment(self):
        """Test Step 8: Network quality assessment for format selection"""
        config = FlowControlConfig()
        pipeline = EnhancedAsyncPipeline(config)
        
        # Test poor network conditions
        poor_metrics = {
            "rtt_ms": 1000,
            "packet_loss_percent": 5.0,
            "bandwidth_mbps": 0.5,
            "jitter_ms": 100
        }
        quality = pipeline.assess_network_quality(poor_metrics)
        assert quality == "poor"
        
        # Test good network conditions
        good_metrics = {
            "rtt_ms": 50,
            "packet_loss_percent": 0.1,
            "bandwidth_mbps": 10.0,
            "jitter_ms": 5
        }
        quality = pipeline.assess_network_quality(good_metrics)
        assert quality == "good"
        
        # Test medium network conditions
        medium_metrics = {
            "rtt_ms": 300,
            "packet_loss_percent": 1.0,
            "bandwidth_mbps": 2.0,
            "jitter_ms": 20
        }
        quality = pipeline.assess_network_quality(medium_metrics)
        assert quality == "medium"
        
    @pytest.mark.asyncio
    async def test_optimal_format_selection(self):
        """Test Step 8: Optimal audio format selection"""
        config = FlowControlConfig()
        pipeline = EnhancedAsyncPipeline(config)
        
        # Test format selection for poor network
        client_caps = {"supported_formats": ["wav", "opus", "aac"]}
        format_choice = pipeline.select_optimal_format("poor", client_caps)
        assert format_choice == "opus"  # Best compression for poor networks
        
        # Test format selection for good network  
        format_choice = pipeline.select_optimal_format("good", client_caps)
        assert format_choice == "wav"  # Lowest latency for good networks
        
        # Test format selection for medium network
        format_choice = pipeline.select_optimal_format("medium", client_caps)
        assert format_choice == "aac"  # Balanced choice
        
        # Test fallback when client doesn't support optimal format
        limited_caps = {"supported_formats": ["wav"]}
        format_choice = pipeline.select_optimal_format("poor", limited_caps)
        assert format_choice == "wav"  # Falls back to supported format
        
    @pytest.mark.asyncio
    async def test_interrupt_handling(self):
        """Test Step 10: Interrupt acknowledgment protocol"""
        config = FlowControlConfig()
        pipeline = EnhancedAsyncPipeline(config)
        
        # Start pipeline
        await pipeline.start()
        
        # Test interrupt request
        client_id = "test_client"
        interrupt_success = await pipeline.request_interrupt(client_id)
        assert interrupt_success is True
        
        # Pipeline should be in interrupting state
        assert pipeline.flow_control_state == FlowControlState.INTERRUPTING
        
        # Test pipeline drainage
        await pipeline.drain_pipeline()
        
        # Pipeline should be in draining state
        assert pipeline.flow_control_state == FlowControlState.DRAINING
        
        # Test interrupt acknowledgment
        await pipeline.send_interrupt_ack()
        
        # Clean up
        await pipeline.stop()
        
    @pytest.mark.asyncio 
    async def test_format_parameters(self):
        """Test format-specific parameters"""
        config = FlowControlConfig()
        pipeline = EnhancedAsyncPipeline(config)
        
        # Test WAV parameters
        wav_params = pipeline.get_format_parameters("wav")
        assert wav_params["sample_rate"] == 24000
        assert wav_params["channels"] == 1
        assert wav_params["bit_depth"] == 16
        
        # Test Opus parameters
        opus_params = pipeline.get_format_parameters("opus")
        assert opus_params["sample_rate"] == 24000
        assert opus_params["bitrate"] == 32000
        assert opus_params["compression"] == "high"
        
        # Test AAC parameters
        aac_params = pipeline.get_format_parameters("aac")
        assert aac_params["sample_rate"] == 48000
        assert aac_params["bitrate"] == 64000
        assert aac_params["compression"] == "balanced"
        
        # Test unsupported format
        unknown_params = pipeline.get_format_parameters("unknown")
        assert unknown_params == wav_params  # Should default to WAV

if __name__ == "__main__":
    pytest.main([__file__, "-v"]) 