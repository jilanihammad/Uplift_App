"""
Pipeline package: decomposed streaming pipeline for TTS.

Re-exports all public symbols so that
  from app.services.pipeline import EnhancedAsyncPipeline, StreamingMessage, ...
works exactly like the old monolithic module.
"""

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

from .metrics import (
    PipelineMetrics,
    ProductionMetricsService,
    production_metrics,
)

from .pipeline import (
    EnhancedAsyncPipeline,
    create_pipeline,
    get_default_config,
    get_production_config,
)

# Re-export text_processor types that were importable from the old monolithic module
from app.utils.text_processor import TextChunk, BoundaryType

__all__ = [
    # Models
    "PipelineState",
    "StreamingMessage",
    "AudioChunk",
    "CompletionSentinel",
    # Flow control
    "FlowControlState",
    "FlowControlConfig",
    "FlowControlMonitor",
    # Metrics
    "PipelineMetrics",
    "ProductionMetricsService",
    "production_metrics",
    # Pipeline
    "EnhancedAsyncPipeline",
    "create_pipeline",
    "get_default_config",
    "get_production_config",
    # Re-exported from text_processor for backward compat
    "TextChunk",
    "BoundaryType",
]
