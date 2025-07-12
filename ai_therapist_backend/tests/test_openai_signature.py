"""
Test to validate OpenAI API signature matches our expectations.
Ensures we're using correct parameter names (response_format vs format).
"""

import inspect
import pytest
from openai import OpenAI
from openai.resources.audio import Speech


def test_openai_tts_signature():
    """Verify the OpenAI TTS API signature matches our parameter usage."""
    # Get the create method signature
    sig = inspect.signature(Speech.create)
    
    # Verify response_format is supported (correct parameter name)
    assert "response_format" in sig.parameters, "OpenAI TTS should accept 'response_format' parameter"
    
    # Verify format is NOT supported (incorrect parameter name that we fixed)
    assert "format" not in sig.parameters, "OpenAI TTS should NOT accept 'format' parameter - use 'response_format'"
    
    # Verify other critical parameters are present
    assert "model" in sig.parameters, "OpenAI TTS should accept 'model' parameter"
    assert "input" in sig.parameters, "OpenAI TTS should accept 'input' parameter"
    assert "voice" in sig.parameters, "OpenAI TTS should accept 'voice' parameter"


def test_openai_streaming_tts_signature():
    """Verify the OpenAI streaming TTS API signature."""
    # For streaming, we use with_streaming_response.create()
    # The parameters should be the same as the regular create method
    client = OpenAI(api_key="test-key")
    streaming_method = client.audio.speech.with_streaming_response.create
    
    # Get the create method signature through the streaming wrapper
    sig = inspect.signature(streaming_method)
    
    # Verify critical parameters are present
    assert "model" in sig.parameters, "Streaming TTS should accept 'model' parameter"
    assert "input" in sig.parameters, "Streaming TTS should accept 'input' parameter"
    assert "voice" in sig.parameters, "Streaming TTS should accept 'voice' parameter"
    assert "response_format" in sig.parameters, "Streaming TTS should accept 'response_format' parameter"


if __name__ == "__main__":
    test_openai_tts_signature()
    test_openai_streaming_tts_signature()
    print("✅ All OpenAI API signature tests passed!")