"""
Comprehensive Backend Smoke Test for TTS

Supports both REST API and WebSocket Live modes for Gemini TTS testing.
Can be run against local dev, staging, or production deployments.

Usage:
    # REST API mode (default)
    python testTTS.py --api-key YOUR_KEY --text "Hello from Gemini"

    # WebSocket Live mode
    python testTTS.py --mode live --url ws://localhost:8000 --text "Testing live mode"

    # Test against staging
    python testTTS.py --mode live --url wss://staging-backend.run.app --text "Staging test"
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
import wave
from pathlib import Path
from typing import Dict, Any, Optional

try:
    import websockets
except ImportError:
    websockets = None

from app.services.llm_manager import LLMManager
from app.core.llm_config import LLMConfig


class TTSTestResults:
    """Container for TTS test results and metadata"""

    def __init__(self):
        self.success: bool = False
        self.ttfb_ms: Optional[float] = None
        self.total_duration_ms: Optional[float] = None
        self.audio_bytes: bytes = b""
        self.mime_type: Optional[str] = None
        self.sample_rate: Optional[int] = None
        self.chunks_received: int = 0
        self.error: Optional[str] = None
        self.mode: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "success": self.success,
            "ttfb_ms": self.ttfb_ms,
            "total_duration_ms": self.total_duration_ms,
            "audio_size_bytes": len(self.audio_bytes),
            "mime_type": self.mime_type,
            "sample_rate": self.sample_rate,
            "chunks_received": self.chunks_received,
            "error": self.error,
            "mode": self.mode
        }


async def test_rest_tts(
    text: str,
    voice: str,
    model: str,
    output: Path
) -> TTSTestResults:
    """
    Test TTS via REST API (direct LLMManager call)

    Args:
        text: Text to synthesize
        voice: Voice to use
        model: Model ID
        output: Output file path

    Returns:
        TTSTestResults with metadata and audio
    """
    results = TTSTestResults()
    results.mode = "rest"

    try:
        os.environ.setdefault("GOOGLE_TTS_MODEL", model)

        manager = LLMManager()

        # Get TTS configuration to capture metadata
        tts_config = LLMConfig.get_tts_config()
        results.mime_type = tts_config.get("mime_type", "audio/wav")
        results.sample_rate = tts_config.get("sample_rate_hz", 24000)

        # Measure TTFB and total duration
        start_time = time.perf_counter()

        audio_bytes, detected_mime, sample_rate = await manager._google_generate_tts_bytes(
            text,
            voice=voice,
            response_format="wav",
        )

        end_time = time.perf_counter()

        # Update results with actual returned metadata
        if detected_mime:
            results.mime_type = detected_mime
        if sample_rate:
            results.sample_rate = sample_rate

        results.audio_bytes = audio_bytes
        results.total_duration_ms = (end_time - start_time) * 1000
        results.chunks_received = 1  # REST returns single response
        results.success = True

        # Save to output file
        output.write_bytes(audio_bytes)

    except Exception as e:
        results.error = str(e)
        results.success = False

    return results


async def test_websocket_tts(
    url: str,
    text: str,
    voice: str,
    output: Path,
    timeout_seconds: int = 30
) -> TTSTestResults:
    """
    Test TTS via WebSocket /ws/tts endpoint

    Args:
        url: WebSocket URL (e.g., ws://localhost:8000 or wss://backend.run.app)
        text: Text to synthesize
        voice: Voice to use
        output: Output file path
        timeout_seconds: Timeout for the test

    Returns:
        TTSTestResults with metadata and audio
    """
    results = TTSTestResults()
    results.mode = "websocket_live"

    if not websockets:
        results.error = "websockets library not installed. Run: pip install websockets"
        results.success = False
        return results

    ws_url = f"{url}/ws/tts" if not url.endswith("/ws/tts") else url

    try:
        async with websockets.connect(ws_url, ping_interval=None) as ws:
            # Wait for tts-hello message
            hello_msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
            hello_data = json.loads(hello_msg)

            if hello_data.get("type") != "tts-hello":
                results.error = f"Unexpected hello message: {hello_data}"
                return results

            # Send TTS request
            start_time = time.perf_counter()
            payload = {
                "text": text,
                "voice": voice,
                "params": {
                    "response_format": "native"  # Request native format for Gemini Live
                }
            }

            await ws.send(json.dumps(payload))

            first_chunk_received = False
            audio_chunks = []

            # Listen for responses with timeout
            try:
                async with asyncio.timeout(timeout_seconds):
                    async for msg in ws:
                        if isinstance(msg, bytes):
                            # Audio chunk received
                            if not first_chunk_received:
                                results.ttfb_ms = (time.perf_counter() - start_time) * 1000
                                first_chunk_received = True

                            audio_chunks.append(msg)
                            results.chunks_received += 1

                        elif isinstance(msg, str):
                            # Control message
                            try:
                                data = json.loads(msg)
                                msg_type = data.get("type")

                                if msg_type == "tts-done":
                                    # Extract metadata from completion message
                                    results.mime_type = data.get("mime_type", "audio/ogg; codecs=opus")
                                    results.sample_rate = data.get("sample_rate", 24000)
                                    results.total_duration_ms = (time.perf_counter() - start_time) * 1000
                                    results.success = True
                                    break

                                elif msg_type == "error":
                                    results.error = data.get("detail", "Unknown error")
                                    results.success = False
                                    break

                            except json.JSONDecodeError:
                                pass  # Ignore non-JSON messages

            except asyncio.TimeoutError:
                results.error = f"Timeout after {timeout_seconds}s"
                results.success = False

            # Combine all audio chunks
            results.audio_bytes = b"".join(audio_chunks)

            # Save to output file
            if results.audio_bytes:
                output.write_bytes(results.audio_bytes)

    except OSError as e:
        if "Connection refused" in str(e):
            results.error = f"Connection refused to {ws_url}"
        else:
            results.error = f"Connection error: {str(e)}"
        results.success = False
    except Exception as e:
        results.error = f"WebSocket error: {str(e)}"
        results.success = False

    return results


def validate_results(results: TTSTestResults, args: argparse.Namespace) -> bool:
    """
    Validate test results and assert expected metadata

    Args:
        results: Test results to validate
        args: Command-line arguments with expected values

    Returns:
        True if validation passes, False otherwise
    """
    validation_passed = True

    # Basic success check
    if not results.success:
        print(f"❌ Test failed: {results.error}")
        return False

    # Validate audio was received
    if not results.audio_bytes:
        print("❌ No audio data received")
        validation_passed = False
    else:
        print(f"✅ Audio received: {len(results.audio_bytes)} bytes")

    # Validate MIME type for live mode
    if args.mode == "live":
        expected_mime = "audio/ogg; codecs=opus"  # Gemini Live default
        if results.mime_type and expected_mime not in results.mime_type:
            print(f"⚠️  MIME type mismatch: expected '{expected_mime}', got '{results.mime_type}'")
        else:
            print(f"✅ MIME type: {results.mime_type}")

    # Validate sample rate
    if results.sample_rate:
        expected_rate = 24000  # Gemini default
        if results.sample_rate != expected_rate:
            print(f"⚠️  Sample rate: {results.sample_rate} Hz (expected {expected_rate} Hz)")
        else:
            print(f"✅ Sample rate: {results.sample_rate} Hz")
    else:
        print("⚠️  Sample rate not reported")

    # Validate TTFB for live mode
    if args.mode == "live" and results.ttfb_ms:
        ttfb_target = 500.0  # Target: sub-500ms TTFB
        if results.ttfb_ms > ttfb_target:
            print(f"⚠️  TTFB: {results.ttfb_ms:.0f} ms (target: <{ttfb_target:.0f} ms)")
        else:
            print(f"✅ TTFB: {results.ttfb_ms:.0f} ms")

    # Validate total duration
    if results.total_duration_ms:
        print(f"⏱️  Total duration: {results.total_duration_ms:.0f} ms")

    # Validate chunk count for streaming
    if args.mode == "live":
        if results.chunks_received < 1:
            print(f"❌ No audio chunks received")
            validation_passed = False
        else:
            print(f"✅ Streaming verified: {results.chunks_received} chunks")

    return validation_passed


def analyze_audio_file(file_path: Path, results: TTSTestResults) -> None:
    """
    Analyze the generated audio file and verify format

    Args:
        file_path: Path to audio file
        results: Test results to update
    """
    if not file_path.exists():
        print("⚠️  Output file not created")
        return

    file_size = file_path.stat().st_size
    print(f"📁 Output file: {file_path} ({file_size} bytes)")

    # Try to analyze WAV file
    if file_path.suffix == ".wav":
        try:
            with wave.open(str(file_path), 'rb') as wav_file:
                channels = wav_file.getnchannels()
                sample_width = wav_file.getsampwidth()
                framerate = wav_file.getframerate()
                n_frames = wav_file.getnframes()
                duration = n_frames / float(framerate)

                print(f"🎵 WAV format: {channels} ch, {sample_width * 8}-bit, {framerate} Hz")
                print(f"🎵 Duration: {duration:.2f} seconds ({n_frames} frames)")

                # Verify sample rate matches metadata
                if results.sample_rate and framerate != results.sample_rate:
                    print(f"⚠️  WAV sample rate ({framerate}) doesn't match metadata ({results.sample_rate})")

        except Exception as e:
            print(f"⚠️  Could not analyze WAV file: {e}")

    elif file_path.suffix == ".ogg":
        # For OGG files, just verify the magic bytes
        with open(file_path, 'rb') as f:
            header = f.read(4)
            if header == b'OggS':
                print("✅ Valid OGG file signature")
            else:
                print("⚠️  Invalid OGG file signature")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Comprehensive Backend TTS Smoke Test",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Test REST API with Gemini
  python testTTS.py --api-key YOUR_KEY --text "Hello from Gemini"

  # Test WebSocket Live mode (local)
  python testTTS.py --mode live --url ws://localhost:8000 --text "Testing live mode"

  # Test against staging deployment
  python testTTS.py --mode live --url wss://staging-backend.run.app --text "Staging test"

  # Test with custom voice and output
  python testTTS.py --mode live --url ws://localhost:8000 --voice kore --output test-live.ogg
        """
    )

    # Mode selection
    parser.add_argument(
        "--mode",
        choices=["rest", "live"],
        default="rest",
        help="Test mode: 'rest' for direct API calls, 'live' for WebSocket streaming"
    )

    # Common arguments
    parser.add_argument(
        "--text",
        default="Hello from Gemini TTS smoke test",
        help="Text to synthesize"
    )
    parser.add_argument(
        "--voice",
        default="kore",
        help="Voice to use (kore, puck, charon, fenrir, aoede)"
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output audio file path (default: test-{mode}.{ext})"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Timeout in seconds for WebSocket tests"
    )

    # REST mode arguments
    parser.add_argument(
        "--api-key",
        help="Google Gemini API key (for REST mode)"
    )
    parser.add_argument(
        "--model",
        default="gemini-2.5-flash-native-audio-preview-09-2025",
        help="Gemini TTS model ID (for REST mode)"
    )

    # WebSocket mode arguments
    parser.add_argument(
        "--url",
        help="WebSocket base URL (for live mode, e.g., ws://localhost:8000 or wss://backend.run.app)"
    )

    # Validation options
    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip metadata validation assertions"
    )
    parser.add_argument(
        "--json-output",
        action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    # Validate required arguments based on mode
    if args.mode == "rest":
        if not args.api_key:
            parser.error("--api-key is required for REST mode")
        os.environ["GOOGLE_API_KEY"] = args.api_key
        os.environ["GOOGLE_TTS_MODE"] = "rest"

    elif args.mode == "live":
        if not args.url:
            parser.error("--url is required for live mode")
        os.environ["GOOGLE_TTS_MODE"] = "live"

    # Determine output file path
    if args.output:
        output_path = Path(args.output)
    else:
        extension = "ogg" if args.mode == "live" else "wav"
        output_path = Path(f"test-{args.mode}.{extension}")

    # Run the test
    if not args.json_output:
        print("=" * 60)
        print(f"🧪 TTS Backend Smoke Test - Mode: {args.mode.upper()}")
        print("=" * 60)
        print(f"Text: '{args.text}'")
        print(f"Voice: {args.voice}")
        print(f"Output: {output_path}")
        print("-" * 60)

    # Execute test based on mode
    if args.mode == "rest":
        results = asyncio.run(test_rest_tts(
            text=args.text,
            voice=args.voice,
            model=args.model,
            output=output_path
        ))
    else:  # live mode
        results = asyncio.run(test_websocket_tts(
            url=args.url,
            text=args.text,
            voice=args.voice,
            output=output_path,
            timeout_seconds=args.timeout
        ))

    # Output results
    if args.json_output:
        print(json.dumps(results.to_dict(), indent=2))
    else:
        print()
        print("=" * 60)
        print("📊 Test Results")
        print("=" * 60)

        # Validate and display results
        validation_passed = True
        if not args.skip_validation:
            validation_passed = validate_results(results, args)

        # Analyze output file
        if results.success and output_path.exists():
            print()
            analyze_audio_file(output_path, results)

        print()
        print("=" * 60)

        if results.success and (args.skip_validation or validation_passed):
            print("✅ Test PASSED")
            print(f"💾 Audio saved to: {output_path.resolve()}")
            sys.exit(0)
        else:
            print("❌ Test FAILED")
            if results.error:
                print(f"Error: {results.error}")
            sys.exit(1)


if __name__ == "__main__":
    main()
