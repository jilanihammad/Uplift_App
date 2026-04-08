"""
Pipeline data models: StreamingMessage, AudioChunk, CompletionSentinel, PipelineState.
"""

from datetime import datetime
from typing import Dict, Any
from dataclasses import dataclass, field
from enum import Enum

from app.utils.text_processor import BoundaryType


class PipelineState(Enum):
    """Pipeline state management"""
    IDLE = "idle"
    INITIALIZING = "initializing"
    STREAMING = "streaming"
    PAUSED = "paused"
    STOPPING = "stopping"
    ERROR = "error"


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


@dataclass
class CompletionSentinel:
    """Completion sentinel to signal end of TTS generation for a specific request"""
    request_id: str
    conversation_id: str
    total_chunks: int
    completion_timestamp: datetime = field(default_factory=datetime.now)
    metadata: Dict[str, Any] = field(default_factory=dict)
