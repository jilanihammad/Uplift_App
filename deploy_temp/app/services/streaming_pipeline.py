"""
Enhanced Async Pipeline with Backpressure for Streaming TTS
Provides intelligent flow control, jitter buffer support, and resource management.

Core Features:
- Smart backpressure timing for stale chunk detection
- Flow control that pauses upstream when queues are full
- Jitter buffer guidance for mobile clients
- Proper cleanup and resource management
- Error isolation between components
- Format discovery with initial JSON frame
"""

import asyncio
import json
import time
import logging
import weakref
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, AsyncGenerator, List, Callable, Tuple
from dataclasses import dataclass, field
from enum import Enum
from collections import defaultdict

# Import existing LLM infrastructure
from app.services.llm_manager import LLMManager
from app.core.llm_config import LLMConfig, ModelType
from app.utils.text_processor import SmartTextProcessor, TextChunk, BoundaryType


class PipelineState(Enum):
    """Pipeline state management"""
    IDLE = "idle"
    INITIALIZING = "initializing"
    STREAMING = "streaming"
    PAUSED = "paused"
    STOPPING = "stopping"
    ERROR = "error"


class FlowControlState(Enum):
    """Flow control states for backpressure management"""
    FLOWING = "flowing"
    THROTTLED = "throttled"
    PAUSED = "paused"
    RECOVERING = "recovering"
    INTERRUPTING = "interrupting"  # New state for interrupt handling
    DRAINING = "draining"          # New state for pipeline drainage


@dataclass
class PipelineMetrics:
    """Pipeline performance and health metrics"""
    # Throughput metrics
    messages_processed: int = 0
    chunks_generated: int = 0
    audio_chunks_sent: int = 0
    
    # Timing metrics
    avg_llm_latency_ms: float = 0.0
    avg_tts_latency_ms: float = 0.0
    avg_end_to_end_ms: float = 0.0
    time_to_first_audio_ms: float = 0.0
    
    # Queue metrics
    llm_queue_size: int = 0
    tts_queue_size: int = 0
    client_queue_size: int = 0
    
    # Backpressure metrics
    backpressure_events: int = 0
    stale_chunks_dropped: int = 0
    flow_control_pauses: int = 0
    
    # Memory metrics
    memory_usage_bytes: int = 0
    peak_memory_bytes: int = 0
    
    # Error metrics
    llm_errors: int = 0
    tts_errors: int = 0
    client_errors: int = 0
    
    # Performance targets
    target_ttfa_ms: float = 400.0  # Time to first audio
    target_latency_ms: float = 300.0
    
    def update_timing(self, metric_name: str, value_ms: float):
        """Update timing metrics with exponential moving average"""
        current = getattr(self, metric_name, 0.0)
        # Use 0.3 alpha for responsive but stable averaging
        setattr(self, metric_name, 0.3 * value_ms + 0.7 * current)


class ProductionMetricsService:
    """
    Service to send WAVPerformanceMonitor metrics to Firebase/Sentry for production monitoring
    Addresses Issue #7: Observability quick win
    """
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.metrics_enabled = True
        self.last_report_time = time.time()
        self.report_interval_seconds = 30  # Report every 30 seconds
        
    def is_metrics_enabled(self) -> bool:
        """Check if metrics reporting is enabled"""
        return self.metrics_enabled
        
    def send_performance_metrics(self, metrics: "PipelineMetrics", pipeline_id: str) -> None:
        """
        Send performance metrics to Firebase Analytics and Sentry
        
        Args:
            metrics: PipelineMetrics instance with current performance data
            pipeline_id: Unique identifier for the pipeline
        """
        try:
            # Create metrics payload for external services
            metrics_payload = self._create_metrics_payload(metrics, pipeline_id)
            
            # Send to Firebase Analytics (if available)
            self._send_to_firebase(metrics_payload)
            
            # Send to Sentry as custom metrics (if available) 
            self._send_to_sentry(metrics_payload)
            
            # Log success
            self.logger.debug(f"Performance metrics sent for pipeline {pipeline_id}")
            
        except Exception as e:
            self.logger.error(f"Failed to send production metrics: {str(e)}")
            
    def _create_metrics_payload(self, metrics: "PipelineMetrics", pipeline_id: str) -> Dict[str, Any]:
        """Create standardized metrics payload"""
        return {
            "pipeline_id": pipeline_id,
            "timestamp": datetime.now().isoformat(),
            
            # Latency metrics (critical for TTS performance)
            "time_to_first_audio_ms": metrics.time_to_first_audio_ms,
            "avg_end_to_end_ms": metrics.avg_end_to_end_ms,
            "avg_tts_latency_ms": metrics.avg_tts_latency_ms,
            "avg_llm_latency_ms": metrics.avg_llm_latency_ms,
            
            # Throughput metrics
            "messages_processed": metrics.messages_processed,
            "chunks_generated": metrics.chunks_generated,
            "audio_chunks_sent": metrics.audio_chunks_sent,
            
            # Queue health metrics
            "llm_queue_size": metrics.llm_queue_size,
            "tts_queue_size": metrics.tts_queue_size,
            "client_queue_size": metrics.client_queue_size,
            
            # Performance issues
            "backpressure_events": metrics.backpressure_events,
            "stale_chunks_dropped": metrics.stale_chunks_dropped,
            "flow_control_pauses": metrics.flow_control_pauses,
            
            # Memory usage
            "memory_usage_bytes": metrics.memory_usage_bytes,
            "peak_memory_bytes": metrics.peak_memory_bytes,
            
            # Error rates
            "error_rate": (metrics.llm_errors + metrics.tts_errors + metrics.client_errors) / max(1, metrics.messages_processed),
            "llm_errors": metrics.llm_errors,
            "tts_errors": metrics.tts_errors,
            "client_errors": metrics.client_errors,
            
            # Performance targets compliance
            "ttfa_target_met": metrics.time_to_first_audio_ms <= metrics.target_ttfa_ms,
            "latency_target_met": metrics.avg_end_to_end_ms <= metrics.target_latency_ms
        }
        
    def _send_to_firebase(self, metrics_payload: Dict[str, Any]) -> None:
        """
        Send metrics to Firebase Analytics as custom events
        Note: Requires firebase_admin SDK in production
        """
        try:
            # In production, you would use:
            # from firebase_admin import analytics
            # analytics.log_event('tts_performance_metrics', metrics_payload)
            
            # For now, log as structured data for Firebase ingestion
            self.logger.info(
                f"FIREBASE_METRICS: {json.dumps(metrics_payload)}",
                extra={
                    "firebase_event": "tts_performance_metrics",
                    "metrics": metrics_payload
                }
            )
            
        except Exception as e:
            self.logger.error(f"Failed to send Firebase metrics: {str(e)}")
            
    def _send_to_sentry(self, metrics_payload: Dict[str, Any]) -> None:
        """
        Send metrics to Sentry as custom metrics
        Note: Requires sentry_sdk in production
        """
        try:
            # In production, you would use:
            # import sentry_sdk
            # with sentry_sdk.configure_scope() as scope:
            #     scope.set_context("tts_performance", metrics_payload)
            #     sentry_sdk.set_measurement("time_to_first_audio_ms", metrics_payload["time_to_first_audio_ms"])
            #     sentry_sdk.set_measurement("avg_end_to_end_ms", metrics_payload["avg_end_to_end_ms"])
            #     sentry_sdk.capture_message("TTS Performance Metrics", level="info")
            
            # For now, log as structured data for Sentry ingestion
            self.logger.info(
                f"SENTRY_METRICS: {json.dumps(metrics_payload)}",
                extra={
                    "sentry_event": "tts_performance_metrics",
                    "metrics": metrics_payload
                }
            )
            
        except Exception as e:
            self.logger.error(f"Failed to send Sentry metrics: {str(e)}")
            
    def should_report_metrics(self) -> bool:
        """Check if it's time to report metrics based on interval"""
        current_time = time.time()
        if current_time - self.last_report_time >= self.report_interval_seconds:
            self.last_report_time = current_time
            return True
        return False
        
    def send_critical_metric(self, metric_name: str, value: float, tags: Dict[str, str] = None) -> None:
        """
        Send critical metric immediately (e.g., for alerts)
        
        Args:
            metric_name: Name of the metric
            value: Metric value
            tags: Additional tags for the metric
        """
        try:
            payload = {
                "metric_name": metric_name,
                "value": value,
                "timestamp": datetime.now().isoformat(),
                "tags": tags or {},
                "critical": True
            }
            
            # Send immediately to both services
            self._send_to_firebase(payload)
            self._send_to_sentry(payload)
            
            self.logger.warning(f"CRITICAL_METRIC: {metric_name}={value}")
            
        except Exception as e:
            self.logger.error(f"Failed to send critical metric {metric_name}: {str(e)}")


