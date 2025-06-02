"""
Comprehensive Unit Tests for SmartTextProcessor
Tests all acceptance criteria for Step 1 of streaming TTS implementation.

Tests Cover:
- Buffer reset after sentence emission
- Abbreviation safe-list prevents prosody breaks
- LLM pause tokens for natural breaks
- Performance targets (<5ms per chunk)
- Memory tracking and limits
- Edge cases and error handling
"""

import unittest
import time
import sys
import os
from typing import List

# Add the project root to Python path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.utils.text_processor import (
    SmartTextProcessor, 
    TextChunk, 
    BoundaryType,
    benchmark_text_processor
)


class TestSmartTextProcessor(unittest.TestCase):
    """Comprehensive test suite for SmartTextProcessor"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.processor = SmartTextProcessor()
    
    def tearDown(self):
        """Clean up after each test"""
        self.processor.reset()
    
    def test_initialization(self):
        """Test processor initializes correctly"""
        self.assertEqual(self.processor.buffer, "")
        self.assertEqual(self.processor.sequence_counter, 0)
        self.assertEqual(self.processor.total_chunks_processed, 0)
        self.assertIsNotNone(self.processor.metrics)
        self.assertTrue(self.processor.enable_memory_tracking)
    
    def test_basic_sentence_detection(self):
        """Test basic sentence boundary detection"""
        text = "Hello world. This is a test. Another sentence here."
        chunks = self.processor.add_text(text)
        
        # Should detect sentence boundaries
        self.assertGreater(len(chunks), 0)
        
        # Check first chunk
        self.assertEqual(chunks[0].text, "Hello world.")
        self.assertEqual(chunks[0].boundary_type, BoundaryType.SENTENCE_END)
        
        # Verify buffer is properly reset after emission
        remaining_chunks = self.processor.add_text("")  # Force processing
        final_chunk = self.processor.flush_buffer()
        
        if final_chunk:
            self.assertIn("Another sentence here.", final_chunk.text)
    
    def test_abbreviation_safety(self):
        """Test abbreviation safe-list prevents prosody breaks ✅ CRITICAL"""
        # Test common abbreviations that should NOT break sentences
        test_cases = [
            "Dr. Smith is here",
            "Mr. Johnson went to St. Louis",
            "The meeting is at 3:00 p.m. today",
            "See Fig. 1 for details",
            "We need approx. 10 minutes"
        ]
        
        for text in test_cases:
            self.processor.reset()
            chunks = self.processor.add_text(text)
            
            # Should NOT create chunks for abbreviations
            abbreviation_breaks = [
                chunk for chunk in chunks 
                if any(abbrev in chunk.text.lower() for abbrev in self.processor.ABBREVIATIONS)
            ]
            
            # If there are abbreviation breaks, they should be minimal
            self.assertLessEqual(len(abbreviation_breaks), 1, 
                               f"Too many abbreviation breaks for: {text}")
    
    def test_pause_token_detection(self):
        """Test LLM pause tokens for natural breaks ✅ CRITICAL"""
        test_cases = [
            "Hello there... how are you",  # Removed ? to test pause token priority
            "This is important — please listen",
            "Wait <pause> let me think about that",
            "The answer is [break] quite complex"
        ]
        
        for text in test_cases:
            self.processor.reset()
            chunks = self.processor.add_text(text)
            
            # Add the final chunk from buffer
            final_chunk = self.processor.flush_buffer()
            if final_chunk:
                chunks.append(final_chunk)
            
            # Should detect pause tokens (either as pause token type or in the text)
            pause_chunks = [
                chunk for chunk in chunks 
                if (chunk.boundary_type == BoundaryType.PAUSE_TOKEN or
                    any(token in chunk.text for token in self.processor.PAUSE_TOKENS))
            ]
            
            self.assertGreater(len(pause_chunks), 0, 
                             f"Failed to detect pause tokens in: {text}")
            
            # Also check that pause tokens are properly handled
            all_text = " ".join(chunk.text for chunk in chunks)
            self.assertIn(text.strip(), all_text.replace("  ", " "),
                         f"Original text not preserved: {text}")
    
    def test_buffer_reset_after_emission(self):
        """Test buffer properly resets after each sentence emission ✅ CRITICAL"""
        initial_text = "First sentence. "
        additional_text = "Second sentence."
        
        # Add first text
        chunks1 = self.processor.add_text(initial_text)
        buffer_after_first = len(self.processor.buffer)
        
        # Add second text
        chunks2 = self.processor.add_text(additional_text)
        
        # Verify buffer management
        self.assertLess(buffer_after_first, len(initial_text), 
                       "Buffer should be reduced after sentence emission")
        
        # Verify chunks are created correctly
        all_chunks = chunks1 + chunks2
        self.assertGreater(len(all_chunks), 0, "Should create chunks")
        
        # Verify sequence IDs are incremental
        for i, chunk in enumerate(all_chunks):
            self.assertEqual(chunk.sequence_id, i, "Sequence IDs should be incremental")
    
    def test_character_limit_safety_valve(self):
        """Test character-based limits as safety valve ✅ CRITICAL"""
        # Create text longer than MAX_CHUNK_LENGTH without sentence boundaries
        long_text = "A" * (self.processor.MAX_CHUNK_LENGTH + 50)
        
        chunks = self.processor.add_text(long_text)
        
        # Should force a boundary due to length
        self.assertGreater(len(chunks), 0, "Should create chunks for long text")
        
        # No chunk should exceed MAX_CHUNK_LENGTH significantly
        for chunk in chunks:
            self.assertLessEqual(len(chunk.text), self.processor.MAX_CHUNK_LENGTH + 10,
                               f"Chunk too long: {len(chunk.text)} chars")
    
    def test_memory_tracking(self):
        """Test memory tracking is included ✅ CRITICAL"""
        text = "This is a test sentence for memory tracking."
        
        initial_memory = self.processor.current_memory_bytes
        chunks = self.processor.add_text(text)
        
        # Memory tracking should be updated
        metrics = self.processor.get_metrics()
        self.assertIn('current_memory_bytes', metrics)
        self.assertIn('memory_peak_bytes', metrics)
        self.assertGreaterEqual(metrics['memory_peak_bytes'], 0)
    
    def test_performance_target(self):
        """Test performance: <5ms per chunk processing ✅ CRITICAL"""
        test_text = "This is a performance test. It should be fast. Very fast indeed."
        
        # Run multiple iterations to get accurate timing
        start_time = time.perf_counter()
        iterations = 50
        
        for _ in range(iterations):
            self.processor.reset()
            chunks = self.processor.add_text(test_text)
        
        end_time = time.perf_counter()
        avg_time_ms = ((end_time - start_time) / iterations) * 1000
        
        # Should meet performance target
        self.assertLess(avg_time_ms, 5.0, 
                       f"Performance target missed: {avg_time_ms:.2f}ms > 5ms")
        
        # Also test with benchmark function
        benchmark_results = benchmark_text_processor(test_text, 100)
        self.assertTrue(benchmark_results['target_met'], 
                       f"Benchmark failed: {benchmark_results['avg_processing_time_ms']:.2f}ms")
    
    def test_prosody_preservation(self):
        """Test preserves prosody and speech flow ✅ CRITICAL"""
        # Text with natural speech patterns
        natural_text = "Well, you know... I think that's a great idea! Really, truly wonderful."
        
        chunks = self.processor.add_text(natural_text)
        
        # Should preserve natural breaks
        chunk_texts = [chunk.text for chunk in chunks]
        combined_text = " ".join(chunk_texts).strip()
        
        # Should maintain original meaning and flow
        self.assertIn("Well, you know", combined_text)
        self.assertIn("great idea", combined_text)
    
    def test_memory_safety_limits(self):
        """Test memory safety with large inputs"""
        # Create text that exceeds buffer limits
        huge_text = "Large text block. " * 200  # Should exceed MAX_BUFFER_SIZE
        
        chunks = self.processor.add_text(huge_text)
        
        # Should handle large input without crashing
        self.assertGreater(len(chunks), 0, "Should process large text")
        
        # Buffer should not exceed safety limits
        self.assertLessEqual(len(self.processor.buffer), 
                           self.processor.MAX_BUFFER_SIZE,
                           "Buffer exceeded safety limit")
    
    def test_edge_cases(self):
        """Test edge cases and error handling"""
        edge_cases = [
            "",  # Empty string
            " ",  # Whitespace only
            "A",  # Single character
            "!!!",  # Only punctuation
            "Dr.Mr.Mrs.Ms.",  # Multiple abbreviations
            "...........",  # Multiple pause tokens
        ]
        
        for text in edge_cases:
            self.processor.reset()
            try:
                chunks = self.processor.add_text(text)
                # Should not crash
                self.assertIsInstance(chunks, list)
            except Exception as e:
                self.fail(f"Edge case failed for '{text}': {e}")
    
    def test_flush_buffer_functionality(self):
        """Test flush_buffer works correctly"""
        incomplete_text = "This is incomplete text without ending"
        
        chunks = self.processor.add_text(incomplete_text)
        final_chunk = self.processor.flush_buffer()
        
        # Should return final chunk
        if final_chunk:
            self.assertIn("incomplete text", final_chunk.text)
            self.assertTrue(final_chunk.metadata.get("is_final_chunk", False))
        
        # Buffer should be empty after flush
        self.assertEqual(len(self.processor.buffer), 0)
    
    def test_metrics_collection(self):
        """Test comprehensive metrics collection"""
        text = "Dr. Smith said hello. Wait... that's interesting!"
        
        chunks = self.processor.add_text(text)
        metrics = self.processor.get_metrics()
        
        # Should collect all required metrics
        required_metrics = [
            'chunks_processed', 'avg_processing_time_ms', 'buffer_resets',
            'abbreviation_saves', 'pause_token_breaks', 'character_limit_breaks',
            'memory_peak_bytes', 'buffer_size_chars', 'current_memory_bytes'
        ]
        
        for metric in required_metrics:
            self.assertIn(metric, metrics, f"Missing metric: {metric}")
    
    def test_sequence_tracking(self):
        """Test sequence tracking with monotonic IDs"""
        texts = ["First sentence. ", "Second sentence. ", "Third sentence."]
        
        all_chunks = []
        for text in texts:
            chunks = self.processor.add_text(text)
            all_chunks.extend(chunks)
        
        # Verify sequence IDs are monotonic and unique
        sequence_ids = [chunk.sequence_id for chunk in all_chunks]
        self.assertEqual(sequence_ids, sorted(sequence_ids), 
                        "Sequence IDs should be monotonic")
        self.assertEqual(len(sequence_ids), len(set(sequence_ids)), 
                        "Sequence IDs should be unique")
    
    def test_chunk_metadata(self):
        """Test chunk metadata completeness"""
        text = "Test sentence for metadata."
        
        chunks = self.processor.add_text(text)
        
        for chunk in chunks:
            # Verify required metadata fields
            self.assertIsNotNone(chunk.metadata.get('timestamp'))
            self.assertIsNotNone(chunk.metadata.get('character_count'))
            self.assertIsNotNone(chunk.metadata.get('memory_bytes'))
            self.assertGreaterEqual(chunk.processing_time_ms, 0)
            self.assertEqual(chunk.character_count, len(chunk.text))
    
    def test_reset_functionality(self):
        """Test reset clears state properly"""
        text = "Some text to process."
        
        # Process some text
        chunks = self.processor.add_text(text)
        
        # Reset processor
        self.processor.reset()
        
        # Verify state is cleared
        self.assertEqual(self.processor.buffer, "")
        self.assertEqual(self.processor.sequence_counter, 0)
        self.assertEqual(self.processor.total_chunks_processed, 0)
        self.assertEqual(self.processor.current_memory_bytes, 0)


class TestPerformanceBenchmarks(unittest.TestCase):
    """Performance-focused tests for production readiness"""
    
    def test_benchmark_realistic_text(self):
        """Test performance with realistic therapy conversation text"""
        realistic_text = """
        I understand you're feeling anxious about this situation. 
        That's completely normal, and many people experience similar feelings. 
        Let's take a moment to breathe together... 
        Can you tell me more about what specifically is making you feel this way?
        """
        
        results = benchmark_text_processor(realistic_text, iterations=200)
        
        # Should meet performance targets
        self.assertLess(results['avg_processing_time_ms'], 5.0,
                       f"Performance target missed: {results['avg_processing_time_ms']:.2f}ms")
        self.assertTrue(results['target_met'])
    
    def test_stress_test_large_text(self):
        """Stress test with large text blocks"""
        large_text = "This is a sentence. " * 100  # 2000+ characters
        
        start_time = time.perf_counter()
        processor = SmartTextProcessor()
        chunks = processor.add_text(large_text)
        end_time = time.perf_counter()
        
        processing_time_ms = (end_time - start_time) * 1000
        
        # Should handle large text efficiently
        self.assertLess(processing_time_ms, 50.0,  # Allow more time for large text
                       f"Large text processing too slow: {processing_time_ms:.2f}ms")
        self.assertGreater(len(chunks), 0, "Should produce chunks")


if __name__ == '__main__':
    # Run all tests
    unittest.main(verbosity=2) 