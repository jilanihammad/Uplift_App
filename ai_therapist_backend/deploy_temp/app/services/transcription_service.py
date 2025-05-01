import logging
import os
import tempfile
import json
import requests
from fastapi import UploadFile
from pydantic import BaseModel
from typing import Optional
import traceback

from app.core.config import settings

logger = logging.getLogger(__name__)

class TranscriptionService:
    def __init__(self):
        try:
            # Use OpenAI instead of Groq
            self.api_key = settings.OPENAI_API_KEY
            self.base_url = "https://api.openai.com/v1/audio/transcriptions"
            self.model = "whisper-1"  # OpenAI's Whisper model
            self.available = bool(self.api_key)
            
            # Print configuration for debugging
            logger.info(f"TranscriptionService initialized with:")
            logger.info(f"API Base URL: {self.base_url}")
            logger.info(f"Model: {self.model}")
            logger.info(f"API Key: {'Set' if self.api_key else 'Not set'}")
            logger.info(f"Service available: {'Yes' if self.available else 'No'}")
        except Exception as e:
            logger.error(f"Error initializing TranscriptionService: {str(e)}")
            logger.error(traceback.format_exc())
            # Set default values
            self.api_key = ""
            self.base_url = "https://api.openai.com/v1/audio/transcriptions"
            self.model = "whisper-1"
            self.available = False
            logger.warning("TranscriptionService unavailable - will return fallback responses")
        
    async def transcribe_audio(self, audio_file: UploadFile) -> Optional[str]:
        """
        Transcribe audio file using OpenAI API
        
        Args:
            audio_file: Audio file to transcribe
            
        Returns:
            Transcription text or empty string if transcription failed
        """
        if not audio_file:
            logger.error("No audio file provided")
            return ""  # Return empty string to prompt user to type
            
        # Check if service is available
        if not self.available:
            logger.warning("Transcription service unavailable - API key not set")
            return ""  # Return empty string to prompt user to type
            
        try:
            # Save uploaded file to a temporary file
            with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as temp_file:
                temp_file_path = temp_file.name
                temp_file.write(await audio_file.read())
                
            logger.info(f"Saved audio to temporary file: {temp_file_path}")
            
            # Prepare the request to OpenAI API
            headers = {
                "Authorization": f"Bearer {self.api_key}"
            }
            
            with open(temp_file_path, "rb") as f:
                files = {
                    "file": (os.path.basename(temp_file_path), f, "audio/mpeg"),
                    "model": (None, self.model),
                    "language": (None, "en"),
                    "response_format": (None, "json")
                }
                
                logger.info(f"Sending transcription request to {self.base_url}")
                response = requests.post(
                    self.base_url,
                    headers=headers,
                    files=files
                )
                
            # Clean up the temporary file
            try:
                os.unlink(temp_file_path)
                logger.info("Temporary file removed")
            except Exception as cleanup_error:
                logger.warning(f"Could not remove temporary file: {str(cleanup_error)}")
            
            if response.status_code != 200:
                logger.error(f"Error from OpenAI API: {response.status_code} - {response.text}")
                return ""  # Return empty string to prompt user to type
            
            result = response.json()
            logger.info("Transcription successful")
            
            transcription_text = result.get("text", "")
            if not transcription_text:
                return ""  # Return empty string to prompt user to type
                
            return transcription_text
                
        except Exception as e:
            logger.error(f"Error in transcription service: {str(e)}")
            logger.error(traceback.format_exc())
            return ""  # Return empty string to prompt user to type

try:
    # Attempt to initialize the service, but don't crash if it fails
    transcription_service = TranscriptionService()
    logger.info("TranscriptionService initialized successfully")
except Exception as e:
    # Create a minimal service that returns fallback responses
    logger.error(f"Failed to initialize TranscriptionService: {str(e)}")
    logger.error(traceback.format_exc())
    
    class FallbackTranscriptionService:
        async def transcribe_audio(self, audio_file):
            return ""  # Return empty string to prompt user to type
    
    transcription_service = FallbackTranscriptionService()
    logger.warning("Using FallbackTranscriptionService as fallback") 