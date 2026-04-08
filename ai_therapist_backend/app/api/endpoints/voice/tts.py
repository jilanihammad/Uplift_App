"""
SimpleTTSService-compatible WebSocket TTS endpoint.

Contains:
- websocket_tts (/ws/tts) - Basic TTS streaming over WebSocket
"""
import asyncio
import base64
import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.llm_config import LLMConfig
from app.services.llm_manager import llm_manager

logger = logging.getLogger(__name__)

router = APIRouter()


@router.websocket("/ws/tts")
async def websocket_tts(websocket: WebSocket):
    """
    WebSocket TTS endpoint compatible with SimpleTTSService protocol
    """
    await websocket.accept()

    try:
        # Send initial tts-hello message (session_id will be sent by client)
        await websocket.send_text(json.dumps({
            "type": "tts-hello"
        }))

        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
                text = payload.get("text")
                voice = payload.get("voice", "sage")
                params = payload.get("params", {})
                session_id = payload.get("session_id")  # Get session_id from client request
                tts_mode = LLMConfig.get_tts_mode()
                default_format = "native" if tts_mode == "live" else "wav"
                response_format = params.get("response_format", default_format)
                mime_type = LLMConfig.get_tts_config().get("mime_type", "audio/wav")

                if not text:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "detail": "No text provided"
                    }))
                    continue

                try:
                    # Track total audio size for content-length solution
                    total_audio_size = 0

                    # Stream audio using unified manager with enhanced WebSocket control
                    async for b64_chunk in llm_manager.stream_text_to_speech(
                        text,
                        voice=voice,
                        response_format=response_format
                    ):
                        # Decode base64 to get raw binary data
                        audio_bytes = base64.b64decode(b64_chunk)
                        # Track total size
                        total_audio_size += len(audio_bytes)
                        # Send as binary WebSocket frame
                        await websocket.send_bytes(audio_bytes)

                    # When done, send a 'tts-done' message with total size for ExoPlayer completion
                    done_message = {
                        "type": "tts-done",
                        "total_size": total_audio_size,
                        "mime_type": mime_type,
                    }
                    if session_id:
                        done_message["session_id"] = session_id
                    await websocket.send_text(json.dumps(done_message))

                    # Send completion signal for immediate client cleanup (addresses 17s connection issue)
                    await websocket.send_text(json.dumps({
                        "type": "done",
                        "reason": "streaming_complete",
                        "total_bytes": total_audio_size
                    }))

                    # Wait briefly for client to process done message, then close connection
                    await asyncio.sleep(0.1)  # 100ms grace period
                    await websocket.close(code=1000, reason="streaming_complete")
                    return  # Exit the loop and function

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
