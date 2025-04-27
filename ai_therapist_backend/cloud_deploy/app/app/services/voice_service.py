# app/services/voice_service.py (Updated for GROQ API)

import logging
from typing import Optional
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential
import asyncio
import tempfile
import os
import uuid

from app.core.config import settings

logger = logging.getLogger(__name__)

class VoiceService:
    def __init__(self):
        self.api_key = settings.GROQ_API_KEY
        self.base_url = f"{settings.GROQ_API_BASE_URL}/audio/speech"
        self.tts_model = settings.GROQ_TTS_MODEL_ID
        self.voice = "Jennifer-PlayAI"  # Default voice - one of the PlayAI voices
        
        # Ensure audio directory exists
        self.audio_dir = "static/audio"
        os.makedirs(self.audio_dir, exist_ok=True)
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def generate_speech(self, text: str) -> Optional[str]:
        """
        Generate speech from text using GROQ API.
        
        Args:
            text: Text to convert to speech
        
        Returns:
            URL to the generated audio file or None if generation failed
        """
        if not text:
            return None
        
        # Limit text length to avoid excessive API usage
        if len(text) > 5000:
            text = text[:5000]
        
        try:
            # Generate a unique filename for the audio file
            filename = f"{uuid.uuid4()}.mp3"
            file_path = os.path.join(self.audio_dir, filename)
            
            # Generate the audio using GROQ API
            headers = {
                "Accept": "audio/mpeg",
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }
            
            data = {
                "model": self.tts_model,
                "input": text,
                "voice": self.voice,
                "speed": 1.0
            }
            
            logger.info(f"Calling GROQ API for TTS with voice: {self.voice}")
            
            try:
                async with httpx.AsyncClient(timeout=30.0) as client:
                    response = await client.post(self.base_url, json=data, headers=headers)
                    
                    if response.status_code != 200:
                        logger.error(f"Error from GROQ API: {response.status_code} - {response.text}")
                        # Create a fallback audio file with error
                        with open(file_path, "wb") as f:
                            # If there's an error.mp3 file, copy it
                            error_path = os.path.join(self.audio_dir, "error.mp3")
                            if os.path.exists(error_path):
                                with open(error_path, "rb") as error_file:
                                    f.write(error_file.read())
                            else:
                                # Create an empty file as fallback
                                f.write(b"")
                    else:
                        # Save the audio content to the file
                        with open(file_path, "wb") as f:
                            f.write(response.content)
                        
                        logger.info(f"Audio file saved to {file_path}")
            except Exception as e:
                logger.error(f"Error in API request: {str(e)}")
                # Create a fallback audio file
                with open(file_path, "wb") as f:
                    f.write(b"")
            
            # Return the URL path relative to the server root
            # This URL format matches what the app expects
            audio_url = f"/audio/{filename}"
            
            return audio_url
                
        except Exception as e:
            logger.error(f"Error generating speech: {str(e)}")
            # Return a fallback URL
            return "/audio/error.mp3"
    
    def set_voice(self, voice_id: str) -> None:
        """
        Set the voice ID to use for speech generation.
        
        Args:
            voice_id: Voice ID for GROQ API
        """
        self.voice = voice_id

voice_service = VoiceService()