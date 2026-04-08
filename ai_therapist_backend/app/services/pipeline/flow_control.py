"""
Flow control: FlowControlState enum, FlowControlConfig dataclass,
and the flow-control/memory/stale-chunk monitor logic extracted from EnhancedAsyncPipeline.
"""

import asyncio
import time
import logging
from typing import Dict, List, Optional
from dataclasses import dataclass, field
from enum import Enum

from .metrics import PipelineMetrics


class FlowControlState(Enum):
    """Flow control states for backpressure management"""
    FLOWING = "flowing"
    THROTTLED = "throttled"
    PAUSED = "paused"
    RECOVERING = "recovering"
    INTERRUPTING = "interrupting"  # New state for interrupt handling
    DRAINING = "draining"          # New state for pipeline drainage


@dataclass
class FlowControlConfig:
    """Configuration for flow control and backpressure"""
    # Queue size limits
    max_llm_queue_size: int = 5
    max_tts_queue_size: int = 10
    max_client_queue_size: int = 15

    # Timing thresholds
    stale_chunk_threshold_ms: int = 2000  # 2s for stale detection
    backpressure_timeout_ms: int = 5000   # 5s max backpressure
    recovery_delay_ms: int = 100          # 100ms recovery delay

    # Memory limits
    max_memory_bytes: int = 50 * 1024 * 1024  # 50MB max pipeline memory

    # Jitter buffer guidance for mobile clients
    jitter_buffer_min_ms: int = 100      # Minimum buffer for smooth playback
    jitter_buffer_max_ms: int = 500      # Maximum buffer to avoid latency
    jitter_buffer_target_ms: int = 200   # Target buffer size

    # Multi-format TTS support
    supported_formats: List[str] = field(default_factory=lambda: ["wav", "opus", "aac"])
    default_format: str = "wav"          # Lowest latency format
    fallback_format: str = "opus"        # High compression for poor networks
    high_quality_format: str = "aac"     # High quality for good networks

    # Network quality thresholds for format negotiation
    poor_network_threshold_ms: int = 800   # >800ms latency = poor network
    good_network_threshold_ms: int = 200   # <200ms latency = good network


