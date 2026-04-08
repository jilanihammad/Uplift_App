"""
Gemini Live duplex streaming WebSocket endpoint.

Contains:
- websocket_gemini_live (/ws/gemini/live) - Bidirectional audio/text streaming
"""
import asyncio
import contextlib
import json
import logging
import uuid
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from google.genai import types

from app.core.llm_config import LLMConfig
from app.services.llm_manager import llm_manager

logger = logging.getLogger(__name__)

router = APIRouter()


@router.websocket("/ws/gemini/live")
async def websocket_gemini_live(
    websocket: WebSocket,
    user_id: Optional[str] = Query(default=None, alias="userId"),
):
    """Gemini Live duplex streaming endpoint."""

    await websocket.accept()

    if not LLMConfig.is_gemini_live_duplex_enabled():
        await websocket.send_text(json.dumps({
            "type": "error",
            "detail": "Gemini Live duplex mode is disabled."
        }))
        await websocket.close(code=1000)
        return

    if not llm_manager:
        await websocket.send_text(json.dumps({
            "type": "error",
            "detail": "LLM manager unavailable"
        }))
        await websocket.close(code=1011)
        return

    session = None
    audio_metadata = {
        "type": "ready",
        "mode": "duplex",
        "audio": {
            "mime_type": "audio/wav",
            "sample_rate_hz": 24000,
            "channels": 1,
        },
    }

    async def _client_to_model() -> None:
        try:
            while True:
                message = await websocket.receive()
                if message["type"] == "websocket.disconnect":
                    break
                if message["type"] != "websocket.receive":
                    continue

                if "bytes" in message and message["bytes"] is not None:
                    await session.send_audio_chunk(message["bytes"])
                elif "text" in message and message["text"]:
                    try:
                        payload = json.loads(message["text"])
                    except json.JSONDecodeError:
                        await websocket.send_text(json.dumps({
                            "type": "error",
                            "detail": "Invalid JSON payload",
                        }))
                        continue

                    msg_type = payload.get("type")
                    if msg_type == "audio_stream_end":
                        await session.mark_audio_complete()
                    elif msg_type == "client_content":
                        text_value = payload.get("text")
                        if text_value:
                            content = types.Content(
                                role=payload.get("role", "user"),
                                parts=[types.Part.from_text(text=text_value)],
                            )
                            await session.send_client_content(
                                content,
                                turn_complete=payload.get("turn_complete", False),
                            )
        except WebSocketDisconnect:
            pass
        finally:
            with contextlib.suppress(Exception):
                await session.mark_audio_complete()

    async def _model_to_client() -> None:
        try:
            await websocket.send_text(json.dumps({
                **audio_metadata,
                "session_id": session.session_id,
            }))

            async for event in session.receive_events():
                kind = event.get("kind")
                if kind == "audio":
                    await websocket.send_bytes(event["data"])
                elif kind == "text":
                    await websocket.send_text(json.dumps({
                        "type": "model_text",
                        "text": event.get("text", ""),
                        "isFinal": event.get("is_final", False),
                        "sequence": event.get("sequence"),
                    }))
                elif kind == "turn_complete":
                    await websocket.send_text(json.dumps({
                        "type": "turn_complete",
                        "sequence": event.get("sequence"),
                    }))
        except Exception as exc:
            await websocket.send_text(json.dumps({
                "type": "error",
                "detail": str(exc),
            }))
            raise

    try:
        try:
            session = llm_manager.create_gemini_live_session(
                user_id=user_id,
                metadata={
                    "session_id": f"gemini-live-{uuid.uuid4().hex}",
                    "input_mime": "audio/pcm; rate=24000; channels=1; bit=16",
                },
            )
        except RuntimeError as config_error:
            await websocket.send_text(json.dumps({
                "type": "error",
                "detail": str(config_error),
            }))
            await websocket.close(code=1011)
            return

        await session.start()

        sender_task = asyncio.create_task(_client_to_model(), name=f"gemini-live-send-{session.session_id}")
        receiver_task = asyncio.create_task(_model_to_client(), name=f"gemini-live-recv-{session.session_id}")

        done, pending = await asyncio.wait(
            {sender_task, receiver_task},
            return_when=asyncio.FIRST_EXCEPTION,
        )

        for task in pending:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

        for task in done:
            task_result = task.exception()
            if task_result and not isinstance(task_result, asyncio.CancelledError):
                raise task_result

    except Exception as exc:
        logger.error("Gemini Live websocket error: %s", exc)
        with contextlib.suppress(Exception):
            await websocket.send_text(json.dumps({
                "type": "error",
                "detail": str(exc),
            }))
    finally:
        if session is not None:
            await session.close()
        with contextlib.suppress(Exception):
            await websocket.close(code=1011)
