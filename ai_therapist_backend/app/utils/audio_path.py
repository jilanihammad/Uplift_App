"""
Audio path utilities for consistent file extension handling.

This module provides utilities to prevent double extension bugs (e.g., .wav.wav)
by centralizing audio file extension logic.
"""

import os
from typing import Optional


def ensure_wav(path_or_name: str) -> str:
    """
    Ensures a path or filename has a .wav extension.
    
    Args:
        path_or_name: File path or filename that may or may not have .wav extension
        
    Returns:
        Path or filename with .wav extension guaranteed
        
    Raises:
        ValueError: If input is empty or whitespace-only
        
    Examples:
        ensure_wav("audio_file") -> "audio_file.wav"
        ensure_wav("audio_file.wav") -> "audio_file.wav"
        ensure_wav("/path/to/audio_file") -> "/path/to/audio_file.wav"
        ensure_wav("/path/to/audio_file.wav") -> "/path/to/audio_file.wav"
    """
    if not path_or_name or not path_or_name.strip():
        raise ValueError("Empty audio filename not allowed")
    
    # Handle both paths and filenames consistently
    return path_or_name if path_or_name.lower().endswith('.wav') else f'{path_or_name}.wav'


def ensure_basename_no_extension(basename: str) -> str:
    """
    Validates that a basename contains no file extensions.
    
    This is a safety check to ensure basenames are clean before
    applying ensure_wav() to prevent double extensions.
    
    Args:
        basename: The base filename to validate
        
    Returns:
        The same basename if valid
        
    Raises:
        ValueError: If basename contains dots (indicating extensions)
        
    Examples:
        ensure_basename_no_extension("audio_file") -> "audio_file"
        ensure_basename_no_extension("audio_file.wav") -> raises ValueError
    """
    if '.' in basename:
        raise ValueError(f"Basename should not contain extensions: {basename}")
    return basename


def safe_audio_path(directory: str, basename: str, extension: str = "wav") -> str:
    """
    Safely constructs an audio file path with guaranteed single extension.
    
    Args:
        directory: Directory path
        basename: Base filename without extension
        extension: File extension (default: "wav")
        
    Returns:
        Full path with single extension
        
    Raises:
        ValueError: If basename contains dots or inputs are invalid
        
    Examples:
        safe_audio_path("/tmp", "audio", "wav") -> "/tmp/audio.wav"
        safe_audio_path("/tmp", "audio.wav", "wav") -> raises ValueError
    """
    if not directory or not basename:
        raise ValueError("Directory and basename are required")
    
    # Validate basename has no extensions
    ensure_basename_no_extension(basename)
    
    # Construct path with single extension
    filename = f"{basename}.{extension.lower()}"
    return os.path.join(directory, filename)