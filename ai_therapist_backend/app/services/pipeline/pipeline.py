"""
Core EnhancedAsyncPipeline class: queue management, task lifecycle, client management,
LLM producer, TTS processor, client sender.

Flow control monitoring, metrics collection, and data models live in sibling modules.
"""

import asyncio
import base64
import json
import time
import logging
from datetime import datetime
from typing import Dict, Any, Optional, AsyncGenerator, List, Tuple, Union

from app.core.logging_utils import preview_text
from app.services.llm_manager import LLMManager
from app.core.llm_config import LLMConfig, ModelType
from app.utils.text_processor import SmartTextProcessor, TextChunk, BoundaryType

from . import format_strategy, sender_periodic, voice_policy
from .connection_registry import ConnectionRegistry
from .models import (
    PipelineState,
    StreamingMessage,
    AudioChunk,
    CompletionSentinel,
)
from .flow_control import (
    FlowControlState,
    FlowControlConfig,
    FlowControlMonitor,
)
from .metrics import PipelineMetrics, production_metrics


class EnhancedAsyncPipeline:
    """
    Enhanced async pipeline with comprehensive flow control, jitter buffer support,
    performance monitoring, memory management, interrupt handling, and production optimizations.

    Features:
    - Real-time TTS streaming with sub-400ms latency
    - Flow control and backpressure management
    - Jitter buffer guidance for mobile clients
    - Performance metrics and monitoring
    - Memory management and cleanup
    - Interrupt acknowledgment protocol
    - Multi-format TTS support with network adaptation
    """

    def __init__(self, config: FlowControlConfig, llm_manager: LLMManager):
        self.config = config
        self.llm_manager = llm_manager
        self.logger = logging.getLogger(__name__)

        # Validate LLMManager
        self._validate_llm_manager()

        self.state = PipelineState.IDLE

        # CRITICAL FIX: Add missing pipeline_id attribute
        self.pipeline_id = f"pipeline_{int(time.time() * 1000)}_{id(self)}"

        # Core components
        self.text_processor = SmartTextProcessor()

        # Async queues for pipeline stages
        self.llm_queue: asyncio.Queue[StreamingMessage] = asyncio.Queue(
            maxsize=self.config.max_llm_queue_size
        )
        self.tts_queue: asyncio.Queue[TextChunk] = asyncio.Queue(
            maxsize=self.config.max_tts_queue_size
        )
        self.client_queue: asyncio.Queue[Union[AudioChunk, CompletionSentinel]] = asyncio.Queue(
            maxsize=self.config.max_client_queue_size
        )

        # Pipeline tasks (will be created when pipeline starts)
        self.pipeline_tasks: List[asyncio.Task] = []
        self.shutdown_event = asyncio.Event()

        # Metrics and monitoring
        self.metrics = PipelineMetrics()
        self.flow_control_lock = asyncio.Lock()
        self.last_activity_time = time.time()

        # Client connections
        self.connections = ConnectionRegistry(self.logger)

        # Flow control monitor (owns flow_state, backpressure timing, stale chunks)
        self._fc_monitor = FlowControlMonitor(
            config=self.config,
            metrics=self.metrics,
            llm_queue=self.llm_queue,
            tts_queue=self.tts_queue,
            client_queue=self.client_queue,
            shutdown_event=self.shutdown_event,
            flow_control_lock=self.flow_control_lock,
        )

        # Interrupt handling state
        self.interrupt_requested = False
        self.interrupt_client_id: Optional[str] = None
        self.draining_start_time: Optional[float] = None
        self.pending_chunks_before_interrupt: int = 0

        # Performance monitoring
        self._setup_performance_monitoring()

        self.logger.info(
            f"Pipeline {self.pipeline_id} initialized successfully "
            f"with {self.config.max_client_queue_size} client queue size"
        )

    # ------------------------------------------------------------------
    # Proxy property so callers that read pipeline.flow_state still work
    # ------------------------------------------------------------------

    @property
    def flow_state(self) -> FlowControlState:
        return self._fc_monitor.flow_state

    @flow_state.setter
    def flow_state(self, value: FlowControlState):
        self._fc_monitor.flow_state = value

    @property
    def stale_chunk_timestamps(self) -> Dict[str, float]:
        return self._fc_monitor.stale_chunk_timestamps

    @property
    def backpressure_start_time(self) -> Optional[float]:
        return self._fc_monitor.backpressure_start_time

    @backpressure_start_time.setter
    def backpressure_start_time(self, value: Optional[float]):
        self._fc_monitor.backpressure_start_time = value

    # ------------------------------------------------------------------
    # Validation & setup
    # ------------------------------------------------------------------

    def _validate_llm_manager(self):
        """Simple validation that LLMManager is properly configured."""
        try:
            if not self.llm_manager:
                raise ValueError("LLMManager is None")

            if not self.llm_manager.tts_config:
                raise ValueError("LLMManager has no TTS configuration")

            if not hasattr(self.llm_manager, 'llm_config') or not self.llm_manager.llm_config:
                self.logger.warning("LLMManager has no LLM configuration - TTS-only mode")

            self.logger.info(f"LLM validation passed: TTS provider = {self.llm_manager.tts_config.provider}")
            return True

        except Exception as e:
            self.logger.error(f"LLMManager validation failed: {e}")
            raise

    def _setup_performance_monitoring(self):
        """Initialize performance monitoring components and metrics tracking"""
        try:
            self.performance_timers = {
                "llm_start_time": None,
                "tts_start_time": None,
                "request_start_time": None,
                "first_audio_time": None
            }
            self.performance_counters = {
                "requests_processed": 0,
                "audio_chunks_sent": 0,
                "errors_encountered": 0,
                "backpressure_events": 0
            }
            self.memory_tracker = {
                "peak_usage": 0,
                "current_usage": 0,
                "last_check": time.time()
            }
            self.production_metrics_enabled = production_metrics.is_metrics_enabled()
            self.last_performance_report = time.time()
            self.performance_report_interval = 30
            self.performance_targets = {
                "time_to_first_audio_ms": 400,
                "avg_end_to_end_ms": 300,
                "max_queue_wait_ms": 100
            }
            self.logger.info("Performance monitoring initialized successfully")
        except Exception as e:
            self.logger.error(f"Failed to initialize performance monitoring: {str(e)}")
            self.production_metrics_enabled = False

    # ------------------------------------------------------------------
    # Lifecycle: start / stop
    # ------------------------------------------------------------------

    async def start(self) -> None:
        """Start the async pipeline with all components"""
        if self.state != PipelineState.IDLE:
            raise RuntimeError(f"Pipeline already running (state: {self.state})")

        self.state = PipelineState.INITIALIZING
        self.logger.info("Starting enhanced async pipeline...")

        try:
            await self._cleanup_tasks()

            self.pipeline_tasks = [
                asyncio.create_task(self._llm_producer()),
                asyncio.create_task(self._tts_processor()),
                asyncio.create_task(self._client_sender()),
                asyncio.create_task(self._fc_monitor.run_flow_control_monitor()),
                asyncio.create_task(self._fc_monitor.run_memory_monitor()),
                asyncio.create_task(self._fc_monitor.run_stale_chunk_cleaner()),
            ]

            self.state = PipelineState.STREAMING
            self.logger.info("Pipeline started successfully")

        except Exception as e:
            self.state = PipelineState.ERROR
            self.logger.error(f"Failed to start pipeline: {e}")
            await self._cleanup_tasks()
            raise

    async def stop(self) -> None:
        """Gracefully stop the pipeline"""
        if self.state == PipelineState.IDLE:
            return

        self.state = PipelineState.STOPPING
        self.logger.info("Stopping pipeline...")

        self.shutdown_event.set()
        await self._cleanup_tasks()
        await self._clear_queues()

        self.state = PipelineState.IDLE
        self.flow_state = FlowControlState.FLOWING
        self.shutdown_event.clear()
        self.logger.info("Pipeline stopped")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def add_message(self, message: StreamingMessage) -> bool:
        """Add a message to the pipeline for processing."""
        if self.state != PipelineState.STREAMING:
            raise RuntimeError(f"Pipeline not streaming (state: {self.state})")

        try:
            if self.flow_state == FlowControlState.PAUSED:
                self.logger.warning("Message rejected - pipeline paused")
                return False

            await asyncio.wait_for(self.llm_queue.put(message), timeout=1.0)
            self.metrics.messages_processed += 1
            self.last_activity_time = time.time()
            return True

        except asyncio.TimeoutError:
            self.logger.warning("Message rejected - LLM queue full")
            self.metrics.backpressure_events += 1
            return False
        except Exception as e:
            self.logger.error(f"Error adding message: {e}")
            return False

    async def get_init_frame(self, client_id: str) -> Dict[str, Any]:
        """Generate initialization frame with jitter buffer guidance."""
        return {
            "type": "init",
            "client_id": client_id,
            "pipeline_version": "2.0",
            "capabilities": {
                "streaming_tts": True,
                "real_time_audio": True,
                "backpressure_control": True,
                "stale_detection": True
            },
            "jitter_buffer": {
                "min_ms": self.config.jitter_buffer_min_ms,
                "max_ms": self.config.jitter_buffer_max_ms,
                "target_ms": self.config.jitter_buffer_target_ms,
                "guidance": "Buffer 200ms for optimal latency/quality tradeoff"
            },
            "audio_format": {
                "encoding": "pcm",
                "sample_rate": 16000,
                "channels": 1,
                "bit_depth": 16
            },
            "flow_control": {
                "sequence_tracking": True,
                "chunk_acknowledgment": False,
                "max_buffer_chunks": 10
            },
            "performance_targets": {
                "time_to_first_audio_ms": self.metrics.target_ttfa_ms,
                "target_latency_ms": self.metrics.target_latency_ms
            },
            "timestamp": datetime.now().isoformat()
        }

    async def register_client(self, client_id: str, websocket) -> Dict[str, Any]:
        """Register a new client connection."""
        self.connections.register(client_id, websocket)
        return await self.get_init_frame(client_id)

    async def unregister_client(self, client_id: str) -> None:
        """Unregister a client connection."""
        await self.connections.unregister(client_id)

    def get_metrics(self) -> Dict[str, Any]:
        """Get comprehensive pipeline metrics for monitoring and optimization"""
        return {
            "pipeline_state": self.state.value,
            "flow_control_state": self.flow_state.value,
            "throughput": {
                "messages_processed": self.metrics.messages_processed,
                "chunks_generated": self.metrics.chunks_generated,
                "audio_chunks_sent": self.metrics.audio_chunks_sent
            },
            "timing": {
                "avg_llm_latency_ms": self.metrics.avg_llm_latency_ms,
                "avg_tts_latency_ms": self.metrics.avg_tts_latency_ms,
                "avg_end_to_end_ms": self.metrics.avg_end_to_end_ms,
                "time_to_first_audio_ms": self.metrics.time_to_first_audio_ms
            },
            "queues": {
                "llm_queue_size": self.llm_queue.qsize(),
                "tts_queue_size": self.tts_queue.qsize(),
                "client_queue_size": self.client_queue.qsize(),
                "max_sizes": {
                    "llm": self.config.max_llm_queue_size,
                    "tts": self.config.max_tts_queue_size,
                    "client": self.config.max_client_queue_size
                }
            },
            "performance": {
                "backpressure_events": self.metrics.backpressure_events,
                "stale_chunks_dropped": self.metrics.stale_chunks_dropped,
                "flow_control_pauses": self.metrics.flow_control_pauses,
                "memory_usage_bytes": self.metrics.memory_usage_bytes,
                "peak_memory_bytes": self.metrics.peak_memory_bytes
            },
            "errors": {
                "llm_errors": self.metrics.llm_errors,
                "tts_errors": self.metrics.tts_errors,
                "client_errors": self.metrics.client_errors
            },
            "targets": {
                "target_ttfa_ms": self.metrics.target_ttfa_ms,
                "target_latency_ms": self.metrics.target_latency_ms
            },
            "active_clients": len(self.connections)
        }

    # ------------------------------------------------------------------
    # Network quality & format selection
    # ------------------------------------------------------------------

    def assess_network_quality(self, client_metrics: Dict[str, Any]) -> str:
        return format_strategy.assess_network_quality(client_metrics, self.config)

    def select_optimal_format(
        self, network_quality: str, client_capabilities: Dict[str, Any]
    ) -> str:
        return format_strategy.select_optimal_format(
            network_quality, client_capabilities, self.config
        )

    def get_format_parameters(self, audio_format: str) -> Dict[str, Any]:
        return format_strategy.get_format_parameters(audio_format)

    # ------------------------------------------------------------------
    # Interrupt handling
    # ------------------------------------------------------------------

    async def request_interrupt(self, client_id: str) -> bool:
        """Request pipeline interruption for new user input"""
        if self.interrupt_requested:
            self.logger.info(f"Interrupt already in progress, ignoring request from {client_id}")
            return False

        self.logger.info(f"Interrupt requested by client {client_id}")
        self.interrupt_requested = True
        self.interrupt_client_id = client_id
        self.draining_start_time = time.time()

        self.pending_chunks_before_interrupt = (
            self.llm_queue.qsize() +
            self.tts_queue.qsize() +
            self.client_queue.qsize()
        )

        async with self.flow_control_lock:
            self.flow_state = FlowControlState.INTERRUPTING

        await self.drain_pipeline()
        return True

    async def drain_pipeline(self) -> None:
        """Drain the pipeline of pending chunks to prepare for new input"""
        self.logger.info("Starting pipeline drainage for interrupt")

        async with self.flow_control_lock:
            self.flow_state = FlowControlState.DRAINING

        await self._clear_queues()
        await asyncio.sleep(0.1)
        await self.send_interrupt_ack()

    async def send_interrupt_ack(self) -> None:
        """Send interrupt acknowledgment after pipeline drainage is complete"""
        if not self.interrupt_requested or not self.interrupt_client_id:
            return

        client_id = self.interrupt_client_id
        drain_time_ms = (time.time() - self.draining_start_time) * 1000 if self.draining_start_time else 0

        interrupt_ack = {
            "type": "interrupt_ack",
            "client_id": client_id,
            "timestamp": datetime.now().isoformat(),
            "drainage_info": {
                "chunks_cleared": self.pending_chunks_before_interrupt,
                "drain_time_ms": round(drain_time_ms, 2),
                "pipeline_ready": True
            },
            "pipeline_state": {
                "flow_state": "ready_for_input",
                "queue_sizes": {
                    "llm": self.llm_queue.qsize(),
                    "tts": self.tts_queue.qsize(),
                    "client": self.client_queue.qsize()
                }
            }
        }

        websocket = self.connections.get(client_id)
        if websocket is not None:
            try:
                await websocket.send(json.dumps(interrupt_ack))
                self.logger.info(f"Interrupt acknowledgment sent to {client_id} (drain time: {drain_time_ms:.1f}ms)")
            except Exception as e:
                self.logger.warning(f"Failed to send interrupt ack to {client_id}: {e}")

        self.interrupt_requested = False
        self.interrupt_client_id = None
        self.draining_start_time = None
        self.pending_chunks_before_interrupt = 0

        async with self.flow_control_lock:
            self.flow_state = FlowControlState.FLOWING

        self.logger.info("Pipeline interrupt handling completed, ready for new input")

    def is_interrupting(self) -> bool:
        """Check if pipeline is currently handling an interrupt"""
        return self.interrupt_requested or self.flow_state in [
            FlowControlState.INTERRUPTING, FlowControlState.DRAINING
        ]

    # ------------------------------------------------------------------
    # LLM producer
    # ------------------------------------------------------------------

    async def _llm_producer(self) -> None:
        """LLM producer component with flow control integration."""
        self.logger.info("LLM producer started")
        conversation_sequence = 0

        while not self.shutdown_event.is_set():
            try:
                if self.flow_state == FlowControlState.PAUSED:
                    await asyncio.sleep(0.01)
                    continue

                try:
                    message = await asyncio.wait_for(self.llm_queue.get(), timeout=0.1)
                except asyncio.TimeoutError:
                    continue

                if self.flow_state in [FlowControlState.PAUSED, FlowControlState.THROTTLED]:
                    await self.llm_queue.put(message)
                    await asyncio.sleep(0.1)
                    continue

                start_time = time.time()
                try:
                    await self._process_llm_message(message, conversation_sequence)
                    conversation_sequence += 1
                    processing_time = (time.time() - start_time) * 1000
                    self.metrics.update_timing("avg_llm_latency_ms", processing_time)
                except Exception as e:
                    self.logger.error(f"Error processing LLM message {message.message_id}: {e}")
                    self.metrics.llm_errors += 1

                self.llm_queue.task_done()
                self.last_activity_time = time.time()

            except Exception as e:
                self.logger.error(f"LLM producer error: {e}")
                self.metrics.llm_errors += 1
                await asyncio.sleep(1.0)

        self.logger.info("LLM producer stopped")

    async def _process_llm_message(self, message: StreamingMessage, conversation_sequence: int) -> None:
        """Process a single LLM message with streaming response generation."""
        sentence_id = 0
        text_buffer = ""
        ttfa_start_time = time.time()

        try:
            if message.metadata.get("is_tts_only", False):
                self.logger.info(f"Processing TTS-only request for message {message.message_id}")
                await self._process_tts_only_message(message, conversation_sequence)
                return

            conversation_context = {
                "conversation_id": message.conversation_id,
                "message_id": message.message_id,
                "sequence": conversation_sequence,
                "voice_seed": self._get_voice_seed(message.conversation_id),
                "timestamp": message.timestamp.isoformat()
            }

            async for chunk_text in self._stream_llm_response(message):
                if self.shutdown_event.is_set():
                    break

                text_buffer += chunk_text
                sentences = self.text_processor.add_text(chunk_text)

                for text_chunk in sentences:
                    if text_chunk.text.strip():
                        text_chunk.metadata.update({
                            **conversation_context,
                            "sentence_id": f"{message.message_id}_{sentence_id}",
                            "sequence": sentence_id,
                            "is_sentence_end": True,
                            "voice_consistency_seed": conversation_context["voice_seed"],
                            "interruption_safe": True,
                            "prosody_complete": True
                        })

                        success = await self._add_to_tts_queue(text_chunk)
                        if success:
                            sentence_id += 1
                            self.metrics.chunks_generated += 1
                            if sentence_id == 1:
                                ttfa_ms = (time.time() - ttfa_start_time) * 1000
                                self.metrics.update_timing("time_to_first_audio_ms", ttfa_ms)
                        else:
                            self.logger.warning(f"Failed to queue sentence for TTS: {text_chunk.metadata['sentence_id']}")

            final_chunk = self.text_processor.flush_buffer()
            if final_chunk and final_chunk.text.strip():
                final_chunk.metadata.update({
                    **conversation_context,
                    "sentence_id": f"{message.message_id}_{sentence_id}",
                    "sequence": sentence_id,
                    "is_sentence_end": True,
                    "is_response_end": True,
                    "voice_consistency_seed": conversation_context["voice_seed"],
                    "interruption_safe": True,
                    "prosody_complete": True
                })
                await self._add_to_tts_queue(final_chunk)
                sentence_id += 1
                self.metrics.chunks_generated += 1

            self.logger.info(f"LLM message processed: {sentence_id} sentences generated for {message.message_id}")

        except Exception as e:
            self.logger.error(f"Error in LLM message processing: {e}")
            self.metrics.llm_errors += 1

            try:
                fallback_message = StreamingMessage(
                    message_id=f"{message.message_id}_fallback",
                    conversation_id=message.conversation_id,
                    user_message="I apologize, but I'm having trouble generating a response. Please try again.",
                    metadata={
                        "is_tts_only": True,
                        "is_fallback": True,
                        "original_error": str(e),
                        "voice": "nova"
                    }
                )
                await self._process_tts_only_message(fallback_message, conversation_sequence)
                self.logger.info("Fallback response generated via TTS-only path")
            except Exception as fallback_error:
                self.logger.error(f"Fallback response generation failed: {fallback_error}")

    async def _process_tts_only_message(self, message: StreamingMessage, conversation_sequence: int) -> None:
        """Process a TTS-only message (Maya's response already generated)."""
        sentence_id = 0
        ttfa_start_time = time.time()

        try:
            conversation_context = {
                "conversation_id": message.conversation_id,
                "message_id": message.message_id,
                "sequence": conversation_sequence,
                "voice_seed": self._get_voice_seed(message.conversation_id),
                "timestamp": message.timestamp.isoformat(),
                "is_tts_only": True
            }

            self.text_processor.reset()
            sentences = self.text_processor.add_text(message.user_message)

            for text_chunk in sentences:
                if text_chunk.text.strip():
                    text_chunk.metadata.update({
                        **conversation_context,
                        "sentence_id": f"{message.message_id}_{sentence_id}",
                        "sequence": sentence_id,
                        "is_sentence_end": True,
                        "voice_consistency_seed": conversation_context["voice_seed"],
                        "interruption_safe": True,
                        "prosody_complete": True,
                        "tts_voice": message.metadata.get("voice", "nova"),
                        "tts_params": message.metadata.get("tts_params", {})
                    })

                    success = await self._add_to_tts_queue(text_chunk)
                    if success:
                        sentence_id += 1
                        self.metrics.chunks_generated += 1
                        if sentence_id == 1:
                            ttfa_ms = (time.time() - ttfa_start_time) * 1000
                            self.metrics.update_timing("time_to_first_audio_ms", ttfa_ms)
                    else:
                        self.logger.warning(f"Failed to queue TTS sentence: {text_chunk.metadata['sentence_id']}")

            final_chunk = self.text_processor.flush_buffer()
            if final_chunk and final_chunk.text.strip():
                final_chunk.metadata.update({
                    **conversation_context,
                    "sentence_id": f"{message.message_id}_{sentence_id}",
                    "sequence": sentence_id,
                    "is_sentence_end": True,
                    "is_response_end": True,
                    "voice_consistency_seed": conversation_context["voice_seed"],
                    "interruption_safe": True,
                    "prosody_complete": True,
                    "tts_voice": message.metadata.get("voice", "nova"),
                    "tts_params": message.metadata.get("tts_params", {})
                })
                await self._add_to_tts_queue(final_chunk)
                sentence_id += 1
                self.metrics.chunks_generated += 1

            self.logger.info(f"TTS-only message processed: {sentence_id} sentences generated for {message.message_id}")

        except Exception as e:
            self.logger.error(f"Error in TTS-only message processing: {e}")
            self.metrics.llm_errors += 1
            raise

    async def _stream_llm_response(self, message: StreamingMessage) -> AsyncGenerator[str, None]:
        """Stream LLM response using existing LLMManager (provider-agnostic)."""
        try:
            context = message.metadata.get('context', [])
            system_prompt = message.metadata.get('system_prompt', '')
            user_info = message.metadata.get('user_info')

            llm_kwargs = {}
            valid_params = ['temperature', 'max_tokens', 'top_p', 'top_k', 'frequency_penalty', 'presence_penalty']
            for param in valid_params:
                if param in message.metadata:
                    llm_kwargs[param] = message.metadata[param]

            async for chunk in self.llm_manager.stream_chat_completion(
                message=message.user_message,
                context=context,
                system_prompt=system_prompt,
                user_info=user_info,
                **llm_kwargs
            ):
                chunk_text = self._extract_chunk_text(chunk)
                if chunk_text:
                    yield chunk_text

        except Exception as e:
            self.logger.error(f"Error streaming LLM response: {e}")
            self.metrics.llm_errors += 1
            raise

    def _extract_chunk_text(self, chunk: Any) -> str:
        """Extract text content from LLM response chunk (provider-agnostic)."""
        try:
            if isinstance(chunk, str):
                return chunk
            elif isinstance(chunk, dict):
                if "choices" in chunk and len(chunk["choices"]) > 0:
                    delta = chunk["choices"][0].get("delta", {})
                    return delta.get("content", "")
                elif "delta" in chunk:
                    return chunk["delta"].get("text", "")
                elif "content" in chunk:
                    return chunk["content"]
                elif "text" in chunk:
                    return chunk["text"]
            elif hasattr(chunk, 'content'):
                return getattr(chunk, 'content', "")
            elif hasattr(chunk, 'text'):
                return getattr(chunk, 'text', "")
            return str(chunk) if chunk else ""
        except Exception as e:
            self.logger.warning(f"Error extracting chunk text: {e}")
            return ""

    def _get_voice_seed(self, conversation_id: str) -> str:
        return voice_policy.voice_seed(conversation_id)

    # ------------------------------------------------------------------
    # TTS queue helpers
    # ------------------------------------------------------------------

    async def _add_to_tts_queue(self, text_chunk: TextChunk) -> bool:
        """Add text chunk to TTS queue with flow control."""
        try:
            if self.flow_state == FlowControlState.PAUSED:
                self.logger.warning("TTS queue add rejected - pipeline paused")
                return False
            timeout = 2.0 if self.flow_state == FlowControlState.FLOWING else 0.5
            await asyncio.wait_for(self.tts_queue.put(text_chunk), timeout=timeout)
            return True
        except asyncio.TimeoutError:
            self.logger.warning(f"TTS queue timeout for chunk: {text_chunk.metadata.get('sentence_id', 'unknown')}")
            self.metrics.backpressure_events += 1
            return False
        except Exception as e:
            self.logger.error(f"Error adding to TTS queue: {e}")
            return False

    # ------------------------------------------------------------------
    # TTS processor
    # ------------------------------------------------------------------

    async def _tts_processor(self) -> None:
        """TTS processor component with quality controls and streaming audio generation."""
        self.logger.info("TTS processor started")
        conversation_voices: Dict[str, str] = {}

        while not self.shutdown_event.is_set():
            try:
                if self.flow_state == FlowControlState.PAUSED:
                    await asyncio.sleep(0.01)
                    continue

                try:
                    text_chunk = await asyncio.wait_for(self.tts_queue.get(), timeout=0.1)
                except asyncio.TimeoutError:
                    continue

                if self.flow_state in [FlowControlState.PAUSED, FlowControlState.THROTTLED]:
                    await self.tts_queue.put(text_chunk)
                    await asyncio.sleep(0.1)
                    continue

                start_time = time.time()
                try:
                    await self._process_tts_chunk(text_chunk, conversation_voices)
                    processing_time = (time.time() - start_time) * 1000
                    self.metrics.update_timing("avg_tts_latency_ms", processing_time)
                except Exception as e:
                    self.logger.error(f"Error processing TTS chunk {text_chunk.metadata.get('sentence_id', 'unknown')}: {e}")
                    self.metrics.tts_errors += 1

                self.tts_queue.task_done()
                self.last_activity_time = time.time()

            except Exception as e:
                self.logger.error(f"TTS processor error: {e}")
                self.metrics.tts_errors += 1
                await asyncio.sleep(1.0)

        self.logger.info("TTS processor stopped")

    async def _process_tts_chunk(self, text_chunk: TextChunk, conversation_voices: Dict[str, str]) -> None:
        """Process text chunk through TTS generation with adaptive format selection"""
        chunk_timestamp = time.time()
        sentence_id = text_chunk.metadata.get("sentence_id", "unknown")
        conversation_id = text_chunk.metadata.get("conversation_id", "unknown")

        voice = self._select_voice(
            client_voice=text_chunk.metadata.get("voice"),
            conversation_id=conversation_id
        )

        from app.core.config import settings
        if settings.VERBOSE_AUDIO_CHUNKS:
            self.logger.debug(f"Selected voice '{voice}' for text: '{text_chunk.text[:50]}...'")

        try:
            client_metadata = text_chunk.metadata
            client_requested_format = text_chunk.metadata.get("format", "wav")
            optimal_format = client_requested_format
            format_params = self.get_format_parameters(optimal_format)

            audio_chunks_generated = 0
            sentence_id = f"{conversation_id}_{text_chunk.sequence_id}"

            network_metrics = client_metadata.get("network_metrics", {})
            network_quality = self.assess_network_quality(network_metrics) if network_metrics else "good"

            self.logger.info(f"TTS processing: format={optimal_format}, network={network_quality}, preview='{preview_text(text_chunk.text)}'")
            self.logger.debug(f"TTS full text: {text_chunk.text}")

            tts_params = {
                "voice": voice,
                "conversation_id": conversation_id,
                "response_format": format_params["response_format"],
                "stream": True,
                "chunk_size": 1024,
                "real_time": True
            }

            if optimal_format == "opus":
                client_opus_params = client_metadata.get("opus_params", {})
                tts_params["bitrate"] = str(client_opus_params.get("bitrate", format_params.get("bitrate", 64000)))
                tts_params["sample_rate"] = client_opus_params.get("sample_rate", format_params.get("sample_rate", 48000))
                tts_params["channels"] = client_opus_params.get("channels", 1)
            elif optimal_format == "aac":
                tts_params["bitrate"] = format_params.get("bitrate", "64k")
                tts_params["sample_rate"] = format_params.get("sample_rate", 48000)

            async for audio_chunk_b64 in self._stream_tts_audio(text_chunk.text, tts_params):
                if self.shutdown_event.is_set():
                    break

                try:
                    audio_data = base64.b64decode(audio_chunk_b64)
                except Exception as e:
                    self.logger.warning(f"Failed to decode audio chunk: {e}")
                    continue

                audio_chunk = AudioChunk(
                    chunk_id=f"{sentence_id}_{audio_chunks_generated}",
                    sentence_id=sentence_id,
                    sequence=text_chunk.sequence_id,
                    audio_data=audio_data,
                    is_sentence_end=(audio_chunks_generated == 0),
                    boundary_type=text_chunk.boundary_type,
                    metadata={
                        **text_chunk.metadata,
                        "audio_format": optimal_format,
                        "voice_used": voice,
                        "chunk_index": audio_chunks_generated,
                        "total_chunks": "unknown",
                        "tts_processing_time_ms": (time.time() - chunk_timestamp) * 1000,
                        "is_realtime": True,
                        "streaming": True,
                        "boundary_type": text_chunk.boundary_type.value,
                        "network_quality": network_quality,
                        "format_params": format_params,
                        "estimated_bitrate_kbps": format_params["estimated_bitrate_kbps"]
                    }
                )

                success = await self._add_to_client_queue(audio_chunk)
                if success:
                    audio_chunks_generated += 1
                    self.metrics.chunks_generated += 1
                    if audio_chunks_generated == 1:
                        ttfa_ms = (time.time() - chunk_timestamp) * 1000
                        self.metrics.update_timing("time_to_first_audio_ms", ttfa_ms)
                        self.logger.info(f"Time to first audio: {ttfa_ms:.1f}ms (format: {optimal_format})")
                else:
                    self.logger.warning(f"Failed to queue audio chunk {audio_chunks_generated} for {sentence_id}")
                    break

            total_latency = (time.time() - chunk_timestamp) * 1000
            self.metrics.update_timing("avg_tts_latency_ms", total_latency)

            self.logger.info(f"TTS completed for preview='{preview_text(text_chunk.text, max_length=30)}': {audio_chunks_generated} chunks, {total_latency:.1f}ms, format: {optimal_format}")

            completion_sentinel = CompletionSentinel(
                request_id=text_chunk.metadata.get("message_id", sentence_id),
                conversation_id=conversation_id,
                total_chunks=audio_chunks_generated,
                metadata={
                    "sentence_id": sentence_id,
                    "text_processed": text_chunk.text[:50] + "..." if len(text_chunk.text) > 50 else text_chunk.text,
                    "total_latency_ms": total_latency,
                    "audio_format": optimal_format,
                    "voice_used": voice,
                    "sequence": text_chunk.sequence_id,
                    "processing_timestamp": datetime.now().isoformat()
                }
            )

            success = await self._add_completion_sentinel_to_queue(completion_sentinel)
            if success:
                self.logger.debug(f"Added completion sentinel for request {completion_sentinel.request_id}")
            else:
                self.logger.warning(f"Failed to add completion sentinel for {completion_sentinel.request_id}")

        except Exception as e:
            self.logger.error(f"TTS processing error for text '{text_chunk.text[:50]}...': {str(e)}")
            self.metrics.tts_errors += 1
            self.logger.warning(f"TTS failed for chunk {sentence_id}, will retry upstream if needed")
            raise

    async def _stream_tts_audio(self, text: str, tts_params: Dict[str, Any]) -> AsyncGenerator[str, None]:
        """Stream TTS audio using existing LLMManager (provider-agnostic)."""
        try:
            valid_tts_params = {}
            expected_params = ['voice', 'response_format', 'speed', 'pitch']
            for param in expected_params:
                if param in tts_params:
                    valid_tts_params[param] = tts_params[param]

            valid_tts_params.pop('conversation_id', None)
            valid_tts_params.pop('stream', None)
            valid_tts_params.pop('chunk_size', None)
            valid_tts_params.pop('real_time', None)

            opus_params = None
            response_format = tts_params.get('response_format', 'wav')
            if response_format in ['opus', 'ogg_opus']:
                opus_params = {
                    'sample_rate': tts_params.get('sample_rate', 48000),
                    'channels': 1,
                    'bitrate': int(str(tts_params.get('bitrate', '64000')).replace('k', '000'))
                }
                self.logger.info(f"Using OPUS format with params: {opus_params}")
            else:
                self.logger.info(f"Using {response_format.upper()} format (no OPUS processing)")

            async for chunk_b64 in self.llm_manager.stream_text_to_speech(
                text=text,
                opus_params=opus_params,
                **valid_tts_params
            ):
                yield chunk_b64

        except Exception as e:
            self.logger.error(f"Error streaming TTS audio: {e}")
            self.metrics.tts_errors += 1
            raise

    # ------------------------------------------------------------------
    # Voice & format helpers (delegate to focused modules)
    # ------------------------------------------------------------------

    def _select_voice(
        self,
        client_voice: Optional[str] = None,
        conversation_id: Optional[str] = None,
    ) -> str:
        return voice_policy.select_voice(client_voice, conversation_id, self.llm_manager)

    def _get_validated_format(self, requested_format: str) -> str:
        return format_strategy.validated_format(requested_format, self.llm_manager)

    # ------------------------------------------------------------------
    # Client queue helpers & sender
    # ------------------------------------------------------------------

    async def _add_to_client_queue(self, audio_chunk: AudioChunk) -> bool:
        """Add audio chunk to client queue with flow control."""
        try:
            if self.flow_state == FlowControlState.PAUSED:
                self.logger.warning("Client queue add rejected - pipeline paused")
                return False
            timeout = 2.0 if self.flow_state == FlowControlState.FLOWING else 0.5
            await asyncio.wait_for(self.client_queue.put(audio_chunk), timeout=timeout)
            return True
        except asyncio.TimeoutError:
            self.logger.warning(f"Client queue timeout for chunk: {audio_chunk.chunk_id}")
            self.metrics.backpressure_events += 1
            return False
        except Exception as e:
            self.logger.error(f"Error adding to client queue: {e}")
            return False

    async def _add_completion_sentinel_to_queue(self, completion_sentinel: CompletionSentinel) -> bool:
        """Add completion sentinel to client queue with flow control."""
        try:
            if self.flow_state == FlowControlState.PAUSED:
                self.logger.warning("Completion sentinel add rejected - pipeline paused")
                return False
            timeout = 2.0 if self.flow_state == FlowControlState.FLOWING else 0.5
            await asyncio.wait_for(self.client_queue.put(completion_sentinel), timeout=timeout)
            return True
        except asyncio.TimeoutError:
            self.logger.warning(f"Client queue timeout for completion sentinel: {completion_sentinel.request_id}")
            self.metrics.backpressure_events += 1
            return False
        except Exception as e:
            self.logger.error(f"Error adding completion sentinel to client queue: {e}")
            return False

    async def _client_sender(self) -> None:
        """Client sender with jitter buffer support."""
        self.logger.info("Client sender started")
        chunks_sent = 0
        sequence_counter = 0
        last_checkpoint_time = time.time()
        checkpoint_interval = 5.0
        last_performance_log = time.time()
        performance_log_interval = 10.0

        while not self.shutdown_event.is_set():
            try:
                try:
                    queue_item = await asyncio.wait_for(self.client_queue.get(), timeout=1.0)
                except asyncio.TimeoutError:
                    await self._handle_periodic_tasks(
                        last_checkpoint_time, last_performance_log,
                        checkpoint_interval, performance_log_interval,
                        sequence_counter, chunks_sent
                    )
                    continue

                if isinstance(queue_item, CompletionSentinel):
                    completion_frame = {
                        "type": "tts_complete",
                        "request_id": queue_item.request_id,
                        "conversation_id": queue_item.conversation_id,
                        "total_chunks": queue_item.total_chunks,
                        "completion_timestamp": queue_item.completion_timestamp.isoformat(),
                        "status": "success",
                        "metadata": queue_item.metadata
                    }
                    completion_sent_count = await self._send_to_active_clients(completion_frame, f"completion_{queue_item.request_id}")
                    if completion_sent_count > 0:
                        self.logger.info(f"Sent completion signal for request {queue_item.request_id} to {completion_sent_count} clients")
                    else:
                        self.logger.warning(f"Failed to send completion signal for request {queue_item.request_id}")
                    continue

                audio_chunk = queue_item

                if self.flow_state == FlowControlState.PAUSED:
                    from app.core.config import settings
                    if settings.VERBOSE_AUDIO_CHUNKS:
                        self.logger.debug(f"Skipping chunk {audio_chunk.chunk_id} - flow control paused")
                    continue

                audio_frame, binary_data = self._prepare_audio_frame(audio_chunk, sequence_counter)
                sent_count = await self._send_to_active_clients(audio_frame, audio_chunk.chunk_id, binary_data)

                if sent_count > 0:
                    chunks_sent += 1
                    sequence_counter += 1
                    self.metrics.audio_chunks_sent += 1
                    chunk_age_ms = (time.time() - audio_chunk.timestamp.timestamp()) * 1000
                    self.metrics.update_timing("avg_end_to_end_ms", chunk_age_ms)

                current_time = time.time()
                if current_time - last_checkpoint_time >= checkpoint_interval:
                    await self._send_checkpoint_frame(sequence_counter, chunks_sent)
                    last_checkpoint_time = current_time
                if current_time - last_performance_log >= performance_log_interval:
                    await self._log_performance_metrics(chunks_sent, sequence_counter)
                    last_performance_log = current_time

            except Exception as e:
                self.logger.error(f"Client sender error: {e}")
                self.metrics.client_errors += 1
                await asyncio.sleep(0.1)

        await self._handle_clean_disconnection(sequence_counter, chunks_sent)
        self.logger.info("Client sender stopped")

    def _get_dynamic_audio_format(self, chunk_metadata: Dict[str, Any]) -> Dict[str, Any]:
        return format_strategy.dynamic_audio_format(chunk_metadata, self.config)

    def _prepare_audio_frame(self, audio_chunk: AudioChunk, sequence_counter: int, use_binary: bool = False) -> Tuple[Dict[str, Any], bytes]:
        """Prepare audio frame with complete jitter buffer metadata."""
        chunk_metadata = audio_chunk.metadata if isinstance(audio_chunk.metadata, dict) else {}

        metadata = {
            "type": "audio",
            "chunk_id": audio_chunk.chunk_id,
            "sentence_id": audio_chunk.sentence_id,
            "sequence": sequence_counter,
            "is_sentence_end": audio_chunk.is_sentence_end,
            "boundary_type": audio_chunk.boundary_type.value if audio_chunk.boundary_type else "unknown",
            "timestamp": audio_chunk.timestamp.isoformat(),
            "jitter_buffer": {
                "sequence_id": sequence_counter,
                "buffer_hint_ms": self.config.jitter_buffer_target_ms,
                "is_realtime": True,
                "max_age_ms": 500
            },
            "performance": {
                "generation_latency_ms": round(self.metrics.avg_tts_latency_ms, 2),
                "end_to_end_latency_ms": round(self.metrics.avg_end_to_end_ms, 2),
                "sequence_number": sequence_counter
            },
            "audio_format": self._get_dynamic_audio_format(chunk_metadata),
            "metadata": {
                **chunk_metadata,
                "pipeline_sequence": sequence_counter,
                "flow_control_state": self.flow_state.value
            }
        }

        if use_binary:
            metadata["audio_length"] = len(audio_chunk.audio_data)
            metadata["frame_format"] = "binary"
            return metadata, audio_chunk.audio_data
        else:
            metadata["audio_data"] = base64.b64encode(audio_chunk.audio_data).decode()
            metadata["frame_format"] = "json"
            return metadata, None

    async def _send_to_active_clients(
        self,
        audio_frame: Dict[str, Any],
        chunk_id: str,
        binary_data: Optional[bytes] = None,
    ) -> int:
        sent_count, failed_count = await self.connections.send_to_all(
            audio_frame, chunk_id, binary_data
        )
        if failed_count:
            self.metrics.client_errors += failed_count
        return sent_count

    async def _send_checkpoint_frame(self, sequence_counter: int, chunks_sent: int) -> None:
        await sender_periodic.send_checkpoint_frame(
            connections=self.connections,
            flow_state=self.flow_state,
            metrics=self.metrics,
            llm_queue_size=self.llm_queue.qsize(),
            tts_queue_size=self.tts_queue.qsize(),
            client_queue_size=self.client_queue.qsize(),
            sequence_counter=sequence_counter,
            chunks_sent=chunks_sent,
        )

    async def _log_performance_metrics(self, chunks_sent: int, sequence_counter: int) -> None:
        await sender_periodic.log_performance_metrics(
            logger=self.logger,
            metrics=self.metrics,
            connections=self.connections,
            flow_state=self.flow_state,
            pipeline_id=self.pipeline_id,
            llm_queue=self.llm_queue,
            tts_queue=self.tts_queue,
            client_queue=self.client_queue,
            sequence_counter=sequence_counter,
            chunks_sent=chunks_sent,
        )

    async def _handle_periodic_tasks(
        self,
        last_checkpoint: float,
        last_performance: float,
        checkpoint_interval: float,
        performance_interval: float,
        sequence_counter: int,
        chunks_sent: int,
    ) -> None:
        await sender_periodic.handle_periodic_tasks(
            last_checkpoint=last_checkpoint,
            last_performance=last_performance,
            checkpoint_interval=checkpoint_interval,
            performance_interval=performance_interval,
            on_checkpoint=lambda: self._send_checkpoint_frame(sequence_counter, chunks_sent),
            on_performance=lambda: self._log_performance_metrics(chunks_sent, sequence_counter),
        )

    async def _handle_clean_disconnection(self, sequence_counter: int, chunks_sent: int) -> None:
        await sender_periodic.handle_clean_disconnection(
            logger=self.logger,
            connections=self.connections,
            metrics=self.metrics,
            sequence_counter=sequence_counter,
            chunks_sent=chunks_sent,
        )

    # ------------------------------------------------------------------
    # Task cleanup & queue clearing
    # ------------------------------------------------------------------

    async def _cleanup_tasks(self) -> None:
        """Clean up all pipeline tasks"""
        if not self.pipeline_tasks:
            return
        for task in self.pipeline_tasks:
            if not task.done():
                task.cancel()
        try:
            await asyncio.wait_for(
                asyncio.gather(*self.pipeline_tasks, return_exceptions=True),
                timeout=5.0
            )
        except asyncio.TimeoutError:
            self.logger.warning("Task cleanup timeout - some tasks may not have stopped cleanly")
        self.pipeline_tasks.clear()

    async def _clear_queues(self) -> None:
        """Clear all pipeline queues"""
        queues = [self.llm_queue, self.tts_queue, self.client_queue]
        for queue in queues:
            while not queue.empty():
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    break


# ======================================================================
# Utility functions for pipeline management
# ======================================================================

async def create_pipeline(config: Optional[FlowControlConfig] = None, llm_manager: Optional[LLMManager] = None) -> EnhancedAsyncPipeline:
    """Factory function to create and start a new pipeline."""
    if llm_manager is None:
        from app.services.llm_manager import llm_manager as default_llm_manager
        llm_manager = default_llm_manager

    pipeline = EnhancedAsyncPipeline(config, llm_manager)
    await pipeline.start()
    return pipeline


def get_default_config() -> FlowControlConfig:
    """Get default flow control configuration"""
    return FlowControlConfig()


def get_production_config() -> FlowControlConfig:
    """Get production-optimized flow control configuration"""
    return FlowControlConfig(
        max_llm_queue_size=10,
        max_tts_queue_size=20,
        max_client_queue_size=30,
        stale_chunk_threshold_ms=1500,
        backpressure_timeout_ms=3000,
        recovery_delay_ms=50,
        max_memory_bytes=100 * 1024 * 1024,
        jitter_buffer_min_ms=150,
        jitter_buffer_max_ms=400,
        jitter_buffer_target_ms=250
    )