class FlowControlMonitor:
    """
    Encapsulates the flow-control monitor, memory monitor, and stale-chunk cleaner
    tasks that were previously inline methods of EnhancedAsyncPipeline.

    The pipeline injects its queues, metrics, config, and shutdown_event so this
    class can operate without back-references to the pipeline object.
    """

    def __init__(
        self,
        config: FlowControlConfig,
        metrics: PipelineMetrics,
        llm_queue: asyncio.Queue,
        tts_queue: asyncio.Queue,
        client_queue: asyncio.Queue,
        shutdown_event: asyncio.Event,
        flow_control_lock: asyncio.Lock,
    ):
        self.config = config
        self.metrics = metrics
        self.llm_queue = llm_queue
        self.tts_queue = tts_queue
        self.client_queue = client_queue
        self.shutdown_event = shutdown_event
        self.flow_control_lock = flow_control_lock
        self.logger = logging.getLogger(__name__)

        # Mutable state managed by this monitor
        self.flow_state = FlowControlState.FLOWING
        self.backpressure_start_time: Optional[float] = None
        self.stale_chunk_timestamps: Dict[str, float] = {}

    # ------------------------------------------------------------------
    # Flow-control monitor task
    # ------------------------------------------------------------------

    async def run_flow_control_monitor(self) -> None:
        """Monitor and manage flow control state"""
        self.logger.info("Flow control monitor started")

        while not self.shutdown_event.is_set():
            try:
                async with self.flow_control_lock:
                    await self._check_flow_control()

                # Check every 100ms for responsive flow control
                await asyncio.sleep(0.1)

            except Exception as e:
                self.logger.error(f"Flow control monitor error: {e}")
                await asyncio.sleep(1.0)

        self.logger.info("Flow control monitor stopped")

    async def _check_flow_control(self) -> None:
        """Check and update flow control state based on queue sizes and timing"""
        current_time = time.time()

        # Check queue pressures
        llm_pressure = self.llm_queue.qsize() / self.config.max_llm_queue_size
        tts_pressure = self.tts_queue.qsize() / self.config.max_tts_queue_size
        client_pressure = self.client_queue.qsize() / self.config.max_client_queue_size

        max_pressure = max(llm_pressure, tts_pressure, client_pressure)

        # State transition logic
        if self.flow_state == FlowControlState.FLOWING:
            if max_pressure > 0.9:  # 90% queue full triggers throttling
                self.flow_state = FlowControlState.THROTTLED
                self.logger.info(f"Flow control throttled (pressure: {max_pressure:.2f})")
            elif max_pressure > 0.98:  # 98% queue full triggers pause
                self.flow_state = FlowControlState.PAUSED
                self.backpressure_start_time = current_time
                self.metrics.flow_control_pauses += 1
                self.logger.warning(f"Flow control paused (pressure: {max_pressure:.2f})")

        elif self.flow_state == FlowControlState.THROTTLED:
            if max_pressure < 0.6:
                self.flow_state = FlowControlState.FLOWING
                self.logger.info("Flow control resumed (throttling cleared)")
            elif max_pressure > 0.95:
                self.flow_state = FlowControlState.PAUSED
                self.backpressure_start_time = current_time
                self.metrics.flow_control_pauses += 1
                self.logger.warning("Flow control paused (from throttled)")

        elif self.flow_state == FlowControlState.PAUSED:
            if max_pressure < 0.4:
                self.flow_state = FlowControlState.RECOVERING
                self.logger.info("Flow control recovering")
            elif (self.backpressure_start_time and
                  (current_time - self.backpressure_start_time) >
                  (self.config.backpressure_timeout_ms / 1000)):
                self.flow_state = FlowControlState.RECOVERING
                self.logger.warning("Flow control timeout - forcing recovery")

        elif self.flow_state == FlowControlState.RECOVERING:
            if (self.backpressure_start_time and
                (current_time - self.backpressure_start_time) >
                (self.config.recovery_delay_ms / 1000)):
                self.flow_state = FlowControlState.FLOWING
                self.backpressure_start_time = None
                self.logger.info("Flow control fully recovered")

    # ------------------------------------------------------------------
    # Memory monitor task
    # ------------------------------------------------------------------

    async def run_memory_monitor(self) -> None:
        """Monitor memory usage and enforce limits"""
        self.logger.info("Memory monitor started")

        while not self.shutdown_event.is_set():
            try:
                memory_usage = (
                    self.llm_queue.qsize() * 1024 +   # ~1KB per LLM message
                    self.tts_queue.qsize() * 512 +     # ~512B per text chunk
                    self.client_queue.qsize() * 8192    # ~8KB per audio chunk
                )

                self.metrics.memory_usage_bytes = memory_usage
                self.metrics.peak_memory_bytes = max(
                    self.metrics.peak_memory_bytes,
                    memory_usage
                )

                if memory_usage > self.config.max_memory_bytes:
                    self.logger.warning(f"Memory limit exceeded: {memory_usage} bytes")
                    await self._emergency_memory_cleanup()

                await asyncio.sleep(5.0)

            except Exception as e:
                self.logger.error(f"Memory monitor error: {e}")
                await asyncio.sleep(5.0)

        self.logger.info("Memory monitor stopped")

    async def _emergency_memory_cleanup(self) -> None:
        """Emergency cleanup when memory limits are exceeded"""
        self.logger.warning("Performing emergency memory cleanup")

        cleanup_count = 0

        # Clear 25% of LLM queue
        llm_clear_count = max(1, self.llm_queue.qsize() // 4)
        for _ in range(llm_clear_count):
            try:
                self.llm_queue.get_nowait()
                cleanup_count += 1
            except asyncio.QueueEmpty:
                break

        # Clear 25% of TTS queue
        tts_clear_count = max(1, self.tts_queue.qsize() // 4)
        for _ in range(tts_clear_count):
            try:
                self.tts_queue.get_nowait()
                cleanup_count += 1
            except asyncio.QueueEmpty:
                break

        # Clear 25% of client queue
        client_clear_count = max(1, self.client_queue.qsize() // 4)
        for _ in range(client_clear_count):
            try:
                self.client_queue.get_nowait()
                cleanup_count += 1
            except asyncio.QueueEmpty:
                break

        self.logger.warning(f"Emergency cleanup removed {cleanup_count} items")

    # ------------------------------------------------------------------
    # Stale chunk cleaner task
    # ------------------------------------------------------------------

    async def run_stale_chunk_cleaner(self) -> None:
        """Clean up stale chunks that exceed timing thresholds"""
        self.logger.info("Stale chunk cleaner started")

        while not self.shutdown_event.is_set():
            try:
                current_time = time.time()
                stale_threshold = self.config.stale_chunk_threshold_ms / 1000

                stale_count = 0
                for chunk_id, timestamp in list(self.stale_chunk_timestamps.items()):
                    if (current_time - timestamp) > stale_threshold:
                        del self.stale_chunk_timestamps[chunk_id]
                        stale_count += 1

                if stale_count > 0:
                    self.metrics.stale_chunks_dropped += stale_count
                    self.logger.info(f"Dropped {stale_count} stale chunks")

                await asyncio.sleep(2.0)

            except Exception as e:
                self.logger.error(f"Stale chunk cleaner error: {e}")
                await asyncio.sleep(2.0)

        self.logger.info("Stale chunk cleaner stopped")
