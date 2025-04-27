# app/services/voice_service.py (Updated for OpenAI TTS)

import logging
from typing import Optional
import requests
import os
import uuid

from app.core.config import settings

logger = logging.getLogger(__name__)

class VoiceService:
    def __init__(self):
        # Use environment variables instead of hardcoded values
        self.api_key = settings.OPENAI_API_KEY
        self.base_url = "https://api.openai.com/v1/audio/speech"
        self.tts_model = settings.OPENAI_TTS_MODEL or "gpt-4o-mini-tts"
        self.voice = settings.OPENAI_TTS_VOICE or "sage"
        
        # Ensure audio directory exists
        self.audio_dir = "static/audio"
        os.makedirs(self.audio_dir, exist_ok=True)
        
        # Create a fallback audio file if it doesn't exist
        self._create_fallback_audio()
        
        logger.info(f"VoiceService initialized with:")
        logger.info(f"TTS Model: {self.tts_model}")
        logger.info(f"Voice: {self.voice}")
        logger.info(f"API Key: {'Set' if self.api_key else 'Not set'}")
        logger.info(f"Service available: {'Yes' if self.api_key else 'No'}")
        
        if self.api_key and self.tts_model and self.voice:
            logger.info("VoiceService initialized successfully")
        else:
            logger.warning("VoiceService initialized with missing configuration")
    
    def _create_fallback_audio(self):
        """Create a valid fallback MP3 file"""
        error_file = os.path.join(self.audio_dir, "error.mp3")
        
        if os.path.exists(error_file) and os.path.getsize(error_file) > 100:
            logger.info(f"Fallback audio file already exists: {error_file}")
            return
            
        try:
            # This is a minimal valid MP3 file
            with open(error_file, "wb") as f:
                # Simple but valid MP3 frame header
                mp3_data = bytearray.fromhex(
                    "FFFB5000" +  # MPEG1 Layer 3 header
                    "00000000000000000000" +
                    "00000000000000000000" +
                    "00000000000000000000" 
                )
                f.write(mp3_data)
            
            logger.info(f"Created fallback audio file: {error_file}")
        except Exception as e:
            logger.error(f"Error creating fallback audio file: {str(e)}")
    
    async def generate_speech(self, text: str) -> Optional[str]:
        """
        Generate speech from text using OpenAI API.
        
        Args:
            text: Text to convert to speech
        
        Returns:
            URL to the generated audio file or None if generation failed
        """
        if not text:
            return "/audio/error.mp3"
        
        # Check if API key is available
        if not self.api_key:
            logger.error("No OpenAI API key available")
            return "/audio/error.mp3"
        
        # Limit text length to avoid excessive API usage
        if len(text) > 4000:  # OpenAI has a 4096 token limit
            text = text[:4000]
        
        try:
            # Generate a unique filename for the audio file
            filename = f"{uuid.uuid4()}.mp3"
            file_path = os.path.join(self.audio_dir, filename)
            
            # Generate the audio using OpenAI API
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
            data = {
                "model": self.tts_model,
                "input": text,
                "voice": self.voice,
                "response_format": "mp3"
            }
            
            logger.info(f"Calling OpenAI API for TTS with voice: {self.voice}")
            
            # Make the API call - using sync requests since it works
            try:
                response = requests.post(
                    self.base_url, 
                    json=data, 
                    headers=headers,
                    timeout=30
                )
                
                if response.status_code != 200:
                    logger.error(f"Error from OpenAI API: {response.status_code} - {response.text}")
                    return "/audio/error.mp3"
                
                # Save the audio content to the file
                with open(file_path, "wb") as f:
                    f.write(response.content)
                
                file_size = os.path.getsize(file_path)
                logger.info(f"Audio file saved to {file_path} with size {file_size} bytes")
                
                if file_size > 0:
                    return f"/audio/{filename}"
                else:
                    logger.error("Generated audio file is empty")
                    return "/audio/error.mp3"
                    
            except Exception as e:
                logger.error(f"Error calling OpenAI speech API: {str(e)}")
                return "/audio/error.mp3"
            
        except Exception as e:
            logger.error(f"Error generating speech: {str(e)}")
            return "/audio/error.mp3"
    
    def set_voice(self, voice_id: str) -> None:
        """
        Set the voice ID to use for speech generation.
        
        Args:
            voice_id: Voice ID for OpenAI API (alloy, echo, fable, onyx, nova, shimmer)
        """
        try:
            self.voice = voice_id.lower()  # OpenAI voices are lowercase
            logger.info(f"Voice set to: {self.voice}")
        except Exception as e:
            logger.error(f"Error setting voice: {str(e)}")

voice_service = VoiceService() 