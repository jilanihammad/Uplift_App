"""
Pytest-based Backend Smoke Tests for TTS

Automated tests for both REST API and WebSocket Live modes.
Suitable for CI/CD pipelines and pre-deployment validation.

Usage:
    # Run all TTS smoke tests
    pytest tests/test_tts_smoke.py -v

    # Run only WebSocket live tests
    pytest tests/test_tts_smoke.py -v -k "live"

    # Run against staging
    pytest tests/test_tts_smoke.py -v --base-url=https://staging-backend.run.app

    # Generate JSON report
    pytest tests/test_tts_smoke.py -v --json-report --json-report-file=test-results.json
"""

import asyncio
import json
import os
import tempfile
import wave
from pathlib import Path
from typing import Generator, Dict, Any

import pytest

try:
    import websockets
    WEBSOCKETS_AVAILABLE = True
except ImportError:
    WEBSOCKETS_AVAILABLE = False

from app.services.llm_manager import LLMManager
from app.core.llm_config import LLMConfig


# Test configuration from environment variables
TEST_CONFIG = {
    "google_api_key": os.getenv("GOOGLE_API_KEY"),
    "base_url": os.getenv("TEST_BASE_URL", "http://localhost:8000"),
    "timeout": int(os.getenv("TEST_TIMEOUT", "30")),
    "voice": os.getenv("TEST_VOICE", "kore"),
    "ttfb_threshold_ms": float(os.getenv("TEST_TTFB_THRESHOLD", "500")),
}


@pytest.fixture
def temp_audio_file() -> Generator[Path, None, None]:
    """Create a temporary file for audio output"""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        temp_path = Path(f.name)

    yield temp_path

    # Cleanup
    if temp_path.exists():
        temp_path.unlink()


@pytest.fixture
def llm_manager():
    """Create LLMManager instance for testing"""
    # Ensure Google API key is set
    if TEST_CONFIG["google_api_key"]:
        os.environ["GOOGLE_API_KEY"] = TEST_CONFIG["google_api_key"]

    return LLMManager()


class TestTTSRestAPI:
    """Test suite for REST API TTS functionality"""

    @pytest.mark.skipif(
        not TEST_CONFIG["google_api_key"],
        reason="GOOGLE_API_KEY not set"
    )
    @pytest.mark.asyncio
    async def test_rest_tts_basic(self, llm_manager, temp_audio_file):
        """Test basic REST TTS generation"""
        os.environ["GOOGLE_TTS_MODE"] = "rest"

        text = "Testing REST TTS synthesis"
        voice = TEST_CONFIG["voice"]

        # Generate TTS audio
        audio_bytes, mime_type, sample_rate = await llm_manager._google_generate_tts_bytes(
            text,
            voice=voice,
            response_format="wav"
        )

        # Assertions
        assert audio_bytes, "No audio data received"
        assert len(audio_bytes) > 0, "Audio data is empty"
        assert mime_type, "MIME type not returned"
        assert "audio" in mime_type.lower(), f"Invalid MIME type: {mime_type}"
        assert sample_rate, "Sample rate not returned"
        assert sample_rate > 0, "Invalid sample rate"

        # Save and validate WAV file
        temp_audio_file.write_bytes(audio_bytes)
        assert temp_audio_file.exists(), "Output file not created"
        assert temp_audio_file.stat().st_size > 0, "Output file is empty"

        # Validate WAV format
        with wave.open(str(temp_audio_file), 'rb') as wav_file:
            assert wav_file.getnchannels() > 0, "Invalid channel count"
            assert wav_file.getframerate() == sample_rate, "Sample rate mismatch"

    @pytest.mark.skipif(
        not TEST_CONFIG["google_api_key"],
        reason="GOOGLE_API_KEY not set"
    )
    @pytest.mark.asyncio
    async def test_rest_tts_metadata(self, llm_manager):
        """Test metadata returned by REST TTS"""
        os.environ["GOOGLE_TTS_MODE"] = "rest"

        # Get TTS configuration
        tts_config = LLMConfig.get_tts_config()

        # Assertions
        assert tts_config, "TTS config not returned"
        assert "provider" in tts_config, "Provider not in config"
        assert "model" in tts_config, "Model not in config"
        assert "sample_rate_hz" in tts_config, "Sample rate not in config"
        assert "mime_type" in tts_config, "MIME type not in config"

        # Validate expected values
        assert tts_config["sample_rate_hz"] == 24000, "Unexpected sample rate"
        assert "audio" in tts_config["mime_type"], "Invalid MIME type"


