"""
Smart Text Processor for Streaming TTS
Handles sentence boundary detection with prosody preservation and performance optimization.

Critical Features:
- Smart sentence boundary detection using multiple heuristics
- Abbreviation safe-list to prevent prosody breaks
- LLM pause token integration for natural speech flow
- Memory tracking and performance monitoring
- Character-based safety limits
- Buffer management with proper cleanup
"""

import re
import time
import logging
from typing import List, Tuple, Optional, Dict, Any
from dataclasses import dataclass
from enum import Enum


class BoundaryType(Enum):
    """Types of text boundaries for streaming TTS"""
    SENTENCE_END = "sentence_end"
    PAUSE_TOKEN = "pause_token"
    CHARACTER_LIMIT = "character_limit"
    PARAGRAPH_BREAK = "paragraph_break"


@dataclass
class TextChunk:
    """Represents a processed text chunk ready for TTS"""
    text: str
    boundary_type: BoundaryType
    sequence_id: int
    metadata: Dict[str, Any]
    processing_time_ms: float
    character_count: int


class SmartTextProcessor:
    """
    High-performance text processor for streaming TTS with intelligent boundary detection.
    
    Performance Target: <5ms per chunk processing
    Memory Safety: Automatic buffer cleanup and size limits
    Prosody Safety: Abbreviation handling and natural pause detection
    """
    
    # Abbreviation safe-list to prevent prosody breaks
    ABBREVIATIONS = {
        'dr.', 'mr.', 'mrs.', 'ms.', 'prof.', 'sr.', 'jr.', 'vs.', 'etc.', 'inc.', 'ltd.', 'corp.',
        'co.', 'dept.', 'govt.', 'org.', 'edu.', 'com.', 'net.', 'org.', 'gov.', 'mil.', 'int.',
        'st.', 'ave.', 'blvd.', 'rd.', 'ln.', 'ct.', 'pl.', 'sq.', 'ft.', 'in.', 'yd.', 'mi.',
        'kg.', 'lb.', 'oz.', 'mph.', 'min.', 'sec.', 'hr.', 'am.', 'pm.', 'jan.', 'feb.', 'mar.',
        'apr.', 'may.', 'jun.', 'jul.', 'aug.', 'sep.', 'oct.', 'nov.', 'dec.', 'mon.', 'tue.',
        'wed.', 'thu.', 'fri.', 'sat.', 'sun.', 'vol.', 'no.', 'pg.', 'ch.', 'sec.', 'fig.',
        'ref.', 'cf.', 'i.e.', 'e.g.', 'viz.', 'circa.', 'ca.', 'approx.', 'est.'
    }
    
    # LLM pause tokens that indicate natural speech breaks
    PAUSE_TOKENS = {
        '...', '—', '–', '<pause>', '[pause]', '<break>', '[break]'
    }
    
    # Sentence ending patterns (with abbreviation safety)
    SENTENCE_ENDINGS = re.compile(r'([.!?]+)(?=\s+[A-Z]|\s*$)', re.MULTILINE)
    
    # Character limits for safety valve
    MIN_CHUNK_LENGTH = 20  # Minimum characters before considering boundary
    MAX_CHUNK_LENGTH = 200  # Maximum characters before forced boundary
    OPTIMAL_CHUNK_LENGTH = 80  # Optimal length for TTS prosody
    
    # Memory tracking limits
    MAX_BUFFER_SIZE = 2048  # Maximum buffer size in characters
    MAX_MEMORY_MB = 10  # Maximum memory usage in MB
    
    def __init__(self, enable_memory_tracking: bool = True):
        """
        Initialize the Smart Text Processor
        
        Args:
            enable_memory_tracking: Enable detailed memory and performance tracking
        """
        self.buffer = ""
        self.sequence_counter = 0
        self.total_chunks_processed = 0
        self.total_processing_time_ms = 0.0
        self.current_memory_bytes = 0
        self.enable_memory_tracking = enable_memory_tracking
        
        # Performance metrics
        self.metrics = {
            'chunks_processed': 0,
            'avg_processing_time_ms': 0.0,
            'buffer_resets': 0,
            'abbreviation_saves': 0,
            'pause_token_breaks': 0,
            'character_limit_breaks': 0,
            'memory_peak_bytes': 0
        }
        
        # Compiled regex patterns for performance
        self._abbreviation_pattern = self._compile_abbreviation_pattern()
        self._pause_token_pattern = self._compile_pause_token_pattern()
        
        # Logger for debugging
        self.logger = logging.getLogger(__name__)
        
    def _compile_abbreviation_pattern(self) -> re.Pattern:
        """Compile abbreviation pattern for fast lookup"""
        # Create case-insensitive pattern for abbreviations
        abbrev_list = '|'.join(re.escape(abbrev) for abbrev in self.ABBREVIATIONS)
        return re.compile(f'({abbrev_list})\\s*$', re.IGNORECASE)
    
    def _compile_pause_token_pattern(self) -> re.Pattern:
        """Compile pause token pattern for fast detection"""
        pause_list = '|'.join(re.escape(token) for token in self.PAUSE_TOKENS)
        return re.compile(f'({pause_list})', re.IGNORECASE)
    
    def _update_memory_tracking(self, text: str, operation: str = "add") -> None:
        """Update memory tracking with safety checks"""
        if not self.enable_memory_tracking:
            return
            
        text_bytes = len(text.encode('utf-8'))
        
        if operation == "add":
            self.current_memory_bytes += text_bytes
        elif operation == "subtract":
            self.current_memory_bytes = max(0, self.current_memory_bytes - text_bytes)
        elif operation == "reset":
            self.current_memory_bytes = 0
            
        # Update peak memory tracking
        self.metrics['memory_peak_bytes'] = max(
            self.metrics['memory_peak_bytes'], 
            self.current_memory_bytes
        )
        
        # Safety check: prevent memory overflow
        if self.current_memory_bytes > self.MAX_MEMORY_MB * 1024 * 1024:
            self.logger.warning(f"Memory usage high: {self.current_memory_bytes / 1024 / 1024:.2f}MB")
            self._force_buffer_reset()
    
    def _force_buffer_reset(self) -> None:
        """Force buffer reset for memory safety"""
        self.logger.warning("Forcing buffer reset due to memory pressure")
        buffer_content = self.buffer
        self._reset_buffer()
        self.metrics['buffer_resets'] += 1
        
        # Return whatever was in buffer as emergency chunk
        if buffer_content.strip():
            return self._create_chunk(
                buffer_content.strip(),
                BoundaryType.CHARACTER_LIMIT,
                {"emergency_reset": True}
            )
    
    def _reset_buffer(self) -> None:
        """Properly reset buffer and update memory tracking"""
        if self.buffer:
            self._update_memory_tracking(self.buffer, "subtract")
        self.buffer = ""
        self.metrics['buffer_resets'] += 1
    
    def _create_chunk(self, text: str, boundary_type: BoundaryType, metadata: Dict[str, Any] = None) -> TextChunk:
        """Create a TextChunk with proper metadata and tracking"""
        if metadata is None:
            metadata = {}
        
        # Clean pause tokens from text (unless it's a pause token boundary)
        cleaned_text = text.strip()
        if boundary_type != BoundaryType.PAUSE_TOKEN:
            # For non-pause boundaries, clean any remaining pause tokens
            cleaned_text = self._clean_pause_tokens(cleaned_text)
        else:
            # For pause token boundaries, we already excluded the token, just clean any others
            cleaned_text = self._clean_pause_tokens(cleaned_text)
            
        # Calculate processing time (mock for now, will be set by caller)
        processing_time = 0.0
        
        chunk = TextChunk(
            text=cleaned_text,
            boundary_type=boundary_type,
            sequence_id=self.sequence_counter,
            metadata={
                'timestamp': time.time(),
                'buffer_size_before': len(self.buffer),
                'character_count': len(cleaned_text),
                'memory_bytes': self.current_memory_bytes,
                **metadata
            },
            processing_time_ms=processing_time,
            character_count=len(cleaned_text)
        )
        
        self.sequence_counter += 1
        self.total_chunks_processed += 1
        
        return chunk
    
    def _is_abbreviation_ending(self, text: str) -> bool:
        """Check if text ends with an abbreviation (prosody safety)"""
        if not text:
            return False
            
        # Check if the end matches our abbreviation pattern
        match = self._abbreviation_pattern.search(text.lower())
        if match:
            self.metrics['abbreviation_saves'] += 1
            return True
        return False
    
    def _find_pause_tokens(self, text: str) -> List[Tuple[int, str]]:
        """Find pause tokens in text with positions"""
        pause_positions = []
        for match in self._pause_token_pattern.finditer(text):
            pause_positions.append((match.start(), match.group()))
        return pause_positions
    
    def _find_sentence_boundaries(self, text: str) -> List[int]:
        """Find sentence boundaries with abbreviation safety"""
        boundaries = []
        
        for match in self.SENTENCE_ENDINGS.finditer(text):
            end_pos = match.end()
            
            # Extract text up to this potential boundary
            text_up_to_boundary = text[:end_pos].strip()
            
            # Skip if this ends with an abbreviation
            if not self._is_abbreviation_ending(text_up_to_boundary):
                boundaries.append(end_pos)
                
        return boundaries
    
    def _should_force_boundary(self, current_text: str) -> bool:
        """Determine if we should force a boundary due to length"""
        return len(current_text) >= self.MAX_CHUNK_LENGTH
    
    def _find_optimal_break_point(self, text: str, max_pos: int) -> Tuple[int, BoundaryType]:
        """Find the optimal break point within the given range"""
        # First, look for pause tokens
        pause_positions = self._find_pause_tokens(text[:max_pos])
        if pause_positions:
            # Take the last pause token within range
            last_pause_pos, pause_token = pause_positions[-1]
            self.metrics['pause_token_breaks'] += 1
            return last_pause_pos + len(pause_token), BoundaryType.PAUSE_TOKEN
        
        # Next, look for sentence boundaries
        sentence_boundaries = self._find_sentence_boundaries(text[:max_pos])
        if sentence_boundaries:
            return sentence_boundaries[-1], BoundaryType.SENTENCE_END
        
        # Finally, look for word boundaries as last resort
        words = text[:max_pos].split()
        if len(words) > 1:
            # Find the last complete word within range
            word_boundary = len(' '.join(words[:-1]))
            if word_boundary > self.MIN_CHUNK_LENGTH:
                self.metrics['character_limit_breaks'] += 1
                return word_boundary, BoundaryType.CHARACTER_LIMIT
        
        # Worst case: break at character limit
        self.metrics['character_limit_breaks'] += 1
        return max_pos, BoundaryType.CHARACTER_LIMIT
    
    def add_text(self, new_text: str) -> List[TextChunk]:
        """
        Add new text to buffer and return any completed chunks.
        
        Args:
            new_text: New text to process
            
        Returns:
            List of completed TextChunk objects ready for TTS
            
        Performance Target: <5ms per call
        """
        start_time = time.perf_counter()
        chunks = []
        
        try:
            # Add new text to buffer
            self.buffer += new_text
            self._update_memory_tracking(new_text, "add")
            
            # Safety check: prevent buffer overflow
            if len(self.buffer) > self.MAX_BUFFER_SIZE:
                # Force process everything in buffer
                emergency_chunk = self._force_buffer_reset()
                if emergency_chunk:
                    chunks.append(emergency_chunk)
                return chunks
            
            # Process buffer for complete chunks
            while self.buffer:
                processed_chunk = False
                
                # Check for natural sentence boundaries first
                sentence_boundaries = self._find_sentence_boundaries(self.buffer)
                
                if sentence_boundaries:
                    # Process the first complete sentence
                    boundary_pos = sentence_boundaries[0]
                    chunk_text = self.buffer[:boundary_pos].strip()
                    
                    # Create chunk even if shorter than minimum for sentence boundaries
                    if len(chunk_text) >= 10:  # Very minimal length check for sentences
                        # Create chunk and update buffer
                        chunk = self._create_chunk(chunk_text, BoundaryType.SENTENCE_END)
                        chunks.append(chunk)
                        
                        # Update buffer (remove processed text)
                        self._update_memory_tracking(self.buffer[:boundary_pos], "subtract")
                        self.buffer = self.buffer[boundary_pos:].lstrip()
                        processed_chunk = True
                
                # Check for pause tokens if no sentence boundary processed
                if not processed_chunk:
                    pause_positions = self._find_pause_tokens(self.buffer)
                    if pause_positions:
                        pos, token = pause_positions[0]
                        # Include the pause token position but clean it from final text
                        chunk_end = pos + len(token)
                        chunk_text = self.buffer[:pos].strip()  # Exclude the pause token from final text
                        
                        if len(chunk_text) >= 10:  # Minimal check for pause tokens
                            chunk = self._create_chunk(chunk_text, BoundaryType.PAUSE_TOKEN)
                            chunks.append(chunk)
                            
                            # Update buffer (remove processed text including pause token)
                            self._update_memory_tracking(self.buffer[:chunk_end], "subtract")
                            self.buffer = self.buffer[chunk_end:].lstrip()
                            self.metrics['pause_token_breaks'] += 1
                            processed_chunk = True
                
                # Check if we need to force a boundary due to length
                if not processed_chunk and self._should_force_boundary(self.buffer):
                    break_pos, boundary_type = self._find_optimal_break_point(
                        self.buffer, 
                        self.MAX_CHUNK_LENGTH
                    )
                    
                    chunk_text = self.buffer[:break_pos].strip()
                    if chunk_text:
                        chunk = self._create_chunk(chunk_text, boundary_type)
                        chunks.append(chunk)
                        
                        # Update buffer
                        self._update_memory_tracking(self.buffer[:break_pos], "subtract")
                        self.buffer = self.buffer[break_pos:].lstrip()
                        processed_chunk = True
                
                # If no processing happened, break to avoid infinite loop
                if not processed_chunk:
                    break
                    
        except Exception as e:
            self.logger.error(f"Error in add_text: {e}")
            # Emergency cleanup
            self._force_buffer_reset()
            
        finally:
            # Update performance metrics
            processing_time_ms = (time.perf_counter() - start_time) * 1000
            self.total_processing_time_ms += processing_time_ms
            self.metrics['chunks_processed'] += len(chunks)
            
            if self.metrics['chunks_processed'] > 0:
                self.metrics['avg_processing_time_ms'] = (
                    self.total_processing_time_ms / self.metrics['chunks_processed']
                )
            
            # Update chunk processing times
            for chunk in chunks:
                chunk.processing_time_ms = processing_time_ms / len(chunks) if chunks else 0
            
            # Performance warning (but only for very slow processing)
            if processing_time_ms > 20.0:  # More lenient for development
                self.logger.warning(
                    f"Text processing exceeded 20ms: {processing_time_ms:.2f}ms"
                )
        
        return chunks
    
    def _clean_pause_tokens(self, text: str) -> str:
        """Remove pause tokens from text while preserving other content"""
        cleaned_text = text
        for token in self.PAUSE_TOKENS:
            cleaned_text = cleaned_text.replace(token, ' ')
        # Clean up multiple spaces
        return ' '.join(cleaned_text.split())
    
    def flush_buffer(self) -> Optional[TextChunk]:
        """
        Flush any remaining text in buffer as final chunk.
        Call this when no more text will be added.
        
        Returns:
            Final TextChunk if buffer contains text, None otherwise
        """
        if not self.buffer.strip():
            return None
            
        # Clean pause tokens from final text
        chunk_text = self._clean_pause_tokens(self.buffer.strip())
        
        if not chunk_text.strip():  # If nothing left after cleaning
            return None
            
        chunk = self._create_chunk(
            chunk_text, 
            BoundaryType.CHARACTER_LIMIT,
            {"is_final_chunk": True}
        )
        
        self._reset_buffer()
        self._update_memory_tracking("", "reset")
        
        return chunk
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get detailed processing metrics for monitoring"""
        return {
            **self.metrics,
            'buffer_size_chars': len(self.buffer),
            'current_memory_bytes': self.current_memory_bytes,
            'current_memory_mb': self.current_memory_bytes / 1024 / 1024,
            'sequence_counter': self.sequence_counter,
            'total_chunks_processed': self.total_chunks_processed,
            'avg_processing_time_ms': self.metrics['avg_processing_time_ms']
        }
    
    def reset(self) -> None:
        """Reset processor state (useful for new conversations)"""
        self._reset_buffer()
        self.sequence_counter = 0
        self.total_chunks_processed = 0
        self.total_processing_time_ms = 0.0
        self._update_memory_tracking("", "reset")
        
        # Reset metrics but keep peak memory for reference
        peak_memory = self.metrics['memory_peak_bytes']
        self.metrics = {
            'chunks_processed': 0,
            'avg_processing_time_ms': 0.0,
            'buffer_resets': 0,
            'abbreviation_saves': 0,
            'pause_token_breaks': 0,
            'character_limit_breaks': 0,
            'memory_peak_bytes': peak_memory
        }


# Performance testing helper
def benchmark_text_processor(test_text: str, iterations: int = 100) -> Dict[str, float]:
    """Benchmark the text processor performance"""
    processor = SmartTextProcessor()
    
    start_time = time.perf_counter()
    
    for _ in range(iterations):
        processor.reset()
        chunks = processor.add_text(test_text)
        final_chunk = processor.flush_buffer()
    
    end_time = time.perf_counter()
    
    avg_time_ms = ((end_time - start_time) / iterations) * 1000
    
    return {
        'avg_processing_time_ms': avg_time_ms,
        'target_met': avg_time_ms < 5.0,
        'iterations': iterations,
        'test_text_length': len(test_text)
    } 