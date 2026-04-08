"""
Pipeline metrics: PipelineMetrics dataclass and ProductionMetricsService.
"""

import json
import time
import logging
from datetime import datetime
from typing import Dict, Any
from dataclasses import dataclass


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