class TestTTSWebSocketLive:
    """Test suite for WebSocket Live TTS functionality"""

    @pytest.mark.skipif(
        not WEBSOCKETS_AVAILABLE,
        reason="websockets library not installed"
    )
    @pytest.mark.asyncio
    async def test_websocket_connection(self):
        """Test WebSocket /ws/tts connection"""
        ws_url = f"{TEST_CONFIG['base_url'].replace('http', 'ws')}/ws/tts"

        try:
            async with websockets.connect(ws_url, ping_interval=None) as ws:
                # Wait for tts-hello message
                hello_msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
                hello_data = json.loads(hello_msg)

                # Assertions
                assert hello_data.get("type") == "tts-hello", "Invalid hello message"

        except websockets.exceptions.ConnectionRefused:
            pytest.fail(f"Connection refused to {ws_url}. Is the server running?")
        except asyncio.TimeoutError:
            pytest.fail("Timeout waiting for hello message")

    @pytest.mark.skipif(
        not WEBSOCKETS_AVAILABLE,
        reason="websockets library not installed"
    )
    @pytest.mark.asyncio
    async def test_websocket_tts_streaming(self, temp_audio_file):
        """Test WebSocket TTS streaming with metadata validation"""
        ws_url = f"{TEST_CONFIG['base_url'].replace('http', 'ws')}/ws/tts"

        text = "Testing WebSocket live streaming"
        voice = TEST_CONFIG["voice"]

        try:
            async with websockets.connect(ws_url, ping_interval=None) as ws:
                # Wait for hello
                hello_msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
                assert json.loads(hello_msg).get("type") == "tts-hello"

                # Send TTS request
                payload = {
                    "text": text,
                    "voice": voice,
                    "params": {
                        "response_format": "native"
                    }
                }

                import time
                start_time = time.perf_counter()
                await ws.send(json.dumps(payload))

                first_chunk_received = False
                ttfb_ms = None
                audio_chunks = []
                mime_type = None
                sample_rate = None
                chunks_received = 0

                # Collect streaming audio
                async for msg in asyncio.wait_for(ws, timeout=TEST_CONFIG["timeout"]):
                    if isinstance(msg, bytes):
                        # Audio chunk
                        if not first_chunk_received:
                            ttfb_ms = (time.perf_counter() - start_time) * 1000
                            first_chunk_received = True

                        audio_chunks.append(msg)
                        chunks_received += 1

                    elif isinstance(msg, str):
                        # Control message
                        try:
                            data = json.loads(msg)
                            msg_type = data.get("type")

                            if msg_type == "tts-done":
                                # Extract metadata
                                mime_type = data.get("mime_type")
                                sample_rate = data.get("sample_rate")
                                break

                            elif msg_type == "error":
                                pytest.fail(f"TTS error: {data.get('detail')}")

                        except json.JSONDecodeError:
                            pass

                # Assertions
                assert first_chunk_received, "No audio chunks received"
                assert chunks_received > 0, "No streaming chunks"
                assert audio_chunks, "No audio data collected"

                audio_bytes = b"".join(audio_chunks)
                assert len(audio_bytes) > 0, "Empty audio data"

                # Validate TTFB
                assert ttfb_ms is not None, "TTFB not measured"
                assert ttfb_ms < TEST_CONFIG["ttfb_threshold_ms"], \
                    f"TTFB {ttfb_ms:.0f}ms exceeds threshold {TEST_CONFIG['ttfb_threshold_ms']}ms"

                # Validate metadata
                assert mime_type, "MIME type not returned"
                assert "audio" in mime_type.lower(), f"Invalid MIME type: {mime_type}"

                # For Gemini Live, expect OGG Opus
                if "live" in TEST_CONFIG["base_url"] or os.getenv("GOOGLE_TTS_MODE") == "live":
                    assert "ogg" in mime_type.lower() or "opus" in mime_type.lower(), \
                        f"Expected OGG/Opus for live mode, got: {mime_type}"

                assert sample_rate, "Sample rate not returned"
                assert sample_rate == 24000, f"Unexpected sample rate: {sample_rate}"

                # Save audio for inspection
                temp_audio_file.write_bytes(audio_bytes)
                assert temp_audio_file.exists(), "Output file not created"

        except websockets.exceptions.ConnectionRefused:
            pytest.skip(f"Server not available at {ws_url}")
        except asyncio.TimeoutError:
            pytest.fail(f"Timeout after {TEST_CONFIG['timeout']}s")

    @pytest.mark.skipif(
        not WEBSOCKETS_AVAILABLE,
        reason="websockets library not installed"
    )
    @pytest.mark.asyncio
    async def test_websocket_tts_performance(self):
        """Test WebSocket TTS performance metrics"""
        ws_url = f"{TEST_CONFIG['base_url'].replace('http', 'ws')}/ws/tts"

        text = "Performance test"
        voice = TEST_CONFIG["voice"]

        try:
            async with websockets.connect(ws_url, ping_interval=None) as ws:
                # Skip hello
                await asyncio.wait_for(ws.recv(), timeout=5.0)

                # Send request
                payload = {
                    "text": text,
                    "voice": voice,
                    "params": {"response_format": "native"}
                }

                import time
                start_time = time.perf_counter()
                await ws.send(json.dumps(payload))

                # Measure TTFB
                first_chunk_time = None
                async for msg in asyncio.wait_for(ws, timeout=TEST_CONFIG["timeout"]):
                    if isinstance(msg, bytes):
                        first_chunk_time = time.perf_counter()
                        break

                assert first_chunk_time is not None, "No audio chunk received"
                ttfb_ms = (first_chunk_time - start_time) * 1000

                # Performance assertion
                assert ttfb_ms < TEST_CONFIG["ttfb_threshold_ms"], \
                    f"TTFB {ttfb_ms:.0f}ms exceeds threshold {TEST_CONFIG['ttfb_threshold_ms']}ms"

        except websockets.exceptions.ConnectionRefused:
            pytest.skip(f"Server not available at {ws_url}")


