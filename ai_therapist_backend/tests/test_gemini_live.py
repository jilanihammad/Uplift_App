import asyncio
import json
from types import SimpleNamespace
from typing import List, Tuple

import pytest

from app.api.endpoints.voice import websocket_gemini_live
from app.services.llm_manager import GeminiLiveSession, llm_manager
from app.core import llm_config


class _FakeLiveConnection:
    def __init__(self):
        self.sent_audio = []
        self.audio_stream_ended = False
        self.sent_text = []

    async def send_realtime_input(self, *, audio=None, audio_stream_end=False):  # pragma: no cover - trivial
        if audio_stream_end:
            self.audio_stream_ended = True
        elif audio is not None:
            self.sent_audio.append(audio)

    async def send_client_content(self, **kwargs):  # pragma: no cover - trivial
        self.sent_text.append(kwargs)

    def receive(self):
        async def _generator():
            yield SimpleNamespace(
                server_content=SimpleNamespace(
                    model_turn=SimpleNamespace(
                        parts=[
                            SimpleNamespace(
                                inline_data=SimpleNamespace(
                                    data=b"\x00\x01",
                                    mime_type="audio/pcm; rate=16000; channels=1",
                                ),
                                text=None,
                            ),
                            SimpleNamespace(
                                inline_data=None,
                                text="Hello from Gemini",
                            ),
                        ],
                        turn_complete=True,
                    )
                )
            )
        return _generator()


class _FakeLiveContext:
    def __init__(self):
        self.connection = _FakeLiveConnection()

    async def __aenter__(self):  # pragma: no cover - trivial
        return self.connection

    async def __aexit__(self, exc_type, exc, tb):  # pragma: no cover - trivial
        return False


class _FakeGenaiClient:
    def __init__(self, *_, **__):
        self.aio = SimpleNamespace(live=SimpleNamespace(connect=lambda **_: _FakeLiveContext()))


@pytest.mark.asyncio
async def test_gemini_live_session_streams_audio_and_text(monkeypatch):
    monkeypatch.setattr("app.services.llm_manager.genai.Client", _FakeGenaiClient)

    session = GeminiLiveSession(api_key="test", model_id="gemini-test")
    await session.start()

    agen = session.receive_events()
    header_event = await asyncio.wait_for(agen.__anext__(), timeout=0.1)
    audio_event = await asyncio.wait_for(agen.__anext__(), timeout=0.1)
    text_event = await asyncio.wait_for(agen.__anext__(), timeout=0.1)
    turn_event = await asyncio.wait_for(agen.__anext__(), timeout=0.1)

    assert header_event["kind"] == "audio" and header_event["is_header"] is True
    assert audio_event["kind"] == "audio" and audio_event["is_header"] is False
    assert text_event["kind"] == "text" and text_event["is_final"] is True
    assert turn_event["kind"] == "turn_complete"

    await session.send_audio_chunk(b"1234")
    await session.mark_audio_complete()

    fake_connection = session._session  # type: ignore[attr-defined]
    assert fake_connection.audio_stream_ended is True
    assert len(fake_connection.sent_audio) == 1
    blob = fake_connection.sent_audio[0]
    assert getattr(blob, "data", None) == b"1234"

    await session.close()
    with pytest.raises(StopAsyncIteration):
        await asyncio.wait_for(agen.__anext__(), timeout=0.1)


class StubGeminiSession:
    def __init__(self):
        self.session_id = "stub-session"
        self.started = False
        self.closed = False
        self.audio_chunks: List[bytes] = []
        self.audio_complete = False
        self.client_contents: List[Tuple[SimpleNamespace, bool]] = []

    async def start(self):  # pragma: no cover - trivial
        self.started = True

    async def close(self):  # pragma: no cover - trivial
        self.closed = True

    async def send_audio_chunk(self, data, mime_type=None):  # pragma: no cover - trivial
        self.audio_chunks.append(data)

    async def mark_audio_complete(self):  # pragma: no cover - trivial
        self.audio_complete = True

    async def send_client_content(self, content, turn_complete=False):  # pragma: no cover - trivial
        self.client_contents.append((content, turn_complete))

    async def receive_events(self):
        yield {"kind": "text", "text": "Final", "is_final": True, "sequence": 1}
        yield {"kind": "turn_complete", "sequence": 2}


class FakeWebSocket:
    def __init__(self, messages):
        self._messages = iter(messages)
        self.sent_messages: List[Tuple[str, str]] = []
        self.accepted = False
        self.closed = []

    async def accept(self):  # pragma: no cover - trivial
        self.accepted = True

    async def receive(self):
        try:
            return next(self._messages)
        except StopIteration:
            return {"type": "websocket.disconnect"}

    async def send_text(self, data):
        self.sent_messages.append(("text", data))

    async def send_bytes(self, data):
        self.sent_messages.append(("bytes", data))

    async def close(self, code=1000, reason=None):  # pragma: no cover - trivial
        self.closed.append((code, reason))


@pytest.mark.asyncio
async def test_websocket_gemini_live_happy_path(monkeypatch):
    stub_session = StubGeminiSession()

    monkeypatch.setattr(llm_config.LLMConfig, "is_gemini_live_duplex_enabled", staticmethod(lambda: True))
    monkeypatch.setattr(llm_manager, "create_gemini_live_session", lambda **_: stub_session)

    fake_ws = FakeWebSocket(
        [
            {"type": "websocket.receive", "bytes": b"\x01\x02"},
            {
                "type": "websocket.receive",
                "text": json.dumps({"type": "client_content", "text": "hi", "turn_complete": True}),
            },
            {"type": "websocket.receive", "text": json.dumps({"type": "audio_stream_end"})},
        ]
    )

    await websocket_gemini_live(fake_ws, user_id="test-user")

    assert fake_ws.accepted is True
    ready_payload = json.loads(fake_ws.sent_messages[0][1])
    assert ready_payload["type"] == "ready"
    assert any("model_text" in msg[1] for msg in fake_ws.sent_messages if msg[0] == "text")
    assert any("turn_complete" in msg[1] for msg in fake_ws.sent_messages if msg[0] == "text")

    assert stub_session.started is True
    assert stub_session.audio_chunks == [b"\x01\x02"]
    assert stub_session.audio_complete is True
    assert stub_session.closed is True


@pytest.mark.asyncio
async def test_websocket_gemini_live_disabled(monkeypatch):
    monkeypatch.setattr(llm_config.LLMConfig, "is_gemini_live_duplex_enabled", staticmethod(lambda: False))

    fake_ws = FakeWebSocket([])
    await websocket_gemini_live(fake_ws, user_id=None)

    assert fake_ws.accepted is True
    error_payload = json.loads(fake_ws.sent_messages[0][1])
    assert error_payload["type"] == "error"
    assert "disabled" in error_payload["detail"].lower()
    assert fake_ws.closed[0][0] == 1000
