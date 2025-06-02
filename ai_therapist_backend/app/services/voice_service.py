# app/services/voice_service.py (Updated for OpenAI TTS)

import logging
from typing import Optional
import requests
import os
import uuid
import traceback

from app.core.config import settings

logger = logging.getLogger(__name__)

class VoiceService:
    def __init__(self):
        try:
            # Initialize with LLMManager for unified AI operations
            from app.services.llm_manager import llm_manager
            self.llm_manager = llm_manager
            
            # Check if TTS is available through LLMManager
            from app.core.llm_config import LLMConfig, ModelType
            self.available = LLMConfig.is_model_available(ModelType.TTS)
            
            # Use /tmp in Cloud Run, otherwise use static/audio
            if os.environ.get("GOOGLE_CLOUD") == "1":
                logger.info("Running in Cloud Run environment, using /tmp for audio storage")
                self.audio_dir = "/tmp/static/audio"
            else:
                self.audio_dir = "static/audio"
                
            # Ensure audio directory exists
            os.makedirs(self.audio_dir, exist_ok=True)
            logger.info(f"[TTS] Audio directory: {self.audio_dir}")
            
            # Create a fallback audio file if it doesn't exist
            self._create_fallback_audio()
            
            # Get TTS configuration from LLMManager
            tts_config = self.llm_manager.tts_config
            if tts_config:
                logger.info(f"VoiceService initialized with LLMManager:")
                logger.info(f"TTS Provider: {tts_config.provider}")
                logger.info(f"TTS Model: {tts_config.model_id}")
                logger.info(f"Default Voice: {tts_config.default_params.get('voice', 'sage')}")
            else:
                logger.warning("No TTS configuration found in LLMManager")
                
            logger.info(f"Service available: {'Yes' if self.available else 'No'}")
            logger.info(f"[TTS] Environment: {'Cloud Run' if os.environ.get('GOOGLE_CLOUD') == '1' else 'Local'}")
            
        except Exception as e:
            logger.error(f"Error initializing VoiceService: {str(e)}")
            logger.error(traceback.format_exc())
            
            # Set unavailable on error
            self.available = False
            self.llm_manager = None
            
            # Ensure audio directory exists even on error - use /tmp in Cloud Run
            if os.environ.get("GOOGLE_CLOUD") == "1":
                self.audio_dir = "/tmp/static/audio"
            else:
                self.audio_dir = "static/audio"
                
            os.makedirs(self.audio_dir, exist_ok=True)
            
            logger.warning("VoiceService unavailable - will return fallback responses")
    
    def _create_fallback_audio(self):
        """Create a valid fallback WAV file"""
        error_file = os.path.join(self.audio_dir, "error.wav")  # Changed to WAV
        logger.info(f"[TTS] Checking for fallback audio at: {error_file}")
        if os.path.exists(error_file) and os.path.getsize(error_file) > 1000:
            logger.info(f"[TTS] Fallback audio file already exists: {error_file}")
            return
            
        try:
            # Create a simple text file as fallback in Cloud Run
            with open(error_file, "wb") as f:
                f.write(b"This is a fallback audio file")
            logger.info(f"[TTS] Created simple fallback file: {error_file}")
        except Exception as e:
            logger.error(f"[TTS] Error creating fallback audio file: {str(e)}")
            logger.error(traceback.format_exc())
    
    async def generate_speech(self, text: str, format_params: dict = None) -> Optional[str]:
        """Generate speech from text and return the URL to the generated audio file"""
        logger.info(f"[TTS] generate_speech called. Text: '{text[:100]}'... Params: {format_params}")
        if not text:
            logger.error("[TTS] No text provided for speech generation")
            raise ValueError("No text provided for speech generation")
        if not self.available:
            logger.error("[TTS] Voice service unavailable - TTS not configured")
            raise ValueError("Voice service unavailable - TTS not configured")
            
        # Use LLMManager to generate speech
        try:
            # Get format extension - default to WAV for streaming TTS
            format_type = format_params.get("response_format", "wav") if format_params else "wav"
            extension = ".wav" if format_type == "wav" else f".{format_type}"
            
            # Generate a unique filename for the audio file
            filename = f"{uuid.uuid4()}{extension}"
            file_path = os.path.join(self.audio_dir, filename)
            logger.info(f"[TTS] Will save audio to: {file_path}")
            
            # Ensure the directory exists
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            
            # Use LLMManager's text_to_speech method
            # The LLMManager method returns base64-encoded audio data, not a boolean
            audio_b64 = await self.llm_manager.text_to_speech(
                text=text,
                output_file=file_path,
                response_format=format_type,
                voice=format_params.get("voice") if format_params else None
            )
            
            if audio_b64:
                # The LLMManager handles file creation internally
                logger.info(f"[TTS] TTS successful for file: {file_path}")
                
                if os.path.exists(file_path):
                    file_size = os.path.getsize(file_path)
                    logger.info(f"[TTS] Audio file saved: {file_path} ({file_size} bytes)")
                else:
                    # If file doesn't exist, LLMManager returned base64 data
                    # We need to save it ourselves
                    import base64
                    audio_bytes = base64.b64decode(audio_b64)
                    with open(file_path, 'wb') as f:
                        f.write(audio_bytes)
                    logger.info(f"[TTS] Audio file created from base64: {file_path} ({len(audio_bytes)} bytes)")
            else:
                logger.error(f"[TTS] TTS failed - no audio data returned")
                raise Exception("TTS generation failed - no audio data returned")
            
            # Return the URL to the audio file
            logger.info(f"[TTS] Returning audio URL to client: /audio/{filename}")
            return f"/audio/{filename}"
            
        except Exception as e:
            logger.error(f"[TTS] Error generating speech: {str(e)}")
            logger.error(traceback.format_exc())
            raise Exception(f"Speech generation failed: {str(e)}")
    
    def set_voice(self, voice_id: str) -> None:
        """
        Set the voice ID to use for speech generation.
        
        Args:
            voice_id: Voice ID for TTS API (depends on provider - e.g., OpenAI: alloy, echo, fable, onyx, nova, shimmer, sage)
        """
        try:
            logger.info(f"[TTS] set_voice called with: {voice_id}")
            
            if self.llm_manager and self.llm_manager.tts_config:
                # Update the voice in the TTS configuration's default parameters
                self.llm_manager.tts_config.default_params['voice'] = voice_id.lower()
                logger.info(f"[TTS] Voice set to: {voice_id.lower()}")
            else:
                logger.warning(f"[TTS] Cannot set voice - LLMManager or TTS config not available")
                
        except Exception as e:
            logger.error(f"[TTS] Error setting voice: {str(e)}")
            logger.error(traceback.format_exc())

    async def stream_speech(self, text: str, params: dict = None):
        """
        Stream speech audio chunks as they are generated by the TTS engine.
        Yields: bytes (audio chunk)
        """
        logger.info(f"[TTS] stream_speech called. Text: '{text[:100]}'... Params: {params}")
        if not text:
            logger.error("[TTS] No text provided for speech streaming")
            raise ValueError("No text provided for speech streaming")
        if not self.available:
            logger.error("[TTS] Voice service unavailable - TTS not configured")
            raise ValueError("Voice service unavailable - TTS not configured")

        try:
            # Extract parameters
            voice = params.get("voice") if params else None
            response_format = params.get("response_format", "wav") if params else "wav"
            
            logger.info(f"[TTS] Streaming with format: {response_format}, voice: {voice}")

            # Use LLMManager's stream_text_to_speech method
            async for b64_chunk in self.llm_manager.stream_text_to_speech(
                text=text,
                voice=voice,
                response_format=response_format
            ):
                if b64_chunk:
                    # Convert base64 back to bytes for streaming
                    import base64
                    audio_chunk = base64.b64decode(b64_chunk)
                    logger.info(f"[TTS] Streaming WAV audio chunk of size: {len(audio_chunk)} bytes")
                    yield audio_chunk
                    
        except Exception as e:
            logger.error(f"[TTS] Error in stream_speech: {str(e)}")
            logger.error(traceback.format_exc())
            raise

# Create a singleton instance
try:
    voice_service = VoiceService()
    logger.info("VoiceService initialized successfully with LLMManager")
except Exception as e:
    # Create a minimal service that throws errors
    logger.error(f"Failed to initialize VoiceService: {str(e)}")
    logger.error(traceback.format_exc())
    
    class FallbackVoiceService:
        """A service that throws errors instead of returning fallbacks"""
        async def generate_speech(self, text, format_params=None):
            raise Exception("Voice service unavailable - failed to initialize")
            
        def set_voice(self, voice_id):
            pass
            
        async def stream_speech(self, text, params=None):
            raise Exception("Voice streaming unavailable - failed to initialize")
    
    voice_service = FallbackVoiceService()
    logger.warning("Using FallbackVoiceService that throws errors")