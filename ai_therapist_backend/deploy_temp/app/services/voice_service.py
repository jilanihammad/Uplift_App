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
            # Initialize with OpenAI API key
            self.api_key = settings.OPENAI_API_KEY
            self.base_url = "https://api.openai.com/v1/audio/speech"
            self.tts_model = settings.OPENAI_TTS_MODEL or "gpt-4o-mini-tts"
            self.voice = settings.OPENAI_TTS_VOICE or "sage"
            self.available = bool(self.api_key)
            
            # Use /tmp in Cloud Run, otherwise use static/audio
            if os.environ.get("GOOGLE_CLOUD") == "1":
                logger.info("Running in Cloud Run environment, using /tmp for audio storage")
                self.audio_dir = "/tmp/static/audio"
            else:
                self.audio_dir = "static/audio"
                
            # Ensure audio directory exists
            os.makedirs(self.audio_dir, exist_ok=True)
            logger.info(f"Audio directory: {self.audio_dir}")
            
            # Create a fallback audio file if it doesn't exist
            self._create_fallback_audio()
            
            logger.info(f"VoiceService initialized with:")
            logger.info(f"TTS Model: {self.tts_model}")
            logger.info(f"Voice: {self.voice}")
            logger.info(f"API Key: {'Set' if self.api_key else 'Not set'}")
            logger.info(f"Service available: {'Yes' if self.available else 'No'}")
        except Exception as e:
            logger.error(f"Error initializing VoiceService: {str(e)}")
            logger.error(traceback.format_exc())
            
            # Use default values on error
            self.api_key = ""
            self.base_url = "https://api.openai.com/v1/audio/speech"
            self.tts_model = "gpt-4o-mini-tts"
            self.voice = "sage"
            self.available = False
            
            # Ensure audio directory exists even on error - use /tmp in Cloud Run
            if os.environ.get("GOOGLE_CLOUD") == "1":
                self.audio_dir = "/tmp/static/audio"
            else:
                self.audio_dir = "static/audio"
                
            os.makedirs(self.audio_dir, exist_ok=True)
            
            logger.warning("VoiceService unavailable - will return fallback responses")
    
    def _create_fallback_audio(self):
        """Create a valid fallback MP3 file"""
        error_file = os.path.join(self.audio_dir, "error.mp3")
        
        if os.path.exists(error_file) and os.path.getsize(error_file) > 1000:
            logger.info(f"Fallback audio file already exists: {error_file}")
            return
            
        try:
            # Create a simple text file as fallback in Cloud Run
            with open(error_file, "wb") as f:
                f.write(b"This is a fallback audio file")
            logger.info(f"Created simple fallback file: {error_file}")
        except Exception as e:
            logger.error(f"Error creating fallback audio file: {str(e)}")
            logger.error(traceback.format_exc())
    
    async def generate_speech(self, text: str) -> Optional[str]:
        """Generate speech from text and return the URL to the generated audio file"""
        if not text:
            raise ValueError("No text provided for speech generation")
            
        if not self.available:
            raise ValueError("Voice service unavailable - API key not set")
            
        # Use OpenAI API to generate speech
        try:
            # Generate a unique filename for the audio file
            filename = f"{uuid.uuid4()}.mp3"
            file_path = os.path.join(self.audio_dir, filename)
            
            # Ensure the directory exists
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            
            # Call the OpenAI TTS API
            from app.services.openai_service import openai_service
            tts_success = await openai_service.text_to_speech(text, file_path)
            
            logger.info(f"TTS result: {'Success' if tts_success else 'Failed'}")
            
            # Return the URL to the audio file
            return f"/audio/{filename}"
            
        except Exception as e:
            logger.error(f"Error generating speech: {str(e)}")
            logger.error(traceback.format_exc())
            raise Exception(f"Speech generation failed: {str(e)}")
    
    def set_voice(self, voice_id: str) -> None:
        """
        Set the voice ID to use for speech generation.
        
        Args:
            voice_id: Voice ID for OpenAI API (alloy, echo, fable, onyx, nova, shimmer, sage)
        """
        try:
            self.voice = voice_id.lower()  # OpenAI voices are lowercase
            logger.info(f"Voice set to: {self.voice}")
        except Exception as e:
            logger.error(f"Error setting voice: {str(e)}")
            logger.error(traceback.format_exc())

# Create a singleton instance
try:
    voice_service = VoiceService()
    logger.info("VoiceService initialized successfully")
except Exception as e:
    # Create a minimal service that throws errors
    logger.error(f"Failed to initialize VoiceService: {str(e)}")
    logger.error(traceback.format_exc())
    
    class FallbackVoiceService:
        """A service that throws errors instead of returning fallbacks"""
        async def generate_speech(self, text):
            raise Exception("Voice service unavailable - failed to initialize")
            
        def set_voice(self, voice_id):
            pass
    
    voice_service = FallbackVoiceService()
    logger.warning("Using FallbackVoiceService that throws errors")