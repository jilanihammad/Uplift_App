# app/utils/wav_header_debug.py

import struct
import logging
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

class WavHeaderDebug:
    """Utility class for debugging WAV file headers and RIFF chunk issues."""
    
    @staticmethod
    def analyze_wav_header(audio_data: bytes) -> Dict[str, Any]:
        """
        Analyze WAV header and return detailed information about its structure.
        
        Args:
            audio_data: Raw audio bytes
            
        Returns:
            Dictionary containing header analysis
        """
        if len(audio_data) < 44:
            return {"error": "Audio data too short for WAV header", "length": len(audio_data)}
        
        try:
            # RIFF Header (bytes 0-11)
            riff_signature = audio_data[0:4].decode('ascii')
            riff_chunk_size = struct.unpack('<I', audio_data[4:8])[0]  # Little-endian 32-bit
            wave_signature = audio_data[8:12].decode('ascii')
            
            # fmt Chunk (bytes 12-35)
            fmt_signature = audio_data[12:16].decode('ascii')
            fmt_chunk_size = struct.unpack('<I', audio_data[16:20])[0]
            audio_format = struct.unpack('<H', audio_data[20:22])[0]
            num_channels = struct.unpack('<H', audio_data[22:24])[0]
            sample_rate = struct.unpack('<I', audio_data[24:28])[0]
            byte_rate = struct.unpack('<I', audio_data[28:32])[0]
            block_align = struct.unpack('<H', audio_data[32:34])[0]
            bits_per_sample = struct.unpack('<H', audio_data[34:36])[0]
            
            # data Chunk (bytes 36-43)
            data_signature = audio_data[36:40].decode('ascii')
            data_chunk_size = struct.unpack('<I', audio_data[40:44])[0]
            
            # Calculate expected values
            actual_file_size = len(audio_data)
            expected_riff_chunk_size = actual_file_size - 8
            actual_data_size = actual_file_size - 44
            
            # Check for common issues
            issues = []
            if riff_chunk_size == 0xFFFFFFFF:
                issues.append("RIFF chunk size is 0xFFFFFFFF (invalid streaming placeholder)")
            if data_chunk_size == 0xFFFFFFFF:
                issues.append("Data chunk size is 0xFFFFFFFF (invalid streaming placeholder)")
            if riff_chunk_size != expected_riff_chunk_size:
                issues.append(f"RIFF chunk size mismatch: {riff_chunk_size} vs expected {expected_riff_chunk_size}")
            if data_chunk_size != actual_data_size:
                issues.append(f"Data chunk size mismatch: {data_chunk_size} vs expected {actual_data_size}")
            
            return {
                "file_size": actual_file_size,
                "riff_signature": riff_signature,
                "riff_chunk_size": riff_chunk_size,
                "riff_chunk_size_hex": f"0x{riff_chunk_size:08X}",
                "expected_riff_chunk_size": expected_riff_chunk_size,
                "wave_signature": wave_signature,
                "fmt_signature": fmt_signature,
                "fmt_chunk_size": fmt_chunk_size,
                "audio_format": audio_format,
                "num_channels": num_channels,
                "sample_rate": sample_rate,
                "byte_rate": byte_rate,
                "block_align": block_align,
                "bits_per_sample": bits_per_sample,
                "data_signature": data_signature,
                "data_chunk_size": data_chunk_size,
                "data_chunk_size_hex": f"0x{data_chunk_size:08X}",
                "actual_data_size": actual_data_size,
                "header_valid": WavHeaderDebug._is_header_valid(riff_signature, wave_signature, fmt_signature, data_signature),
                "issues": issues,
                "has_critical_issues": len(issues) > 0
            }
            
        except Exception as e:
            return {"error": f"Failed to parse WAV header: {str(e)}"}
    
    @staticmethod
    def _is_header_valid(riff: str, wave: str, fmt: str, data: str) -> bool:
        """Check if WAV header signatures are valid."""
        return riff == 'RIFF' and wave == 'WAVE' and fmt == 'fmt ' and data == 'data'
    
    @staticmethod
    def fix_wav_header(audio_data: bytes) -> bytes:
        """
        Fix WAV header issues, particularly the 0xFFFFFFFF chunk size problem.
        
        Args:
            audio_data: Original audio bytes with potentially invalid header
            
        Returns:
            Audio bytes with corrected header
        """
        if len(audio_data) < 44:
            logger.warning(f"Audio data too short for WAV header: {len(audio_data)} bytes")
            return audio_data
        
        # Check if this is a WAV file
        if audio_data[0:4] != b'RIFF':
            logger.warning("Not a RIFF/WAV file, skipping header fix")
            return audio_data
        
        # Create a mutable copy
        fixed_data = bytearray(audio_data)
        
        actual_file_size = len(audio_data)
        correct_riff_chunk_size = actual_file_size - 8
        correct_data_size = actual_file_size - 44
        
        # Read current values
        current_riff_chunk_size = struct.unpack('<I', audio_data[4:8])[0]
        current_data_chunk_size = struct.unpack('<I', audio_data[40:44])[0]
        
        logger.info(f"WAV header fix: file_size={actual_file_size}, "
                   f"current_riff_chunk_size=0x{current_riff_chunk_size:08X}, "
                   f"current_data_chunk_size=0x{current_data_chunk_size:08X}")
        
        # Fix RIFF chunk size if invalid
        if current_riff_chunk_size == 0xFFFFFFFF or current_riff_chunk_size != correct_riff_chunk_size:
            logger.info(f"Fixing RIFF chunk size: 0x{current_riff_chunk_size:08X} -> {correct_riff_chunk_size}")
            struct.pack_into('<I', fixed_data, 4, correct_riff_chunk_size)
        
        # Fix data chunk size if invalid  
        if current_data_chunk_size == 0xFFFFFFFF or current_data_chunk_size != correct_data_size:
            logger.info(f"Fixing data chunk size: 0x{current_data_chunk_size:08X} -> {correct_data_size}")
            struct.pack_into('<I', fixed_data, 40, correct_data_size)
        
        return bytes(fixed_data)
    
    @staticmethod
    def log_wav_header_analysis(audio_data: bytes, context: str = ""):
        """Log detailed WAV header analysis for debugging."""
        analysis = WavHeaderDebug.analyze_wav_header(audio_data)
        
        context_prefix = f"[{context}] " if context else ""
        logger.info(f"{context_prefix}WAV Header Analysis:")
        
        if "error" in analysis:
            logger.error(f"{context_prefix}  ERROR: {analysis['error']}")
            return
        
        logger.info(f"{context_prefix}  File size: {analysis['file_size']} bytes")
        logger.info(f"{context_prefix}  RIFF signature: {analysis['riff_signature']}")
        logger.info(f"{context_prefix}  RIFF chunk size: {analysis['riff_chunk_size']} ({analysis['riff_chunk_size_hex']})")
        logger.info(f"{context_prefix}  Expected RIFF chunk size: {analysis['expected_riff_chunk_size']}")
        logger.info(f"{context_prefix}  Data chunk size: {analysis['data_chunk_size']} ({analysis['data_chunk_size_hex']})")
        logger.info(f"{context_prefix}  Actual data size: {analysis['actual_data_size']}")
        logger.info(f"{context_prefix}  Audio format: {analysis['audio_format']} (PCM={analysis['audio_format']==1})")
        logger.info(f"{context_prefix}  Sample rate: {analysis['sample_rate']} Hz")
        logger.info(f"{context_prefix}  Channels: {analysis['num_channels']}")
        logger.info(f"{context_prefix}  Bits per sample: {analysis['bits_per_sample']}")
        logger.info(f"{context_prefix}  Header valid: {analysis['header_valid']}")
        
        if analysis['issues']:
            logger.warning(f"{context_prefix}  Issues found:")
            for issue in analysis['issues']:
                logger.warning(f"{context_prefix}    - {issue}")
        else:
            logger.info(f"{context_prefix}  No issues found")
    
    @staticmethod
    def is_wav_file(audio_data: bytes) -> bool:
        """Check if the audio data is a WAV file."""
        return len(audio_data) >= 12 and audio_data[0:4] == b'RIFF' and audio_data[8:12] == b'WAVE'
    
    @staticmethod
    def has_invalid_chunk_size(audio_data: bytes) -> bool:
        """Check if the WAV file has invalid chunk sizes (0xFFFFFFFF)."""
        if not WavHeaderDebug.is_wav_file(audio_data) or len(audio_data) < 44:
            return False
        
        riff_chunk_size = struct.unpack('<I', audio_data[4:8])[0]
        data_chunk_size = struct.unpack('<I', audio_data[40:44])[0]
        
        return riff_chunk_size == 0xFFFFFFFF or data_chunk_size == 0xFFFFFFFF