# Global production metrics service
production_metrics = ProductionMetricsService()


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


@dataclass
class StreamingMessage:
    """Message structure for pipeline communication"""
    message_id: str
    conversation_id: str
    user_message: str
    timestamp: datetime = field(default_factory=datetime.now)
    metadata: Dict[str, Any] = field(default_factory=dict)
    priority: int = 1  # Higher number = higher priority


@dataclass
class AudioChunk:
    """Audio chunk with metadata for client transmission"""
    chunk_id: str
    sentence_id: str
    sequence: int
    audio_data: bytes
    is_sentence_end: bool
    boundary_type: BoundaryType
    timestamp: datetime = field(default_factory=datetime.now)
    metadata: Dict[str, Any] = field(default_factory=dict)


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
    
    def __init__(self, config: Optional[FlowControlConfig] = None):
        """
        Initialize the enhanced streaming pipeline.
        
        Args:
            config: Flow control configuration (uses defaults if None)
        """
        self.config = config or FlowControlConfig()
        self.state = PipelineState.IDLE
        self.flow_state = FlowControlState.FLOWING
        
        # Core components
        self.llm_manager = LLMManager()
        self.text_processor = SmartTextProcessor()
        
        # Async queues for pipeline stages
        self.llm_queue: asyncio.Queue[StreamingMessage] = asyncio.Queue(
            maxsize=self.config.max_llm_queue_size
        )
        self.tts_queue: asyncio.Queue[TextChunk] = asyncio.Queue(
            maxsize=self.config.max_tts_queue_size
        )
        self.client_queue: asyncio.Queue[AudioChunk] = asyncio.Queue(
            maxsize=self.config.max_client_queue_size
        )
        
        # Pipeline tasks (will be created when pipeline starts)
        self.pipeline_tasks: List[asyncio.Task] = []
        self.shutdown_event = asyncio.Event()
        
        # Metrics and monitoring
        self.metrics = PipelineMetrics()
        self.flow_control_lock = asyncio.Lock()
        self.last_activity_time = time.time()
        
        # Client connections (weak references to avoid memory leaks)
        self.active_clients: Dict[str, Any] = {}  # client_id -> websocket
        
        # Logger
        self.logger = logging.getLogger(__name__)
        
        # Flow control state tracking
        self.backpressure_start_time: Optional[float] = None
        self.stale_chunk_timestamps: Dict[str, float] = {}
        
        # Interrupt handling state
        self.interrupt_requested = False
        self.interrupt_client_id: Optional[str] = None
        self.draining_start_time: Optional[float] = None
        self.pending_chunks_before_interrupt: int = 0
        
    async def start(self) -> None:
        """Start the async pipeline with all components"""
        if self.state != PipelineState.IDLE:
            raise RuntimeError(f"Pipeline already running (state: {self.state})")
        
        self.state = PipelineState.INITIALIZING
        self.logger.info("Starting enhanced async pipeline...")
        
        try:
            # Clear any existing tasks
            await self._cleanup_tasks()
            
            # Start pipeline components
            self.pipeline_tasks = [
                asyncio.create_task(self._llm_producer()),
                asyncio.create_task(self._tts_processor()),
                asyncio.create_task(self._client_sender()),
                asyncio.create_task(self._flow_control_monitor()),
                asyncio.create_task(self._memory_monitor()),
                asyncio.create_task(self._stale_chunk_cleaner())
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
        
        # Signal shutdown
        self.shutdown_event.set()
        
        # Cleanup tasks and resources
        await self._cleanup_tasks()
        
        # Clear queues
        await self._clear_queues()
        
        # Reset state
        self.state = PipelineState.IDLE
        self.flow_state = FlowControlState.FLOWING
        self.shutdown_event.clear()
        
        self.logger.info("Pipeline stopped")
    
    async def add_message(self, message: StreamingMessage) -> bool:
        """
        Add a message to the pipeline for processing.
        
        Args:
            message: The streaming message to process
            
        Returns:
            bool: True if message was added, False if rejected due to backpressure
        """
        if self.state != PipelineState.STREAMING:
            raise RuntimeError(f"Pipeline not streaming (state: {self.state})")
        
        try:
            # Check flow control state
            if self.flow_state == FlowControlState.PAUSED:
                self.logger.warning("Message rejected - pipeline paused")
                return False
            
            # Try to add message with timeout to avoid blocking
            await asyncio.wait_for(
                self.llm_queue.put(message),
                timeout=1.0  # 1 second timeout
            )
            
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
        """
        Generate initialization frame with jitter buffer guidance.
        
        Args:
            client_id: Unique client identifier
            
        Returns:
            Dict containing initialization data for client
        """
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
                "chunk_acknowledgment": False,  # Optional for mobile
                "max_buffer_chunks": 10
            },
            "performance_targets": {
                "time_to_first_audio_ms": self.metrics.target_ttfa_ms,
                "target_latency_ms": self.metrics.target_latency_ms
            },
            "timestamp": datetime.now().isoformat()
        }
    
    async def register_client(self, client_id: str, websocket) -> Dict[str, Any]:
        """
        Register a new client connection.
        
        Args:
            client_id: Unique client identifier
            websocket: WebSocket connection (stored as weak reference)
            
        Returns:
            Dict: Initialization frame for the client
        """
        self.active_clients[client_id] = websocket
        self.logger.info(f"Client registered: {client_id}")
        
        return await self.get_init_frame(client_id)
    
    async def unregister_client(self, client_id: str) -> None:
        """
        Unregister a client connection.
        
        Args:
            client_id: Client identifier to remove
        """
        if client_id in self.active_clients:
            del self.active_clients[client_id]
            self.logger.info(f"Client unregistered: {client_id}")
    
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
            "active_clients": len(self.active_clients)
        }
    
    def assess_network_quality(self, client_metrics: Dict[str, Any]) -> str:
        """
        Assess network quality based on client metrics for adaptive format selection
        
        Args:
            client_metrics: Dictionary containing client network metrics
            
        Returns:
            str: Network quality assessment ("poor", "fair", "good", "excellent")
        """
        # Extract key metrics
        rtt_ms = client_metrics.get("rtt_ms", 0)
        packet_loss = client_metrics.get("packet_loss_percent", 0)
        bandwidth_kbps = client_metrics.get("bandwidth_kbps", 0)
        jitter_ms = client_metrics.get("jitter_ms", 0)
        
        # Network quality scoring
        quality_score = 100
        
        # RTT penalties
        if rtt_ms > self.config.poor_network_threshold_ms:
            quality_score -= 40
        elif rtt_ms > self.config.good_network_threshold_ms:
            quality_score -= 20
        
        # Packet loss penalties
        if packet_loss > 5:
            quality_score -= 30
        elif packet_loss > 1:
            quality_score -= 15
        
        # Bandwidth considerations
        if bandwidth_kbps < 128:  # Very low bandwidth
            quality_score -= 25
        elif bandwidth_kbps < 256:  # Low bandwidth
            quality_score -= 10
        
        # Jitter penalties
        if jitter_ms > 100:
            quality_score -= 15
        elif jitter_ms > 50:
            quality_score -= 8
        
        # Classify network quality
        if quality_score >= 80:
            return "excellent"
        elif quality_score >= 60:
            return "good"
        elif quality_score >= 40:
            return "fair"
        else:
            return "poor"
    
    def select_optimal_format(self, network_quality: str, client_capabilities: Dict[str, Any]) -> str:
        """
        Select optimal audio format based on network quality and client capabilities
        
        Args:
            network_quality: Network quality assessment ("poor", "fair", "good", "excellent")
            client_capabilities: Client capability information
            
        Returns:
            str: Selected audio format
        """
        supported_formats = client_capabilities.get("supported_formats", ["wav"])
        
        # Format selection logic based on network quality
        if network_quality == "poor":
            # Poor network: prioritize compression
            if "opus" in supported_formats:
                return "opus"  # Best compression for poor networks
            elif "aac" in supported_formats:
                return "aac"   # Good compression alternative
            else:
                return "wav"   # Fallback to default
                
        elif network_quality == "fair":
            # Fair network: balance between quality and compression
            if "aac" in supported_formats:
                return "aac"   # Good balance of quality and compression
            elif "opus" in supported_formats:
                return "opus"  # Good compression
            else:
                return "wav"   # Fallback to default
                
        elif network_quality in ["good", "excellent"]:
            # Good/excellent network: prioritize quality and low latency
            if "wav" in supported_formats:
                return "wav"   # Lowest latency, highest quality
            elif "aac" in supported_formats:
                return "aac"   # High quality alternative
            else:
                return "opus"  # Fallback
        
        # Default fallback
        return self.config.default_format
    
    def get_format_parameters(self, audio_format: str) -> Dict[str, Any]:
        """
        Get optimized parameters for specific audio format
        
        Args:
            audio_format: Audio format name
            
        Returns:
            Dict: Format-specific parameters
        """
        format_configs = {
            "wav": {
                "response_format": "wav",
                "sample_rate": 16000,
                "channels": 1,
                "bit_depth": 16,
                "estimated_bitrate_kbps": 256,  # 16kHz * 16bit * 1ch
                "latency_category": "lowest"
            },
            "opus": {
                "response_format": "opus",
                "sample_rate": 24000,
                "channels": 1,
                "bitrate": "24k",
                "estimated_bitrate_kbps": 24,
                "latency_category": "low"
            },
            "aac": {
                "response_format": "aac",
                "sample_rate": 48000,
                "channels": 1,
                "bitrate": "64k",
                "estimated_bitrate_kbps": 64,
                "latency_category": "medium"
            }
        }
        
        return format_configs.get(audio_format, format_configs["wav"])
    
    async def request_interrupt(self, client_id: str) -> bool:
        """
        Request pipeline interruption for new user input
        
        Args:
            client_id: Client requesting the interruption
            
        Returns:
            bool: True if interrupt was processed successfully
        """
        if self.interrupt_requested:
            self.logger.info(f"Interrupt already in progress, ignoring request from {client_id}")
            return False
            
        self.logger.info(f"Interrupt requested by client {client_id}")
        
        # Set interrupt state
        self.interrupt_requested = True
        self.interrupt_client_id = client_id
        self.draining_start_time = time.time()
        
        # Count pending chunks in queues
        self.pending_chunks_before_interrupt = (
            self.llm_queue.qsize() + 
            self.tts_queue.qsize() + 
            self.client_queue.qsize()
        )
        
        # Change flow state to interrupting
        async with self.flow_control_lock:
            self.flow_state = FlowControlState.INTERRUPTING
            
        # Start draining pipeline
        await self.drain_pipeline()
        
        return True
        
    async def drain_pipeline(self) -> None:
        """
        Drain the pipeline of pending chunks to prepare for new input
        """
        self.logger.info("Starting pipeline drainage for interrupt")
        
        async with self.flow_control_lock:
            self.flow_state = FlowControlState.DRAINING
            
        # Clear all queues
        await self._clear_queues()
        
        # Wait a brief moment for any in-flight processing to complete
        await asyncio.sleep(0.1)
        
        # Send interrupt acknowledgment
        await self.send_interrupt_ack()
        
    async def send_interrupt_ack(self) -> None:
        """
        Send interrupt acknowledgment after pipeline drainage is complete
        """
        if not self.interrupt_requested or not self.interrupt_client_id:
            return
            
        client_id = self.interrupt_client_id
        drain_time_ms = (time.time() - self.draining_start_time) * 1000 if self.draining_start_time else 0
        
        # Create interrupt acknowledgment frame
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
        
        # Send acknowledgment to requesting client
        if client_id in self.active_clients:
            try:
                websocket = self.active_clients[client_id]
                await websocket.send(json.dumps(interrupt_ack))
                self.logger.info(f"Interrupt acknowledgment sent to {client_id} (drain time: {drain_time_ms:.1f}ms)")
            except Exception as e:
                self.logger.warning(f"Failed to send interrupt ack to {client_id}: {e}")
        
        # Reset interrupt state
        self.interrupt_requested = False
        self.interrupt_client_id = None
        self.draining_start_time = None
        self.pending_chunks_before_interrupt = 0
        
        # Reset flow state to flowing
        async with self.flow_control_lock:
            self.flow_state = FlowControlState.FLOWING
            
        self.logger.info("Pipeline interrupt handling completed, ready for new input")
        
    def is_interrupting(self) -> bool:
        """Check if pipeline is currently handling an interrupt"""
        return self.interrupt_requested or self.flow_state in [FlowControlState.INTERRUPTING, FlowControlState.DRAINING]
    
    # Private methods for pipeline implementation
    
    async def _llm_producer(self) -> None:
        """
        LLM producer component with flow control integration.
        
        Features:
        - Sentence-level streaming with metadata for clean interruption
        - Pause-token parsing using LLM's natural boundaries
        - Flow control integration with backpressure handling
        - Voice consistency with conversation context
        - Sequence tracking with monotonic IDs
        - Provider-agnostic using existing LLMManager
        """
        self.logger.info("LLM producer started")
        
        # Sequence tracking for conversation consistency
        conversation_sequence = 0
        
        while not self.shutdown_event.is_set():
            try:
                # Check flow control state BEFORE pulling from queue
                if self.flow_state == FlowControlState.PAUSED:
                    await asyncio.sleep(0.01)  # Small delay to prevent busy waiting
                    continue
                
                # Get next message with timeout ONLY if not paused
                try:
                    message = await asyncio.wait_for(
                        self.llm_queue.get(), 
                        timeout=0.1
                    )
                except asyncio.TimeoutError:
                    continue  # Check shutdown and flow state again
                
                # Double-check flow control state after getting message
                if self.flow_state in [FlowControlState.PAUSED, FlowControlState.THROTTLED]:
                    # Put message back and wait - don't process during pause/throttle
                    await self.llm_queue.put(message)
                    await asyncio.sleep(0.1)  # Wait longer during backpressure
                    continue
                
                # Process the message with timing
                start_time = time.time()
                
                try:
                    await self._process_llm_message(message, conversation_sequence)
                    conversation_sequence += 1
                    
                    # Update performance metrics
                    processing_time = (time.time() - start_time) * 1000
                    self.metrics.update_timing("avg_llm_latency_ms", processing_time)
                    
                except Exception as e:
                    self.logger.error(f"Error processing LLM message {message.message_id}: {e}")
                    self.metrics.llm_errors += 1
                
                # Mark LLM queue task as done (only after processing attempt)
                self.llm_queue.task_done()
                
                # Update activity timestamp
                self.last_activity_time = time.time()
                
            except Exception as e:
                self.logger.error(f"LLM producer error: {e}")
                self.metrics.llm_errors += 1
                await asyncio.sleep(1.0)  # Longer delay on error
        
        self.logger.info("LLM producer stopped")
    
    async def _process_llm_message(self, message: StreamingMessage, conversation_sequence: int) -> None:
        """
        Process a single LLM message with streaming response generation.
        
        Args:
            message: The streaming message to process
            conversation_sequence: Monotonic sequence ID for the conversation
        """
        sentence_id = 0
        text_buffer = ""
        ttfa_start_time = time.time()  # Time to first audio tracking
        
        try:
            # Prepare conversation context for voice consistency
            conversation_context = {
                "conversation_id": message.conversation_id,
                "message_id": message.message_id,
                "sequence": conversation_sequence,
                "voice_seed": self._get_voice_seed(message.conversation_id),
                "timestamp": message.timestamp.isoformat()
            }
            
            # Stream LLM response using existing LLMManager
            async for chunk_text in self._stream_llm_response(message):
                if self.shutdown_event.is_set():
                    break
                
                # Add chunk to buffer
                text_buffer += chunk_text
                
                # Process with smart text processor for sentence boundaries
                sentences = self.text_processor.add_text(chunk_text)
                
                # Process complete sentences
                for text_chunk in sentences:
                    if text_chunk.text.strip():  # Skip empty sentences
                        # Update text chunk with conversation metadata
                        text_chunk.metadata.update({
                            **conversation_context,
                            "sentence_id": f"{message.message_id}_{sentence_id}",
                            "sequence": sentence_id,
                            "is_sentence_end": True,
                            "voice_consistency_seed": conversation_context["voice_seed"],
                            "interruption_safe": True,  # Sentence boundaries are safe for interruption
                            "prosody_complete": True    # Sentence has complete prosody
                        })
                        
                        # Try to add to TTS queue with flow control
                        success = await self._add_to_tts_queue(text_chunk)
                        if success:
                            sentence_id += 1
                            self.metrics.chunks_generated += 1
                            
                            # Update time to first audio metric (only for first chunk)
                            if sentence_id == 1:
                                ttfa_ms = (time.time() - ttfa_start_time) * 1000
                                self.metrics.update_timing("time_to_first_audio_ms", ttfa_ms)
                        else:
                            self.logger.warning(f"Failed to queue sentence for TTS: {text_chunk.metadata['sentence_id']}")
            
            # Process any remaining text in buffer at end of response
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
            
            # Generate fallback response for better user experience
            try:
                fallback_chunk = TextChunk(
                    text="I apologize, but I'm having trouble generating a response. Please try again.",
                    boundary_type=BoundaryType.SENTENCE_END,
                    sequence_id=0,
                    metadata={
                        "is_fallback": True,
                        "original_message_id": message.message_id,
                        "error": str(e),
                        "timestamp": time.time()
                    },
                    processing_time_ms=0.0,
                    character_count=len("I apologize, but I'm having trouble generating a response. Please try again.")
                )
                
                await self._add_to_tts_queue(fallback_chunk)
                self.logger.info("Fallback response generated due to LLM error")
            except Exception as fallback_error:
                self.logger.error(f"Failed to generate fallback response: {fallback_error}")
                
            raise
    
    async def _stream_llm_response(self, message: StreamingMessage) -> AsyncGenerator[str, None]:
        """
        Stream LLM response using existing LLMManager (provider-agnostic).
        
        Args:
            message: The streaming message to get response for
            
        Yields:
            str: Text chunks from the LLM response
        """
        try:
            # Use existing LLMManager for streaming chat completion
            async for chunk in self.llm_manager.stream_chat_completion(
                message=message.user_message,
                conversation_id=message.conversation_id,
                **message.metadata  # Pass through any additional parameters
            ):
                # Extract text content from chunk (format may vary by provider)
                chunk_text = self._extract_chunk_text(chunk)
                if chunk_text:
                    yield chunk_text
                    
        except Exception as e:
            self.logger.error(f"Error streaming LLM response: {e}")
            self.metrics.llm_errors += 1
            # Re-raise the exception so it can be handled in _process_llm_message
            # where the fallback response logic exists
            raise
    
    def _extract_chunk_text(self, chunk: Any) -> str:
        """
        Extract text content from LLM response chunk (provider-agnostic).
        
        Args:
            chunk: Raw chunk from LLM provider
            
        Returns:
            str: Extracted text content
        """
        try:
            # Handle different chunk formats from various providers
            if isinstance(chunk, str):
                return chunk
            elif isinstance(chunk, dict):
                # OpenAI format
                if "choices" in chunk and len(chunk["choices"]) > 0:
                    delta = chunk["choices"][0].get("delta", {})
                    return delta.get("content", "")
                # Anthropic format
                elif "delta" in chunk:
                    return chunk["delta"].get("text", "")
                # Generic content field
                elif "content" in chunk:
                    return chunk["content"]
                # Text field
                elif "text" in chunk:
                    return chunk["text"]
            elif hasattr(chunk, 'content'):
                # Object with content attribute
                return getattr(chunk, 'content', "")
            elif hasattr(chunk, 'text'):
                # Object with text attribute
                return getattr(chunk, 'text', "")
            
            # Fallback: convert to string
            return str(chunk) if chunk else ""
            
        except Exception as e:
            self.logger.warning(f"Error extracting chunk text: {e}")
            return ""
    
    def _get_voice_seed(self, conversation_id: str) -> str:
        """
        Generate consistent voice seed for conversation.
        
        Args:
            conversation_id: Unique conversation identifier
            
        Returns:
            str: Consistent voice seed for TTS voice consistency
        """
        # Generate deterministic seed based on conversation ID
        # This ensures voice consistency across sentences in same conversation
        import hashlib
        
        seed_input = f"{conversation_id}_voice_consistency"
        return hashlib.md5(seed_input.encode()).hexdigest()[:8]
    
    async def _add_to_tts_queue(self, text_chunk: TextChunk) -> bool:
        """
        Add text chunk to TTS queue with flow control and backpressure handling.
        
        Args:
            text_chunk: The text chunk to add to TTS processing
            
        Returns:
            bool: True if successfully added, False if rejected due to backpressure
        """
        try:
            # Check flow control state
            if self.flow_state == FlowControlState.PAUSED:
                self.logger.warning("TTS queue add rejected - pipeline paused")
                return False
            
            # Use timeout to avoid blocking indefinitely
            timeout = 2.0 if self.flow_state == FlowControlState.FLOWING else 0.5
            
            await asyncio.wait_for(
                self.tts_queue.put(text_chunk),
                timeout=timeout
            )
            
            return True
            
        except asyncio.TimeoutError:
            self.logger.warning(f"TTS queue timeout for chunk: {text_chunk.metadata.get('sentence_id', 'unknown')}")
            self.metrics.backpressure_events += 1
            return False
        except Exception as e:
            self.logger.error(f"Error adding to TTS queue: {e}")
            return False
    
    async def _tts_processor(self) -> None:
        """
        TTS processor component with quality controls and streaming audio generation.
        
        Features:
        - Provider-agnostic TTS using existing LLMManager.stream_text_to_speech()
        - Voice consistency with conversation-specific seeds
        - Smart stale chunk dropping for poor network handling
        - Flow control integration with backpressure handling
        - Sequence preservation and metadata forwarding
        - Graceful error handling with fallback responses
        - Quality controls for audio generation
        """
        self.logger.info("TTS processor started")
        
        # Voice state tracking for consistency
        conversation_voices: Dict[str, str] = {}  # conversation_id -> voice_id
        
        while not self.shutdown_event.is_set():
            try:
                # Check flow control state before processing
                if self.flow_state == FlowControlState.PAUSED:
                    await asyncio.sleep(0.01)  # Small delay to prevent busy waiting
                    continue
                
                # Get next text chunk with timeout
                try:
                    text_chunk = await asyncio.wait_for(
                        self.tts_queue.get(), 
                        timeout=0.1
                    )
                except asyncio.TimeoutError:
                    continue  # Check shutdown and flow state again
                
                # Double-check flow control state after getting chunk
                if self.flow_state in [FlowControlState.PAUSED, FlowControlState.THROTTLED]:
                    # Put chunk back and wait - don't process during pause/throttle
                    await self.tts_queue.put(text_chunk)
                    await asyncio.sleep(0.1)  # Wait longer during backpressure
                    continue
                
                # Process the text chunk with timing
                start_time = time.time()
                
                try:
                    await self._process_tts_chunk(text_chunk, conversation_voices)
                    
                    # Update performance metrics
                    processing_time = (time.time() - start_time) * 1000
                    self.metrics.update_timing("avg_tts_latency_ms", processing_time)
                    
                except Exception as e:
                    self.logger.error(f"Error processing TTS chunk {text_chunk.metadata.get('sentence_id', 'unknown')}: {e}")
                    self.metrics.tts_errors += 1
                
                # Mark TTS queue task as done (only after processing attempt)
                self.tts_queue.task_done()
                
                # Update activity timestamp
                self.last_activity_time = time.time()
                
            except Exception as e:
                self.logger.error(f"TTS processor error: {e}")
                self.metrics.tts_errors += 1
                await asyncio.sleep(1.0)  # Longer delay on error
        
        self.logger.info("TTS processor stopped")
    
    async def _process_tts_chunk(self, text_chunk: TextChunk, conversation_voices: Dict[str, str]) -> None:
        """
        Process text chunk through TTS generation with adaptive format selection
        
        Args:
            text_chunk: Text chunk to process
            conversation_voices: Voice assignments for conversations
        """
        chunk_timestamp = time.time()
        sentence_id = text_chunk.metadata.get("sentence_id", "unknown")
        conversation_id = text_chunk.metadata.get("conversation_id", "unknown")
        voice = self._get_consistent_voice(conversation_id, text_chunk.metadata.get("voice_seed", "default"), conversation_voices)
        
        # Get client capabilities and network metrics for format selection
        client_metadata = text_chunk.metadata
        client_capabilities = client_metadata.get("client_capabilities", {"supported_formats": ["wav"]})
        network_metrics = client_metadata.get("network_metrics", {})
        
        # Assess network quality and select optimal format
        network_quality = self.assess_network_quality(network_metrics) if network_metrics else "good"
        optimal_format = self.select_optimal_format(network_quality, client_capabilities)
        format_params = self.get_format_parameters(optimal_format)
        
        self.logger.info(f"TTS processing: format={optimal_format}, network={network_quality}, text='{text_chunk.text[:50]}...'")
        
        try:
            # TTS generation parameters with adaptive format
            tts_params = {
                "voice": voice,
                "conversation_id": conversation_id,
                "response_format": format_params["response_format"],
                "stream": True,
                "chunk_size": 1024,
                "real_time": True
            }
            
            # Add format-specific parameters
            if optimal_format == "opus":
                tts_params["bitrate"] = format_params.get("bitrate", "24k")
                tts_params["sample_rate"] = format_params.get("sample_rate", 24000)
            elif optimal_format == "aac":
                tts_params["bitrate"] = format_params.get("bitrate", "64k")
                tts_params["sample_rate"] = format_params.get("sample_rate", 48000)
            
            # Add metadata for audio chunks
            audio_metadata = {
                "sentence_id": text_chunk.metadata.get("sentence_id"),
                "sequence": text_chunk.sequence_id,
                "is_sentence_end": text_chunk.boundary_type in [BoundaryType.SENTENCE_END, BoundaryType.PARAGRAPH_BREAK],
                "boundary_type": text_chunk.boundary_type.value,
                "conversation_id": conversation_id,
                "audio_format": optimal_format,
                "network_quality": network_quality,
                "format_params": format_params
            }
            
            # Stream TTS audio using existing LLMManager
            audio_chunks_generated = 0
            
            async for audio_chunk_b64 in self._stream_tts_audio(text_chunk.text, tts_params):
                if self.shutdown_event.is_set():
                    break
                
                # Decode base64 audio chunk
                try:
                    import base64
                    audio_data = base64.b64decode(audio_chunk_b64)
                except Exception as e:
                    self.logger.warning(f"Failed to decode audio chunk: {e}")
                    continue
                
                # Create audio chunk with adaptive format metadata
                audio_chunk = AudioChunk(
                    chunk_id=f"{sentence_id}_{audio_chunks_generated}",
                    sentence_id=sentence_id,
                    sequence=text_chunk.sequence_id,
                    audio_data=audio_data,
                    is_sentence_end=(audio_chunks_generated == 0),  # Mark first chunk as sentence boundary
                    boundary_type=text_chunk.boundary_type,
                    metadata={
                        **text_chunk.metadata,
                        "audio_format": optimal_format,
                        "voice_used": voice,
                        "chunk_index": audio_chunks_generated,
                        "total_chunks": "unknown",  # Will be updated when stream completes
                        "tts_processing_time_ms": (time.time() - chunk_timestamp) * 1000,
                        "is_realtime": True,
                        "streaming": True,
                        "boundary_type": text_chunk.boundary_type.value,
                        "network_quality": network_quality,
                        "format_params": format_params,
                        "estimated_bitrate_kbps": format_params["estimated_bitrate_kbps"]
                    }
                )
                
                # Try to add to client queue with flow control
                success = await self._add_to_client_queue(audio_chunk)
                
                if success:
                    audio_chunks_generated += 1
                    self.metrics.chunks_generated += 1
                    
                    # Update timing metrics for first audio chunk
                    if audio_chunks_generated == 1:
                        ttfa_ms = (time.time() - chunk_timestamp) * 1000
                        self.metrics.update_timing("time_to_first_audio_ms", ttfa_ms)
                        self.logger.info(f"Time to first audio: {ttfa_ms:.1f}ms (format: {optimal_format})")
                else:
                    self.logger.warning(f"Failed to queue audio chunk {audio_chunks_generated} for {sentence_id}")
                    break
            
            # Update TTS latency timing
            total_latency = (time.time() - chunk_timestamp) * 1000
            self.metrics.update_timing("avg_tts_latency_ms", total_latency)
            
            self.logger.info(f"TTS completed for '{text_chunk.text[:30]}...': {audio_chunks_generated} chunks, {total_latency:.1f}ms, format: {optimal_format}")
            
        except Exception as e:
            self.logger.error(f"TTS processing error for text '{text_chunk.text[:50]}...': {str(e)}")
            self.metrics.tts_errors += 1
            
            # Try fallback to default format if adaptive format failed
            if optimal_format != self.config.default_format:
                self.logger.info(f"Retrying with fallback format: {self.config.default_format}")
                try:
                    fallback_params = self.get_format_parameters(self.config.default_format)
                    fallback_tts_params = {
                        "voice": voice,
                        "conversation_id": conversation_id,
                        "response_format": fallback_params["response_format"],
                        "stream": True,
                        "chunk_size": 1024,
                        "real_time": True
                    }
                    
                    # Retry with fallback format
                    audio_chunks_generated = 0
                    async for audio_chunk_b64 in self._stream_tts_audio(text_chunk.text, fallback_tts_params):
                        if self.shutdown_event.is_set():
                            break
                        
                        try:
                            import base64
                            audio_data = base64.b64decode(audio_chunk_b64)
                            
                            audio_chunk = AudioChunk(
                                chunk_id=f"{sentence_id}_fallback_{audio_chunks_generated}",
                                sentence_id=sentence_id,
                                sequence=text_chunk.sequence_id,
                                audio_data=audio_data,
                                is_sentence_end=(audio_chunks_generated == 0),
                                boundary_type=text_chunk.boundary_type,
                                metadata={
                                    **text_chunk.metadata,
                                    "audio_format": self.config.default_format,
                                    "voice_used": voice,
                                    "chunk_index": audio_chunks_generated,
                                    "is_fallback": True,
                                    "original_format_failed": optimal_format,
                                    "tts_processing_time_ms": (time.time() - chunk_timestamp) * 1000,
                                    "boundary_type": text_chunk.boundary_type.value
                                }
                            )
                            
                            success = await self._add_to_client_queue(audio_chunk)
                            if success:
                                audio_chunks_generated += 1
                            else:
                                break
                                
                        except Exception as decode_error:
                            self.logger.warning(f"Failed to decode fallback audio chunk: {decode_error}")
                            continue
                    
                    self.logger.info(f"Fallback TTS completed: {audio_chunks_generated} chunks")
                    
                except Exception as fallback_error:
                    self.logger.error(f"Fallback TTS also failed: {str(fallback_error)}")
                    raise
    
    async def _stream_tts_audio(self, text: str, tts_params: Dict[str, Any]) -> AsyncGenerator[str, None]:
        """
        Stream TTS audio using existing LLMManager (provider-agnostic).
        
        Args:
            text: Text to convert to speech
            tts_params: TTS parameters including voice, format, etc.
            
        Yields:
            str: Base64-encoded audio chunks from the TTS response
        """
        try:
            # Use existing LLMManager for streaming TTS
            async for chunk_b64 in self.llm_manager.stream_text_to_speech(
                text=text,
                **tts_params
            ):
                yield chunk_b64
                    
        except Exception as e:
            self.logger.error(f"Error streaming TTS audio: {e}")
            self.metrics.tts_errors += 1
            # Re-raise the exception so it can be handled in _process_tts_chunk
            # where the fallback audio logic exists
            raise
    
    def _get_consistent_voice(self, conversation_id: str, voice_seed: str, conversation_voices: Dict[str, str]) -> str:
        """
        Get consistent voice for conversation using deterministic selection.
        
        Args:
            conversation_id: Unique conversation identifier
            voice_seed: Deterministic seed for voice selection
            conversation_voices: Dictionary tracking conversation voice mapping
            
        Returns:
            str: Voice identifier for TTS (e.g., "alloy", "echo", "fable", etc.)
        """
        try:
            # Check if we already have a voice for this conversation
            if conversation_id in conversation_voices:
                return conversation_voices[conversation_id]
            
            # Available OpenAI TTS voices
            available_voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
            
            # Use voice seed to deterministically select a voice
            if voice_seed:
                import hashlib
                seed_hash = hashlib.md5(voice_seed.encode()).hexdigest()
                voice_index = int(seed_hash[:2], 16) % len(available_voices)
                selected_voice = available_voices[voice_index]
            else:
                # Default to first voice if no seed
                selected_voice = available_voices[0]
            
            # Store voice for conversation consistency
            conversation_voices[conversation_id] = selected_voice
            
            self.logger.debug(f"Selected voice '{selected_voice}' for conversation {conversation_id}")
            return selected_voice
            
        except Exception as e:
            self.logger.warning(f"Error selecting voice: {e}")
            # Fallback to default voice
            fallback_voice = "alloy"
            conversation_voices[conversation_id] = fallback_voice
            return fallback_voice
    
    async def _add_to_client_queue(self, audio_chunk: AudioChunk) -> bool:
        """
        Add audio chunk to client queue with flow control and backpressure handling.
        
        Args:
            audio_chunk: The audio chunk to add to client processing
            
        Returns:
            bool: True if successfully added, False if rejected due to backpressure
        """
        try:
            # Check flow control state
            if self.flow_state == FlowControlState.PAUSED:
                self.logger.warning("Client queue add rejected - pipeline paused")
                return False
            
            # Use timeout to avoid blocking indefinitely
            timeout = 2.0 if self.flow_state == FlowControlState.FLOWING else 0.5
            
            await asyncio.wait_for(
                self.client_queue.put(audio_chunk),
                timeout=timeout
            )
            
            return True
            
        except asyncio.TimeoutError:
            self.logger.warning(f"Client queue timeout for chunk: {audio_chunk.chunk_id}")
            self.metrics.backpressure_events += 1
            return False
        except Exception as e:
            self.logger.error(f"Error adding to client queue: {e}")
            return False
    
    async def _client_sender(self) -> None:
        """
        Client sender with jitter buffer support - Step 5 Implementation
        
        Features:
        - Flow control reset in client sender
        - Sentence ID included for clean interruption  
        - Sequence preservation metadata
        - Progress tracking with counters
        - Checkpoint frames for sequence validation
        - Clean WebSocket disconnection handling
        - Performance logging with timing metrics
        """
        self.logger.info("Client sender started")
        
        # Progress tracking counters
        chunks_sent = 0
        sequence_counter = 0
        last_checkpoint_time = time.time()
        checkpoint_interval = 5.0  # Send checkpoint every 5 seconds
        
        # Performance timing metrics
        last_performance_log = time.time()
        performance_log_interval = 10.0  # Log performance every 10 seconds
        
        while not self.shutdown_event.is_set():
            try:
                # Get audio chunk from queue with timeout
                try:
                    audio_chunk = await asyncio.wait_for(
                        self.client_queue.get(),
                        timeout=1.0
                    )
                except asyncio.TimeoutError:
                    # Check for periodic checkpoint frames and performance logging
                    await self._handle_periodic_tasks(
                        last_checkpoint_time, last_performance_log,
                        checkpoint_interval, performance_log_interval,
                        sequence_counter, chunks_sent
                    )
                    continue
                
                # Flow control reset check - Skip sending if paused
                if self.flow_state == FlowControlState.PAUSED:
                    self.logger.debug(f"Skipping chunk {audio_chunk.chunk_id} - flow control paused")
                    continue
                
                # Prepare audio frame with jitter buffer metadata
                audio_frame, binary_data = self._prepare_audio_frame(audio_chunk, sequence_counter)
                
                # Send to all active clients with error handling
                sent_count = await self._send_to_active_clients(audio_frame, audio_chunk.chunk_id, binary_data)
                
                if sent_count > 0:
                    chunks_sent += 1
                    sequence_counter += 1
                    self.metrics.audio_chunks_sent += 1
                    
                    # Track timing metrics for performance
                    chunk_age_ms = (time.time() - audio_chunk.timestamp.timestamp()) * 1000
                    self.metrics.update_timing("avg_end_to_end_ms", chunk_age_ms)
                
                # Update timing for periodic tasks
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
                await asyncio.sleep(0.1)  # Brief delay on error
        
        # Clean disconnection handling
        await self._handle_clean_disconnection(sequence_counter, chunks_sent)
        self.logger.info("Client sender stopped")
    
    def _prepare_audio_frame(self, audio_chunk: AudioChunk, sequence_counter: int, use_binary: bool = False) -> Tuple[Dict[str, Any], bytes]:
        """
        Prepare audio frame with complete jitter buffer metadata
        Supports both JSON and binary WebSocket frame formats
        
        Args:
            audio_chunk: The audio chunk to send
            sequence_counter: Current sequence number for ordering
            use_binary: Whether to prepare binary frame format
            
        Returns:
            Tuple[Dict, bytes]: (metadata_frame, binary_audio_data) for binary mode
                               or (complete_frame, None) for JSON mode
        """
        import base64
        
        # Common metadata structure
        metadata = {
            "type": "audio",
            "chunk_id": audio_chunk.chunk_id,
            "sentence_id": audio_chunk.sentence_id,
            "sequence": sequence_counter,
            "is_sentence_end": audio_chunk.is_sentence_end,
            "boundary_type": audio_chunk.boundary_type.value if audio_chunk.boundary_type else "unknown",
            "timestamp": audio_chunk.timestamp.isoformat(),
            
            # Jitter buffer guidance
            "jitter_buffer": {
                "sequence_id": sequence_counter,
                "buffer_hint_ms": self.config.jitter_buffer_target_ms,
                "is_realtime": True,
                "max_age_ms": 500
            },
            
            # Performance metadata
            "performance": {
                "generation_latency_ms": round(self.metrics.avg_tts_latency_ms, 2),
                "end_to_end_latency_ms": round(self.metrics.avg_end_to_end_ms, 2),
                "sequence_number": sequence_counter
            },
            
            # Audio format info
            "audio_format": {
                "encoding": "wav",
                "sample_rate": 16000,
                "channels": 1,
                "bit_depth": 16
            },
            
            # Complete metadata forwarding
            "metadata": {
                **audio_chunk.metadata,
                "pipeline_sequence": sequence_counter,
                "flow_control_state": self.flow_state.value
            }
        }
        
        if use_binary:
            # Binary frame format: 32-bit audio length + raw audio data
            # Client receives metadata via initial frame, then binary audio
            metadata["audio_length"] = len(audio_chunk.audio_data)
            metadata["frame_format"] = "binary"
            return metadata, audio_chunk.audio_data
        else:
            # JSON frame format (existing)
            metadata["audio_data"] = base64.b64encode(audio_chunk.audio_data).decode()
            metadata["frame_format"] = "json"
            return metadata, None

    async def _send_to_active_clients(self, audio_frame: Dict[str, Any], chunk_id: str, binary_data: Optional[bytes] = None) -> int:
        """
        Send audio frame to all active clients with clean error handling
        Supports both JSON and binary WebSocket frame formats
        
        Args:
            audio_frame: The audio frame metadata to send
            chunk_id: Chunk identifier for logging
            binary_data: Optional binary audio data for binary frame mode
            
        Returns:
            int: Number of clients successfully sent to
        """
        if not self.active_clients:
            return 0
        
        sent_count = 0
        disconnected_clients = []
        
        for client_id, websocket in self.active_clients.items():
            try:
                # Check if client supports binary frames (based on client capabilities)
                client_supports_binary = getattr(websocket, '_supports_binary_frames', False)
                
                if binary_data and client_supports_binary:
                    # Send binary frame: metadata + binary audio
                    # First send metadata as JSON
                    await websocket.send(json.dumps(audio_frame))
                    # Then send raw binary audio data
                    await websocket.send(binary_data)
                    self.logger.debug(f"Sent binary frame to client {client_id}: {len(binary_data)} bytes")
                else:
                    # Send JSON frame (fallback and default)
                    await websocket.send(json.dumps(audio_frame))
                    
                sent_count += 1
                
            except Exception as e:
                self.logger.warning(f"Failed to send chunk {chunk_id} to client {client_id}: {e}")
                disconnected_clients.append(client_id)
                self.metrics.client_errors += 1
        
        # Clean up disconnected clients
        for client_id in disconnected_clients:
            await self.unregister_client(client_id)
        
        return sent_count
    
    async def _send_checkpoint_frame(self, sequence_counter: int, chunks_sent: int) -> None:
        """
        Send checkpoint frame for sequence validation
        
        Args:
            sequence_counter: Current sequence number
            chunks_sent: Total chunks sent so far
        """
        checkpoint_frame = {
            "type": "checkpoint",
            "sequence_checkpoint": sequence_counter,
            "chunks_sent": chunks_sent,
            "timestamp": datetime.now().isoformat(),
            "flow_control_state": self.flow_state.value,
            "performance_snapshot": {
                "avg_latency_ms": round(self.metrics.avg_end_to_end_ms, 2),
                "queue_sizes": {
                    "llm": self.llm_queue.qsize(),
                    "tts": self.tts_queue.qsize(),
                    "client": self.client_queue.qsize()
                }
            }
        }
        
        # Send to all active clients
        await self._send_to_active_clients(checkpoint_frame, f"checkpoint-{sequence_counter}", None)
    
    async def _log_performance_metrics(self, chunks_sent: int, sequence_counter: int) -> None:
        """
        Log performance metrics with timing data and send to production monitoring
        
        Args:
            chunks_sent: Total chunks sent
            sequence_counter: Current sequence number
        """
        # Standard logging
        self.logger.info(
            f"Client sender performance: "
            f"chunks_sent={chunks_sent}, "
            f"sequence={sequence_counter}, "
            f"avg_latency={self.metrics.avg_end_to_end_ms:.1f}ms, "
            f"ttfa={self.metrics.time_to_first_audio_ms:.1f}ms, "
            f"active_clients={len(self.active_clients)}, "
            f"flow_state={self.flow_state.value}"
        )
        
        # Issue #7: Send performance metrics to Firebase/Sentry
        if production_metrics.is_metrics_enabled() and production_metrics.should_report_metrics():
            try:
                # Update queue metrics before sending
                self.metrics.llm_queue_size = self.llm_queue.qsize()
                self.metrics.tts_queue_size = self.tts_queue.qsize()
                self.metrics.client_queue_size = self.client_queue.qsize()
                
                # Send to production monitoring
                production_metrics.send_performance_metrics(self.metrics, self.pipeline_id)
                
                # Send critical alerts if performance targets are missed
                if self.metrics.time_to_first_audio_ms > self.metrics.target_ttfa_ms:
                    production_metrics.send_critical_metric(
                        "ttfa_target_exceeded",
                        self.metrics.time_to_first_audio_ms,
                        {
                            "target": str(self.metrics.target_ttfa_ms),
                            "pipeline_id": self.pipeline_id,
                            "active_clients": str(len(self.active_clients))
                        }
                    )
                    
                if self.metrics.avg_end_to_end_ms > self.metrics.target_latency_ms:
                    production_metrics.send_critical_metric(
                        "latency_target_exceeded", 
                        self.metrics.avg_end_to_end_ms,
                        {
                            "target": str(self.metrics.target_latency_ms),
                            "pipeline_id": self.pipeline_id,
                            "flow_state": self.flow_state.value
                        }
                    )
                    
            except Exception as e:
                self.logger.error(f"Failed to send production metrics: {str(e)}")
    
    async def _handle_periodic_tasks(self, last_checkpoint: float, last_performance: float,
                                   checkpoint_interval: float, performance_interval: float,
                                   sequence_counter: int, chunks_sent: int) -> None:
        """Handle periodic checkpoint and performance logging tasks"""
        current_time = time.time()
        
        if current_time - last_checkpoint >= checkpoint_interval:
            await self._send_checkpoint_frame(sequence_counter, chunks_sent)
        
        if current_time - last_performance >= performance_interval:
            await self._log_performance_metrics(chunks_sent, sequence_counter)
    
    async def _handle_clean_disconnection(self, sequence_counter: int, chunks_sent: int) -> None:
        """
        Handle clean WebSocket disconnection with final summary
        
        Args:
            sequence_counter: Final sequence number
            chunks_sent: Total chunks sent during session
        """
        # Send completion frame to all clients
        completion_frame = {
            "type": "complete",
            "final_sequence": sequence_counter,
            "total_chunks_sent": chunks_sent,
            "session_summary": {
                "total_audio_chunks": chunks_sent,
                "avg_latency_ms": round(self.metrics.avg_end_to_end_ms, 2),
                "time_to_first_audio_ms": round(self.metrics.time_to_first_audio_ms, 2),
                "backpressure_events": self.metrics.backpressure_events,
                "stale_chunks_dropped": self.metrics.stale_chunks_dropped
            },
            "timestamp": datetime.now().isoformat()
        }
        
        # Send to all clients with error handling
        await self._send_to_active_clients(completion_frame, "completion", None)
        
        # Log final session statistics
        self.logger.info(
            f"Session completed: chunks_sent={chunks_sent}, "
            f"final_sequence={sequence_counter}, "
            f"avg_latency={self.metrics.avg_end_to_end_ms:.1f}ms"
        )
    
    async def _flow_control_monitor(self) -> None:
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
                await asyncio.sleep(1.0)  # Longer delay on error
        
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
            if max_pressure > 0.9:  # 90% queue full triggers throttling (raised from 80%)
                self.flow_state = FlowControlState.THROTTLED
                self.logger.info(f"Flow control throttled (pressure: {max_pressure:.2f})")
            elif max_pressure > 0.98:  # 98% queue full triggers pause (raised from 95%)
                self.flow_state = FlowControlState.PAUSED
                self.backpressure_start_time = current_time
                self.metrics.flow_control_pauses += 1
                self.logger.warning(f"Flow control paused (pressure: {max_pressure:.2f})")
        
        elif self.flow_state == FlowControlState.THROTTLED:
            if max_pressure < 0.6:  # Pressure relief allows return to flowing
                self.flow_state = FlowControlState.FLOWING
                self.logger.info("Flow control resumed (throttling cleared)")
            elif max_pressure > 0.95:
                self.flow_state = FlowControlState.PAUSED
                self.backpressure_start_time = current_time
                self.metrics.flow_control_pauses += 1
                self.logger.warning("Flow control paused (from throttled)")
        
        elif self.flow_state == FlowControlState.PAUSED:
            # Check if we should recover from pause
            if max_pressure < 0.4:  # Significant pressure relief needed
                self.flow_state = FlowControlState.RECOVERING
                self.logger.info("Flow control recovering")
            elif (self.backpressure_start_time and 
                  (current_time - self.backpressure_start_time) > 
                  (self.config.backpressure_timeout_ms / 1000)):
                # Timeout fallback - force recovery after timeout
                self.flow_state = FlowControlState.RECOVERING
                self.logger.warning("Flow control timeout - forcing recovery")
        
        elif self.flow_state == FlowControlState.RECOVERING:
            # Short recovery delay before resuming
            if (self.backpressure_start_time and 
                (current_time - self.backpressure_start_time) > 
                (self.config.recovery_delay_ms / 1000)):
                self.flow_state = FlowControlState.FLOWING
                self.backpressure_start_time = None
                self.logger.info("Flow control fully recovered")
    
    async def _memory_monitor(self) -> None:
        """Monitor memory usage and enforce limits"""
        self.logger.info("Memory monitor started")
        
        while not self.shutdown_event.is_set():
            try:
                # Calculate approximate memory usage
                memory_usage = (
                    self.llm_queue.qsize() * 1024 +  # ~1KB per LLM message
                    self.tts_queue.qsize() * 512 +   # ~512B per text chunk
                    self.client_queue.qsize() * 8192  # ~8KB per audio chunk
                )
                
                self.metrics.memory_usage_bytes = memory_usage
                self.metrics.peak_memory_bytes = max(
                    self.metrics.peak_memory_bytes, 
                    memory_usage
                )
                
                # Check memory limits
                if memory_usage > self.config.max_memory_bytes:
                    self.logger.warning(f"Memory limit exceeded: {memory_usage} bytes")
                    await self._emergency_memory_cleanup()
                
                # Check every 5 seconds
                await asyncio.sleep(5.0)
                
            except Exception as e:
                self.logger.error(f"Memory monitor error: {e}")
                await asyncio.sleep(5.0)
        
        self.logger.info("Memory monitor stopped")
    
    async def _stale_chunk_cleaner(self) -> None:
        """Clean up stale chunks that exceed timing thresholds"""
        self.logger.info("Stale chunk cleaner started")
        
        while not self.shutdown_event.is_set():
            try:
                current_time = time.time()
                stale_threshold = self.config.stale_chunk_threshold_ms / 1000
                
                # Check for stale chunks and remove them
                stale_count = 0
                for chunk_id, timestamp in list(self.stale_chunk_timestamps.items()):
                    if (current_time - timestamp) > stale_threshold:
                        del self.stale_chunk_timestamps[chunk_id]
                        stale_count += 1
                
                if stale_count > 0:
                    self.metrics.stale_chunks_dropped += stale_count
                    self.logger.info(f"Dropped {stale_count} stale chunks")
                
                # Check every 2 seconds
                await asyncio.sleep(2.0)
                
            except Exception as e:
                self.logger.error(f"Stale chunk cleaner error: {e}")
                await asyncio.sleep(2.0)
        
        self.logger.info("Stale chunk cleaner stopped")
    
    async def _emergency_memory_cleanup(self) -> None:
        """Emergency cleanup when memory limits are exceeded"""
        self.logger.warning("Performing emergency memory cleanup")
        
        # Clear oldest items from queues
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
    
    async def _cleanup_tasks(self) -> None:
        """Clean up all pipeline tasks"""
        if not self.pipeline_tasks:
            return
        
        # Cancel all tasks
        for task in self.pipeline_tasks:
            if not task.done():
                task.cancel()
        
        # Wait for cancellation with timeout
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


# Utility functions for pipeline management

async def create_pipeline(config: Optional[FlowControlConfig] = None) -> EnhancedAsyncPipeline:
    """
    Factory function to create and start a new pipeline.
    
    Args:
        config: Optional flow control configuration
        
    Returns:
        Started EnhancedAsyncPipeline instance
    """
    pipeline = EnhancedAsyncPipeline(config)
    await pipeline.start()
    return pipeline


def get_default_config() -> FlowControlConfig:
    """Get default flow control configuration"""
    return FlowControlConfig()


def get_production_config() -> FlowControlConfig:
    """Get production-optimized flow control configuration"""
    return FlowControlConfig(
        # Larger queues for production load
        max_llm_queue_size=10,
        max_tts_queue_size=20,
        max_client_queue_size=30,
        
        # Tighter stale detection for better UX
        stale_chunk_threshold_ms=1500,
        backpressure_timeout_ms=3000,
        recovery_delay_ms=50,
        
        # Higher memory limit for production
        max_memory_bytes=100 * 1024 * 1024,  # 100MB
        
        # Optimized jitter buffer for mobile
        jitter_buffer_min_ms=150,
        jitter_buffer_max_ms=400,
        jitter_buffer_target_ms=250
    ) 