"""
Google (Gemini) provider.

Handles chat completion, streaming, and TTS (REST + Live) via the
``google-genai`` SDK.  Also houses the ``GeminiLiveSession`` class for
duplex audio sessions.
"""

import asyncio
import base64
import contextlib
import io
import logging
import struct
import traceback
import uuid
import wave
from typing import (
    Any,
    AsyncGenerator,
    Callable,
    Dict,
    List,
    Optional,
    Tuple,
    Union,
)

from google import genai
from google.genai import types

from app.core.llm_config import LLMConfig, ModelConfig, ModelProvider, ModelType
from app.services.llm.base_provider import BaseProvider

# Phase 2 circuit-breaker decorators
try:
    from app.core.phase2_integration import google_chat, google_streaming
except ImportError:
    def _noop(fn):
        return fn
    google_chat = google_streaming = _noop

logger = logging.getLogger(__name__)


# =====================================================================
# GeminiLiveSession — duplex audio session manager
# =====================================================================

class GeminiLiveSession:
    """Manage lifecycle and streaming for Gemini Live duplex sessions."""

    _DEFAULT_INPUT_MIME = "audio/pcm; rate=24000; channels=1; bit=16"

    def __init__(
        self,
        *,
        api_key: str,
        model_id: str,
        live_config: Optional[types.LiveConnectConfig] = None,
        user_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        self._api_key = api_key
        self._model_id = model_id
        self._live_config = live_config
        self._user_id = user_id
        self._metadata = metadata or {}
        self.session_id: str = self._metadata.get("session_id", f"gemini-live-{uuid.uuid4().hex}")
        self._client = genai.Client(api_key=self._api_key)
        self._session_cm: Optional[Any] = None
        self._session: Optional[Any] = None
        self._receiver_task: Optional[asyncio.Task] = None
        self._incoming_queue: "asyncio.Queue[Optional[Union[Dict[str, Any], Exception]]]" = asyncio.Queue()
        self._closed = False
        self._lock = asyncio.Lock()
        self._logger = logger.getChild("GeminiLiveSession")
        self._input_mime = self._metadata.get("input_mime", self._DEFAULT_INPUT_MIME)
        self._incremental_transcripts = bool(self._metadata.get("incremental_transcripts", False))
        self._sequence = 0
        self._pcm_header_sent = False
        self._pcm_sample_rate = 24000
        self._pcm_channels = 1
        self._pcm_sample_width = 2

    async def start(self) -> None:
        async with self._lock:
            if self._session is not None:
                return
            self._logger.info(
                "[GeminiLiveSession] opening live session (session_id=%s, user_id=%s)",
                self.session_id, self._user_id,
            )
            self._session_cm = self._client.aio.live.connect(
                model=self._model_id, config=self._live_config,
            )
            self._session = await self._session_cm.__aenter__()
            self._receiver_task = asyncio.create_task(
                self._receiver_loop(), name=f"gemini-live-recv-{self.session_id}",
            )
            self._closed = False

    async def close(self) -> None:
        async with self._lock:
            if self._closed:
                return
            self._logger.info("[GeminiLiveSession] closing session %s", self.session_id)
            if self._receiver_task is not None:
                self._receiver_task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await self._receiver_task
                self._receiver_task = None
            if self._session_cm is not None:
                await self._session_cm.__aexit__(None, None, None)
                self._session_cm = None
            self._session = None
            self._closed = True
            await self._incoming_queue.put(None)

    async def send_audio_chunk(self, pcm_bytes: bytes, *, mime_type: Optional[str] = None) -> None:
        if not self._session:
            raise RuntimeError("Gemini Live session has not been started")
        blob = types.Blob(mime_type=mime_type or self._input_mime, data=pcm_bytes)
        await self._session.send_realtime_input(audio=blob)

    async def mark_audio_complete(self) -> None:
        if not self._session:
            return
        await self._session.send_realtime_input(audio_stream_end=True)

    async def send_client_content(self, content: types.Content, *, turn_complete: bool = False) -> None:
        if not self._session:
            raise RuntimeError("Gemini Live session has not been started")
        await self._session.send_client_content(turns=content, turn_complete=turn_complete)

    async def receive_events(self) -> AsyncGenerator[Dict[str, Any], None]:
        while True:
            item = await self._incoming_queue.get()
            if item is None:
                break
            if isinstance(item, Exception):
                raise item
            yield item

    async def _receiver_loop(self) -> None:
        assert self._session is not None
        try:
            async for message in self._session.receive():
                for event in self._parse_server_message(message):
                    await self._incoming_queue.put(event)
        except Exception as exc:
            await self._incoming_queue.put(exc)
        finally:
            await self._incoming_queue.put(None)

    def _parse_server_message(self, message: types.LiveServerMessage) -> List[Dict[str, Any]]:
        events: List[Dict[str, Any]] = []
        server_content = getattr(message, "server_content", None)
        if not server_content:
            return events
        model_turn = getattr(server_content, "model_turn", None)
        if not model_turn:
            return events
        parts = getattr(model_turn, "parts", None) or []
        turn_complete = bool(getattr(model_turn, "turn_complete", False))
        for part in parts:
            inline_data = getattr(part, "inline_data", None)
            if inline_data and getattr(inline_data, "data", None):
                audio_chunks = self._normalize_audio_chunk(bytes(inline_data.data), inline_data.mime_type or "")
                for chunk_bytes, is_header in audio_chunks:
                    self._sequence += 1
                    events.append({
                        "kind": "audio",
                        "data": chunk_bytes,
                        "mime_type": "audio/wav" if is_header or self._pcm_header_sent else inline_data.mime_type,
                        "is_header": is_header,
                        "sequence": self._sequence,
                    })
            text_value = getattr(part, "text", None)
            if text_value:
                if not self._incremental_transcripts and not turn_complete:
                    continue
                self._sequence += 1
                events.append({"kind": "text", "text": text_value, "is_final": turn_complete, "sequence": self._sequence})
        if turn_complete:
            self._sequence += 1
            events.append({"kind": "turn_complete", "sequence": self._sequence})
        return events

    def _normalize_audio_chunk(self, data: bytes, mime_type: str) -> List[Tuple[bytes, bool]]:
        lower_mime = (mime_type or "").lower()
        is_pcm = "pcm" in lower_mime or "l16" in lower_mime
        if not is_pcm:
            return [(data, False)]
        sample_rate, channels, sample_width = self._parse_pcm_mime(lower_mime)
        chunks: List[Tuple[bytes, bool]] = []
        if not self._pcm_header_sent or sample_rate != self._pcm_sample_rate or channels != self._pcm_channels:
            header = self._build_wav_header(sample_rate, channels=channels, sample_width=sample_width)
            chunks.append((header, True))
            self._pcm_header_sent = True
            self._pcm_sample_rate = sample_rate
            self._pcm_channels = channels
            self._pcm_sample_width = sample_width
        chunks.append((data, False))
        return chunks

    def _parse_pcm_mime(self, mime: str) -> Tuple[int, int, int]:
        sample_rate = self._pcm_sample_rate
        channels = self._pcm_channels
        sample_width = self._pcm_sample_width
        for part in mime.split(";"):
            part = part.strip()
            if not part or "=" not in part:
                continue
            key, value = part.split("=", 1)
            key = key.strip()
            value = value.strip()
            if key in {"rate", "samplerate"} and value.isdigit():
                sample_rate = int(value)
            elif key == "channels" and value.isdigit():
                channels = max(1, int(value))
            elif key in {"bit", "bits", "bitdepth"} and value.isdigit():
                sample_width = max(1, int(value) // 8)
        return sample_rate, channels, sample_width

    @staticmethod
    def _build_wav_header(sample_rate: int, *, channels: int = 1, sample_width: int = 2) -> bytes:
        byte_rate = sample_rate * channels * sample_width
        block_align = channels * sample_width
        return struct.pack(
            '<4sI4s4sIHHIIHH4sI',
            b'RIFF', 0xFFFFFFFF, b'WAVE', b'fmt ', 16, 1,
            channels, sample_rate, byte_rate, block_align,
            sample_width * 8, b'data', 0xFFFFFFFF,
        )


# =====================================================================
# GoogleProvider — chat, streaming, and TTS
# =====================================================================

class GoogleProvider(BaseProvider):
    """Provider for Google Gemini models."""

    # ------------------------------------------------------------------
    # Chat completion
    # ------------------------------------------------------------------

    async def generate(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> str:
        try:
            api_key = LLMConfig.get_api_key(config)
            if not api_key:
                raise ValueError("Google API key not found")
            client = genai.Client(api_key=api_key)

            system_instruction_text = system_prompt
            if not system_instruction_text and user_info:
                from app.services.llm.manager import _build_system_prompt
                system_instruction_text = _build_system_prompt(user_info)

            contents = self._build_gemini_contents(message, context)
            request_config = self._build_gemini_config(system_instruction_text, config, kwargs)

            logger.debug(
                "Sending to Google Gemini: model=%s, system_instruction_present=%s, contents_length=%d",
                config.model_id, bool(system_instruction_text), len(contents),
            )

            response = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: client.models.generate_content(
                        model=config.model_id, contents=contents, config=request_config,
                    ),
                ),
                timeout=10.0,
            )

            return self._extract_text(response, config.model_id)

        except Exception as e:
            logger.error("Error generating Google response using new SDK: %s", e)
            logger.error(traceback.format_exc())
            raise

    # ------------------------------------------------------------------
    # Streaming
    # ------------------------------------------------------------------

    @google_streaming
    async def stream(
        self,
        message: str,
        context: Optional[List[Dict[str, str]]],
        system_prompt: str,
        user_info: Optional[Dict[str, Any]],
        config: ModelConfig,
        **kwargs,
    ) -> AsyncGenerator[str, None]:
        try:
            api_key = LLMConfig.get_api_key(config)
            if not api_key:
                raise ValueError("Google API key not found")
            client = genai.Client(api_key=api_key)

            system_instruction_text = system_prompt
            if not system_instruction_text and user_info:
                from app.services.llm.manager import _build_system_prompt
                system_instruction_text = _build_system_prompt(user_info)

            contents = self._build_gemini_contents(message, context)
            request_config = self._build_gemini_config(system_instruction_text, config, kwargs)

            logger.debug(
                "Streaming from Google Gemini: model=%s, system_instruction_present=%s, contents_length=%d",
                config.model_id, bool(system_instruction_text), len(contents),
            )

            stream = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: client.models.generate_content_stream(
                        model=config.model_id, contents=contents, config=request_config,
                    ),
                ),
                timeout=10.0,
            )

            for chunk in stream:
                if hasattr(chunk, "text") and chunk.text:
                    yield chunk.text
                elif hasattr(chunk, "candidates") and chunk.candidates:
                    candidate = chunk.candidates[0]
                    if hasattr(candidate, "content") and candidate.content:
                        if hasattr(candidate.content, "parts") and candidate.content.parts:
                            for part in candidate.content.parts:
                                if hasattr(part, "text") and part.text:
                                    yield part.text
                        elif hasattr(candidate.content, "text") and candidate.content.text:
                            yield candidate.content.text
                await asyncio.sleep(0)

        except Exception as e:
            logger.error("Error streaming Google response using new SDK: %s", e)
            logger.error(traceback.format_exc())
            raise

    # ------------------------------------------------------------------
    # TTS (file save)
    # ------------------------------------------------------------------

    async def tts(self, text: str, output_file: str, tts_config: ModelConfig, **kwargs) -> Any:
        voice = kwargs.pop("voice", None)
        response_format = kwargs.pop("response_format", "wav")

        if response_format not in (None, "wav"):
            raise ValueError("Google TTS currently supports only WAV output")

        audio_bytes, _, _ = await self._generate_tts_bytes(
            text, tts_config, voice=voice, response_format="wav", **kwargs,
        )
        with open(output_file, "wb") as f:
            f.write(audio_bytes)
        return base64.b64encode(audio_bytes).decode("utf-8")

    # ------------------------------------------------------------------
    # Streaming TTS
    # ------------------------------------------------------------------

    async def stream_tts(self, text: str, tts_config: ModelConfig, **kwargs) -> AsyncGenerator[str, None]:
        voice = kwargs.pop("voice", None)
        response_format = kwargs.pop("response_format", None)

        google_mode = (tts_config.default_params or {}).get("mode", "rest")
        default_params = tts_config.default_params.copy() if tts_config else {}
        sample_rate = int(kwargs.get("sample_rate_hz") or default_params.get("sample_rate_hz", 24000))
        channels = int(default_params.get("channels", 1))

        if google_mode == "live":
            async for chunk_b64 in self._stream_live_tts_b64(text, tts_config, voice=voice, response_format=response_format, **kwargs):
                yield chunk_b64
        else:
            if response_format not in (None, "wav"):
                raise ValueError("Google TTS currently supports only WAV streaming")
            async for chunk_b64 in self._stream_rest_tts_b64(text, tts_config, voice=voice, sample_rate=sample_rate, channels=channels, **kwargs):
                yield chunk_b64

    # ------------------------------------------------------------------
    # Internal TTS helpers
    # ------------------------------------------------------------------

    async def _stream_rest_tts_b64(self, text, tts_config, *, voice, sample_rate, channels, **kwargs):
        chunk_size = int(kwargs.get("chunk_size", 16384))
        header = _build_streaming_wav_header(sample_rate, channels=channels, sample_width=2)
        buffer = bytearray(header)
        total_audio_bytes = 0
        first_chunk_logged = False

        logger.info("Google TTS: streaming WAV output (chunk_size=%d)", chunk_size)

        async for raw_chunk in self._stream_tts_chunks(text, tts_config, voice=voice, response_format="wav", sample_rate_hz=sample_rate):
            if not raw_chunk:
                continue
            total_audio_bytes += len(raw_chunk)
            buffer.extend(raw_chunk)
            while chunk_size and len(buffer) >= chunk_size:
                chunk = bytes(buffer[:chunk_size])
                del buffer[:chunk_size]
                if not first_chunk_logged:
                    logger.debug("Google TTS first chunk size=%d bytes", len(chunk))
                    first_chunk_logged = True
                yield base64.b64encode(chunk).decode("utf-8")
            if not chunk_size:
                chunk = bytes(buffer)
                buffer.clear()
                if chunk:
                    if not first_chunk_logged:
                        logger.debug("Google TTS first chunk size=%d bytes", len(chunk))
                        first_chunk_logged = True
                    yield base64.b64encode(chunk).decode("utf-8")
        if buffer:
            chunk = bytes(buffer)
            if not first_chunk_logged:
                logger.debug("Google TTS first chunk size=%d bytes", len(chunk))
            yield base64.b64encode(chunk).decode("utf-8")
        logger.info("Google TTS: WAV completed - streamed %d audio bytes (header %d bytes)", total_audio_bytes, len(header))

    async def _stream_live_tts_b64(self, text, tts_config, *, voice, response_format, **kwargs):
        mime_holder: Dict[str, Optional[str]] = {"value": None}

        def _on_mime_detected(mime: str) -> None:
            if mime_holder["value"] is None:
                mime_holder["value"] = mime

        chunk_size = int(kwargs.get("chunk_size", 0))
        buffer = bytearray()
        total_bytes = 0
        first_chunk_logged = False

        logger.info("Google Live TTS: streaming native audio (chunk_size=%d)", chunk_size)

        async for raw_chunk in self._live_stream_tts_chunks(text, tts_config, voice=voice, response_format=response_format or "native", on_mime_detected=_on_mime_detected):
            if not raw_chunk:
                continue
            total_bytes += len(raw_chunk)
            if chunk_size > 0:
                buffer.extend(raw_chunk)
                while len(buffer) >= chunk_size:
                    chunk = bytes(buffer[:chunk_size])
                    del buffer[:chunk_size]
                    if not first_chunk_logged:
                        logger.debug("Google Live TTS first chunk size=%d bytes", len(chunk))
                        first_chunk_logged = True
                    yield base64.b64encode(chunk).decode("utf-8")
            else:
                if not first_chunk_logged:
                    logger.debug("Google Live TTS first chunk size=%d bytes", len(raw_chunk))
                    first_chunk_logged = True
                yield base64.b64encode(raw_chunk).decode("utf-8")
        if chunk_size > 0 and buffer:
            chunk = bytes(buffer)
            if not first_chunk_logged:
                logger.debug("Google Live TTS first chunk size=%d bytes", len(chunk))
            yield base64.b64encode(chunk).decode("utf-8")
        logger.info("Google Live TTS: native stream complete (%d bytes, mime=%s)", total_bytes, mime_holder.get("value"))

    async def _stream_tts_chunks(self, text, tts_config, *, voice, response_format, **kwargs) -> AsyncGenerator[bytes, None]:
        """Stream raw audio chunks from Google Gemini TTS (REST mode)."""
        api_key = LLMConfig.get_api_key(tts_config)
        if not api_key:
            raise ValueError("GOOGLE_API_KEY is not configured")
        if response_format != "wav":
            raise ValueError("Google TTS helper only supports WAV output")

        default_params = tts_config.default_params.copy()
        sample_rate = int(kwargs.get("sample_rate_hz") or default_params.get("sample_rate_hz", 24000))
        voice_name = voice or default_params.get("voice") or LLMConfig.DEFAULT_TTS_VOICE

        speaking_rate = kwargs.pop("speaking_rate", None)
        pitch = kwargs.pop("pitch", None)
        if speaking_rate is not None or pitch is not None:
            logger.debug("Google TTS ignoring speaking_rate (%s) / pitch (%s) overrides", speaking_rate, pitch)
        if kwargs:
            logger.debug("Google TTS ignored additional parameters: %s", ", ".join(sorted(map(str, kwargs.keys()))))

        voice_config_cls = getattr(types, "VoiceConfig", None)
        prebuilt_voice_config_cls = getattr(types, "PrebuiltVoiceConfig", None)
        if voice_config_cls and prebuilt_voice_config_cls:
            speech_config = types.SpeechConfig(
                voice_config=voice_config_cls(prebuilt_voice_config=prebuilt_voice_config_cls(voice_name=voice_name))
            )
        else:
            speech_config = {"voice_config": {"prebuilt_voice_config": {"voice_name": voice_name}}}

        modality_audio = getattr(types.Modality, "AUDIO", "AUDIO")
        generation_config = types.GenerateContentConfig(
            response_modalities=[modality_audio], speech_config=speech_config,
        )
        contents = [types.Content(role="user", parts=[types.Part.from_text(text=text)])]

        loop = asyncio.get_running_loop()
        queue: "asyncio.Queue[Optional[Union[bytes, Exception]]]" = asyncio.Queue()

        def _produce_chunks() -> None:
            try:
                client = genai.Client(api_key=api_key)
                responses = client.models.generate_content_stream(
                    model=tts_config.model_id, contents=contents, config=generation_config,
                )
                for resp in responses:
                    if not resp or not resp.candidates:
                        continue
                    for candidate in resp.candidates:
                        if not candidate.content or not candidate.content.parts:
                            continue
                        for part in candidate.content.parts:
                            inline_data = getattr(part, "inline_data", None)
                            if inline_data and getattr(inline_data, "data", None):
                                loop.call_soon_threadsafe(queue.put_nowait, bytes(inline_data.data))
            except Exception as exc:
                logger.error("Google TTS streaming failed: %s", exc)
                logger.error(traceback.format_exc())
                loop.call_soon_threadsafe(queue.put_nowait, exc)
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, None)

        producer_future = loop.run_in_executor(None, _produce_chunks)
        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    await asyncio.wrap_future(producer_future)
                    raise item
                yield item
        finally:
            await asyncio.wrap_future(producer_future)

    async def _live_stream_tts_chunks(
        self, text, tts_config, *, voice, response_format,
        on_mime_detected: Optional[Callable[[str], None]] = None,
    ) -> AsyncGenerator[bytes, None]:
        """Stream raw audio chunks from Google Gemini Live API."""
        api_key = LLMConfig.get_api_key(tts_config)
        if not api_key:
            raise ValueError("GOOGLE_API_KEY is not configured")

        default_params = tts_config.default_params.copy()
        sample_rate = int(default_params.get("sample_rate_hz", 24000))
        channels = int(default_params.get("channels", 1))
        sample_width = int(default_params.get("sample_width", 2))
        voice_name = voice or default_params.get("voice") or LLMConfig.DEFAULT_TTS_VOICE

        voice_config = types.VoiceConfig(prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice_name))
        speech_config = types.SpeechConfig(voice_config=voice_config)
        generation_config = types.GenerationConfig(
            response_modalities=[types.Modality.AUDIO], speech_config=speech_config,
        )
        live_config = types.LiveConnectConfig(generation_config=generation_config)

        client = genai.Client(api_key=api_key)

        if logger.isEnabledFor(logging.DEBUG):
            try:
                logger.debug("Google Live TTS: model=%s live_config=%s", tts_config.model_id, live_config.model_dump_json())
            except Exception:
                pass

        queue: "asyncio.Queue[Optional[Union[bytes, Exception]]]" = asyncio.Queue()
        mime_notified = False
        pcm_header_sent = False

        def _parse_pcm_formats(mime: str) -> Tuple[int, int, int]:
            parsed_rate, parsed_channels, parsed_width = sample_rate, channels, sample_width
            if not mime:
                return parsed_rate, parsed_channels, parsed_width
            try:
                lower_mime = mime.lower()
                parts_list = [p.strip() for p in lower_mime.split(";")]
                for p in parts_list[1:]:
                    if not p:
                        continue
                    key, _, value = p.partition("=")
                    key, value = key.strip(), value.strip()
                    if key in ("rate", "samplerate") and value.isdigit():
                        parsed_rate = int(value)
                    elif key in ("channels", "ch") and value.isdigit():
                        parsed_channels = int(value)
                    elif key in ("bit", "bits", "bitdepth") and value.isdigit():
                        parsed_width = max(1, int(value) // 8)
                if "l16" in lower_mime and parsed_width == sample_width:
                    parsed_width = 2
            except Exception:
                parsed_rate, parsed_channels, parsed_width = sample_rate, channels, sample_width
            return parsed_rate, parsed_channels, parsed_width

        async def producer() -> None:
            nonlocal mime_notified, pcm_header_sent
            try:
                async with client.aio.live.connect(model=tts_config.model_id, config=live_config) as session:
                    await session.send_client_content(
                        turns=types.Content(role="user", parts=[types.Part.from_text(text=text)]),
                        turn_complete=True,
                    )
                    async for message in session.receive():
                        server_content = message.server_content
                        if not server_content or not server_content.model_turn:
                            continue
                        parts = server_content.model_turn.parts or []
                        for part in parts:
                            inline_data = getattr(part, "inline_data", None)
                            if inline_data and getattr(inline_data, "data", None):
                                mime_type = inline_data.mime_type or ""
                                lower_mime = mime_type.lower()
                                is_pcm = "pcm" in lower_mime or "l16" in lower_mime
                                is_audio = lower_mime.startswith("audio/") or is_pcm
                                if not is_audio:
                                    logger.debug("Google Live TTS ignoring non-audio inline data (mime=%s)", mime_type or "<none>")
                                    continue
                                if is_pcm:
                                    pcm_rate, pcm_ch, pcm_w = _parse_pcm_formats(mime_type)
                                    if not pcm_header_sent:
                                        header_bytes = _build_streaming_wav_header(pcm_rate, channels=pcm_ch, sample_width=pcm_w or 2)
                                        await queue.put(header_bytes)
                                        pcm_header_sent = True
                                        if on_mime_detected and not mime_notified:
                                            mime_notified = True
                                            on_mime_detected("audio/wav")
                                    await queue.put(bytes(inline_data.data))
                                else:
                                    if on_mime_detected and inline_data.mime_type and not mime_notified:
                                        mime_notified = True
                                        on_mime_detected(inline_data.mime_type)
                                    await queue.put(bytes(inline_data.data))
                        if server_content.turn_complete:
                            break
            except Exception as exc:
                await queue.put(exc)
            finally:
                await queue.put(None)

        producer_task = asyncio.create_task(producer())
        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    raise item
                if item:
                    yield item
        finally:
            if not producer_task.done():
                producer_task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await producer_task

    async def _generate_tts_bytes(self, text, tts_config, *, voice, response_format, **kwargs) -> Tuple[bytes, str, int]:
        default_params = tts_config.default_params.copy() if tts_config else {}
        sample_rate = int(kwargs.pop("sample_rate_hz", None) or default_params.get("sample_rate_hz", 24000))
        channels = int(default_params.get("channels", 1))
        google_mode = default_params.get("mode", "rest")

        if google_mode == "live":
            mime_holder: Dict[str, Optional[str]] = {"value": None}

            def _on_mime(m: str) -> None:
                if mime_holder["value"] is None:
                    mime_holder["value"] = m

            collected = bytearray()
            async for chunk in self._live_stream_tts_chunks(
                text, tts_config, voice=voice, response_format=response_format or "native", on_mime_detected=_on_mime,
            ):
                collected.extend(chunk)
            if not collected:
                raise ValueError("Google TTS returned no audio data")
            mime = mime_holder["value"] or default_params.get("native_mime_type", "audio/ogg; codecs=opus")
            return bytes(collected), mime, sample_rate

        if response_format != "wav":
            raise ValueError("Google TTS helper only supports WAV output")
        collected = bytearray()
        async for chunk in self._stream_tts_chunks(
            text, tts_config, voice=voice, response_format=response_format, sample_rate_hz=sample_rate,
        ):
            collected.extend(chunk)
        if not collected:
            raise ValueError("Google TTS returned no audio data")
        wav_bytes = _pcm_to_wav(bytes(collected), sample_rate=sample_rate, channels=channels, sample_width=2)
        return wav_bytes, "audio/wav", sample_rate

    # ------------------------------------------------------------------
    # Gemini Live Session factory (called from manager)
    # ------------------------------------------------------------------

    @staticmethod
    def create_live_session(
        tts_config: ModelConfig,
        *,
        user_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        live_config: Optional[types.LiveConnectConfig] = None,
    ) -> GeminiLiveSession:
        if not LLMConfig.is_gemini_live_duplex_enabled():
            raise RuntimeError("Gemini Live duplex mode is disabled in configuration")
        if not tts_config or tts_config.provider != ModelProvider.GOOGLE:
            raise RuntimeError("Gemini Live requires Google TTS provider to be active")
        api_key = LLMConfig.get_api_key(tts_config)
        if not api_key:
            raise RuntimeError("GOOGLE_API_KEY is not configured")

        if live_config is None:
            voice_name = (tts_config.default_params or {}).get("voice", LLMConfig.DEFAULT_TTS_VOICE)
            speech_cfg = types.SpeechConfig(
                voice_config=types.VoiceConfig(prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice_name))
            )
            gen_cfg = types.GenerationConfig(
                response_modalities=[types.Modality.AUDIO, types.Modality.TEXT],
                speech_config=speech_cfg,
            )
            live_config = types.LiveConnectConfig(generation_config=gen_cfg)

        metadata = metadata.copy() if metadata else {}
        metadata.setdefault("incremental_transcripts", LLMConfig.use_gemini_live_incremental_transcripts())
        metadata.setdefault("input_mime", "audio/pcm; rate=24000; channels=1; bit=16")

        return GeminiLiveSession(
            api_key=api_key, model_id=tts_config.model_id,
            live_config=live_config, user_id=user_id, metadata=metadata,
        )

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _build_gemini_contents(message: str, context: Optional[List[Dict[str, str]]]) -> list:
        contents = []
        if context:
            for msg in context:
                is_user = msg.get("isUser", False)
                content_text = msg.get("content", "")
                role = "user" if is_user else "model"
                contents.append({"role": role, "parts": [{"text": content_text}]})
        contents.append({"role": "user", "parts": [{"text": message}]})
        return contents

    @staticmethod
    def _build_gemini_config(system_instruction_text: Optional[str], config: ModelConfig, extra_kwargs: dict) -> dict:
        gen_config_params = config.default_params.copy()
        gen_config_params.update(extra_kwargs)
        request_config: Dict[str, Any] = {}
        if system_instruction_text:
            request_config["system_instruction"] = system_instruction_text
        if "temperature" in gen_config_params:
            request_config["temperature"] = gen_config_params.get("temperature", 0.7)
        if "max_tokens" in gen_config_params:
            request_config["max_output_tokens"] = gen_config_params.get("max_tokens", 2000)
        elif "maxOutputTokens" in gen_config_params:
            request_config["max_output_tokens"] = gen_config_params.get("maxOutputTokens", 2000)
        else:
            request_config["max_output_tokens"] = 2000
        if "top_p" in gen_config_params:
            request_config["top_p"] = gen_config_params.get("top_p", 1.0)
        if "top_k" in gen_config_params:
            request_config["top_k"] = gen_config_params.get("top_k")
        return request_config

    @staticmethod
    def _extract_text(response, model_id: str) -> str:
        if hasattr(response, "text") and response.text:
            return response.text
        if hasattr(response, "candidates") and response.candidates:
            candidate = response.candidates[0]
            if hasattr(candidate, "finish_reason") and candidate.finish_reason:
                finish_reason = str(candidate.finish_reason)
                if finish_reason == "MAX_TOKENS":
                    logger.warning("Google Gemini hit token limit.")
                    if hasattr(candidate, "content") and candidate.content:
                        if hasattr(candidate.content, "parts") and candidate.content.parts:
                            partial_text = candidate.content.parts[0].text
                            if partial_text and partial_text.strip():
                                return partial_text
                    return "I apologize, but my response was too long. Could you please ask a shorter or more specific question?"
                elif finish_reason in ("SAFETY", "BLOCKED"):
                    logger.warning("Google Gemini blocked response due to safety filters: %s", finish_reason)
                    return "I apologize, but I cannot provide a response to that request due to safety guidelines."
                elif finish_reason == "RECITATION":
                    logger.warning("Google Gemini blocked response due to recitation concerns: %s", finish_reason)
                    return "I apologize, but I cannot provide that specific information. Could you rephrase your question?"
            if hasattr(candidate, "content") and candidate.content:
                if hasattr(candidate.content, "parts") and candidate.content.parts:
                    return candidate.content.parts[0].text
                elif hasattr(candidate.content, "text"):
                    return candidate.content.text

        logger.error("Could not extract text from Google response. Response structure: %s", response)
        if hasattr(response, "usage_metadata"):
            usage = response.usage_metadata
            logger.error(
                "Token usage - Prompt: %s, Candidates: %s, Total: %s",
                getattr(usage, "prompt_token_count", "unknown"),
                getattr(usage, "candidates_token_count", "unknown"),
                getattr(usage, "total_token_count", "unknown"),
            )
        raise ValueError("Failed to extract text from Google Gemini response")


# =====================================================================
# Module-level helpers shared across the provider
# =====================================================================

def _build_streaming_wav_header(sample_rate: int, *, channels: int = 1, sample_width: int = 2) -> bytes:
    byte_rate = sample_rate * channels * sample_width
    block_align = channels * sample_width
    return struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF', 0xFFFFFFFF, b'WAVE', b'fmt ', 16, 1,
        channels, sample_rate, byte_rate, block_align,
        sample_width * 8, b'data', 0xFFFFFFFF,
    )


def _pcm_to_wav(pcm_bytes: bytes, *, sample_rate: int, channels: int = 1, sample_width: int = 2) -> bytes:
    with io.BytesIO() as buffer:
        with wave.open(buffer, "wb") as wav_file:
            wav_file.setnchannels(channels)
            wav_file.setsampwidth(sample_width)
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(pcm_bytes)
        return buffer.getvalue()
