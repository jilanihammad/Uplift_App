"""Audio format selection strategy.

Pure functions for assessing client network quality and choosing a TTS
audio format that fits. No mutable state; no per-chunk performance impact
since these run once per client init, not per audio chunk.

Hot-path note: ``_prepare_audio_frame`` (which embeds live ``self.metrics``
and ``self.flow_state`` into every chunk) deliberately stays on
``EnhancedAsyncPipeline`` until bead Uplift_App-6ya rewires the client
sender — separating it now would force per-chunk cross-module reads of
mutable state.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from app.core.llm_config import LLMConfig

from .flow_control import FlowControlConfig

logger = logging.getLogger(__name__)


def assess_network_quality(
    client_metrics: Dict[str, Any], config: FlowControlConfig
) -> str:
    """Return one of ``excellent``/``good``/``fair``/``poor``."""
    rtt_ms = client_metrics.get("rtt_ms", 0)
    packet_loss = client_metrics.get("packet_loss_percent", 0)
    bandwidth_kbps = client_metrics.get("bandwidth_kbps", 0)
    jitter_ms = client_metrics.get("jitter_ms", 0)

    quality_score = 100

    if rtt_ms > config.poor_network_threshold_ms:
        quality_score -= 40
    elif rtt_ms > config.good_network_threshold_ms:
        quality_score -= 20

    if packet_loss > 5:
        quality_score -= 30
    elif packet_loss > 1:
        quality_score -= 15

    if bandwidth_kbps < 128:
        quality_score -= 25
    elif bandwidth_kbps < 256:
        quality_score -= 10

    if jitter_ms > 100:
        quality_score -= 15
    elif jitter_ms > 50:
        quality_score -= 8

    if quality_score >= 80:
        return "excellent"
    if quality_score >= 60:
        return "good"
    if quality_score >= 40:
        return "fair"
    return "poor"


def select_optimal_format(
    network_quality: str,
    client_capabilities: Dict[str, Any],
    config: FlowControlConfig,
) -> str:
    """Pick the best TTS format the client can decode for this network."""
    supported_formats = client_capabilities.get("supported_formats", ["wav"])
    if "native" in supported_formats:
        return "native"

    if network_quality == "poor":
        if "opus" in supported_formats:
            return "opus"
        if "aac" in supported_formats:
            return "aac"
        return "wav"
    if network_quality == "fair":
        if "aac" in supported_formats:
            return "aac"
        if "opus" in supported_formats:
            return "opus"
        return "wav"
    if network_quality in ("good", "excellent"):
        if "wav" in supported_formats:
            return "wav"
        if "aac" in supported_formats:
            return "aac"
        return "opus"

    return config.default_format


def get_format_parameters(audio_format: str) -> Dict[str, Any]:
    """Return TTS provider parameters for a given format."""
    if audio_format == "native":
        tts_config = LLMConfig.get_tts_config()
        return {
            "response_format": "native",
            "mime_type": tts_config.get("mime_type", "audio/ogg; codecs=opus"),
            "sample_rate": tts_config.get("sample_rate_hz", 24000),
            "channels": 1,
            "latency_category": "lowest",
        }

    format_configs: Dict[str, Dict[str, Any]] = {
        "wav": {
            "response_format": "wav",
            "sample_rate": 16000,
            "channels": 1,
            "bit_depth": 16,
            "estimated_bitrate_kbps": 256,
            "latency_category": "lowest",
        },
        "opus": {
            "response_format": "ogg_opus",
            "mime_type": "audio/ogg; codecs=opus",
            "sample_rate": 24000,
            "channels": 1,
            "bitrate": "24k",
            "estimated_bitrate_kbps": 24,
            "latency_category": "low",
        },
        "aac": {
            "response_format": "aac",
            "sample_rate": 48000,
            "channels": 1,
            "bitrate": "64k",
            "estimated_bitrate_kbps": 64,
            "latency_category": "medium",
        },
    }

    return format_configs.get(audio_format, format_configs["wav"])


def validated_format(requested_format: Optional[str], llm_manager: Any) -> str:
    """Pass-through validation; LLMManager owns the actual format check."""
    try:
        if (
            llm_manager
            and hasattr(llm_manager, "tts_config")
            and llm_manager.tts_config
        ):
            default_format = llm_manager.tts_config.default_params.get(
                "response_format", "wav"
            )
        else:
            default_format = "wav"
        return requested_format if requested_format else default_format
    except Exception as exc:  # noqa: BLE001
        logger.warning("Error in format selection: %s, using wav", exc)
        return "wav"


def dynamic_audio_format(
    chunk_metadata: Dict[str, Any], config: FlowControlConfig
) -> Dict[str, Any]:
    """Build the audio_format frame metadata for one outgoing chunk."""
    audio_format = chunk_metadata.get("audio_format", config.default_format)
    format_params = get_format_parameters(audio_format)

    if audio_format == "opus":
        return {
            "encoding": "opus",
            "mime_type": format_params.get("mime_type", "audio/ogg; codecs=opus"),
            "sample_rate": format_params.get("sample_rate", 24000),
            "channels": format_params.get("channels", 1),
            "bitrate": format_params.get("bitrate", "24k"),
            "container": "ogg",
        }
    if audio_format == "wav":
        return {
            "encoding": "wav",
            "mime_type": "audio/wav",
            "sample_rate": format_params.get("sample_rate", 16000),
            "channels": format_params.get("channels", 1),
            "bit_depth": format_params.get("bit_depth", 16),
        }
    return {
        "encoding": audio_format,
        "mime_type": format_params.get("mime_type", f"audio/{audio_format}"),
        "sample_rate": format_params.get("sample_rate", 16000),
        "channels": format_params.get("channels", 1),
    }
