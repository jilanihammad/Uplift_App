"""Periodic and shutdown helpers for the client sender loop.

These are NOT on the per-chunk hot path:
- ``send_checkpoint_frame`` fires every ``checkpoint_interval`` seconds (~5s).
- ``log_performance_metrics`` fires every ``performance_log_interval`` seconds (~10s).
- ``handle_periodic_tasks`` fires when ``client_queue.get()`` times out (~1s).
- ``handle_clean_disconnection`` fires once at shutdown.

Extracting them keeps pipeline.py focused on the streaming task lifecycle
without forcing per-chunk cross-module state reads. Each helper takes the
state it needs by argument (no closures over pipeline self), which makes
them straightforward to unit-test once the backend comes back online.
"""
from __future__ import annotations

import logging
import time
from datetime import datetime
from typing import Any

import asyncio

from .connection_registry import ConnectionRegistry
from .flow_control import FlowControlState
from .metrics import PipelineMetrics, production_metrics


async def send_checkpoint_frame(
    *,
    connections: ConnectionRegistry,
    flow_state: FlowControlState,
    metrics: PipelineMetrics,
    llm_queue_size: int,
    tts_queue_size: int,
    client_queue_size: int,
    sequence_counter: int,
    chunks_sent: int,
) -> None:
    """Broadcast a ``checkpoint`` frame so clients can validate sequence."""
    checkpoint_frame = {
        "type": "checkpoint",
        "sequence_checkpoint": sequence_counter,
        "chunks_sent": chunks_sent,
        "timestamp": datetime.now().isoformat(),
        "flow_control_state": flow_state.value,
        "performance_snapshot": {
            "avg_latency_ms": round(metrics.avg_end_to_end_ms, 2),
            "queue_sizes": {
                "llm": llm_queue_size,
                "tts": tts_queue_size,
                "client": client_queue_size,
            },
        },
    }
    await connections.send_to_all(
        checkpoint_frame, f"checkpoint-{sequence_counter}", None
    )


async def log_performance_metrics(
    *,
    logger: logging.Logger,
    metrics: PipelineMetrics,
    connections: ConnectionRegistry,
    flow_state: FlowControlState,
    pipeline_id: str,
    llm_queue: asyncio.Queue,
    tts_queue: asyncio.Queue,
    client_queue: asyncio.Queue,
    sequence_counter: int,
    chunks_sent: int,
) -> None:
    """Log per-interval performance + push to production_metrics if enabled."""
    logger.info(
        f"Client sender performance: "
        f"chunks_sent={chunks_sent}, "
        f"sequence={sequence_counter}, "
        f"avg_latency={metrics.avg_end_to_end_ms:.1f}ms, "
        f"ttfa={metrics.time_to_first_audio_ms:.1f}ms, "
        f"active_clients={len(connections)}, "
        f"flow_state={flow_state.value}"
    )

    if not (
        production_metrics.is_metrics_enabled()
        and production_metrics.should_report_metrics()
    ):
        return

    try:
        metrics.llm_queue_size = llm_queue.qsize()
        metrics.tts_queue_size = tts_queue.qsize()
        metrics.client_queue_size = client_queue.qsize()

        production_metrics.send_performance_metrics(metrics, pipeline_id)

        if metrics.time_to_first_audio_ms > metrics.target_ttfa_ms:
            production_metrics.send_critical_metric(
                "ttfa_target_exceeded",
                metrics.time_to_first_audio_ms,
                {
                    "target": str(metrics.target_ttfa_ms),
                    "pipeline_id": pipeline_id,
                    "active_clients": str(len(connections)),
                },
            )

        if metrics.avg_end_to_end_ms > metrics.target_latency_ms:
            production_metrics.send_critical_metric(
                "latency_target_exceeded",
                metrics.avg_end_to_end_ms,
                {
                    "target": str(metrics.target_latency_ms),
                    "pipeline_id": pipeline_id,
                    "flow_state": flow_state.value,
                },
            )
    except Exception as exc:  # noqa: BLE001
        logger.error(f"Failed to send production metrics: {exc}")


async def handle_periodic_tasks(
    *,
    last_checkpoint: float,
    last_performance: float,
    checkpoint_interval: float,
    performance_interval: float,
    on_checkpoint: Any,
    on_performance: Any,
) -> None:
    """Fire periodic callbacks if their intervals have elapsed.

    ``on_checkpoint`` and ``on_performance`` are zero-arg awaitables (lambdas
    closing over the per-loop counters), so this helper stays free of
    knowledge about checkpoint/log payloads.
    """
    current_time = time.time()
    if current_time - last_checkpoint >= checkpoint_interval:
        await on_checkpoint()
    if current_time - last_performance >= performance_interval:
        await on_performance()


async def handle_clean_disconnection(
    *,
    logger: logging.Logger,
    connections: ConnectionRegistry,
    metrics: PipelineMetrics,
    sequence_counter: int,
    chunks_sent: int,
) -> None:
    """Send a ``complete`` summary frame and log session totals at shutdown."""
    completion_frame = {
        "type": "complete",
        "final_sequence": sequence_counter,
        "total_chunks_sent": chunks_sent,
        "session_summary": {
            "total_audio_chunks": chunks_sent,
            "avg_latency_ms": round(metrics.avg_end_to_end_ms, 2),
            "time_to_first_audio_ms": round(metrics.time_to_first_audio_ms, 2),
            "backpressure_events": metrics.backpressure_events,
            "stale_chunks_dropped": metrics.stale_chunks_dropped,
        },
        "timestamp": datetime.now().isoformat(),
    }
    await connections.send_to_all(completion_frame, "completion", None)
    logger.info(
        f"Session completed: chunks_sent={chunks_sent}, "
        f"final_sequence={sequence_counter}, "
        f"avg_latency={metrics.avg_end_to_end_ms:.1f}ms"
    )