class TestTTSConfiguration:
    """Test suite for TTS configuration validation"""

    def test_tts_config_structure(self):
        """Test TTS configuration has required fields"""
        config = LLMConfig.get_tts_config()

        required_fields = [
            "provider",
            "model",
            "voice",
            "sample_rate_hz",
            "audio_encoding",
            "response_format",
            "mime_type",
            "supports_streaming"
        ]

        for field in required_fields:
            assert field in config, f"Missing required field: {field}"

    def test_tts_mode_detection(self):
        """Test TTS mode detection (rest vs live)"""
        mode = LLMConfig.get_tts_mode()

        assert mode in ["rest", "live"], f"Invalid TTS mode: {mode}"

    def test_provider_availability(self):
        """Test that configured TTS provider is available"""
        from app.core.llm_config import ModelType

        available = LLMConfig.is_model_available(ModelType.TTS)

        if not TEST_CONFIG["google_api_key"]:
            pytest.skip("GOOGLE_API_KEY not set")

        assert available, "TTS provider not available"


# Pytest configuration hooks
def pytest_configure(config):
    """Configure pytest with custom markers"""
    config.addinivalue_line(
        "markers", "smoke: mark test as a smoke test"
    )
    config.addinivalue_line(
        "markers", "live: mark test as requiring live WebSocket connection"
    )


def pytest_addoption(parser):
    """Add custom command-line options"""
    parser.addoption(
        "--base-url",
        action="store",
        default="http://localhost:8000",
        help="Base URL for backend server"
    )
    parser.addoption(
        "--google-api-key",
        action="store",
        help="Google API key for TTS tests"
    )


@pytest.fixture(scope="session", autouse=True)
def configure_test_env(request):
    """Configure test environment from command-line options"""
    # Update TEST_CONFIG with command-line options
    base_url = request.config.getoption("--base-url")
    google_api_key = request.config.getoption("--google-api-key")

    if base_url:
        TEST_CONFIG["base_url"] = base_url

    if google_api_key:
        TEST_CONFIG["google_api_key"] = google_api_key
        os.environ["GOOGLE_API_KEY"] = google_api_key
