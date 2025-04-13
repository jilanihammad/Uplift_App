# app/services/voice_service.py (Updated for Sesame AI)

import logging
from typing import Optional
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential
import asyncio
import tempfile
import os

from app.core.config import settings

logger = logging.getLogger(__name__)

class VoiceService:
    def __init__(self):
        self.api_key = settings.SESAME_API_KEY
        self.base_url = settings.SESAME_API_URL
        self.voice_id = "therapist-calm"  # Default voice ID
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def generate_speech(self, text: str) -> Optional[str]:
        """
        Generate speech from text using Sesame AI API.
        
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
            # Generate the audio using Sesame AI API
            headers = {
                "Accept": "audio/mpeg",
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }
            
            data = {
                "text": text,
                "voice_id": self.voice_id,
                "settings": {
                    "stability": 0.5,
                    "clarity": 0.75,
                    "style": "therapeutic"
                }
            }
            
            async with httpx.AsyncClient() as client:
                response = await client.post(self.base_url, json=data, headers=headers)
                
                if response.status_code != 200:
                    logger.error(f"Error from Sesame AI API: {response.text}")
                    return None
                
                # Create a temporary file to store the audio
                with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as temp_file:
                    temp_file.write(response.content)
                    audio_path = temp_file.name
                
                audio_url = f"/api/audio/{os.path.basename(audio_path)}"
                
                return audio_url
                
        except Exception as e:
            logger.error(f"Error generating speech: {str(e)}")
            return None
    
    def set_voice(self, voice_id: str) -> None:
        """
        Set the voice ID to use for speech generation.
        
        Args:
            voice_id: Voice ID
        """
        self.voice_id = voice_id

voice_service = VoiceService()