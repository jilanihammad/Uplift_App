import logging
import os
from typing import Optional
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from app.core.config import settings

logger = logging.getLogger(__name__)

class GroqService:
    def __init__(self):
        self.api_key = settings.GROQ_API_KEY
        self.openai_api_key = settings.OPENAI_API_KEY or self.api_key  # Fallback to GROQ key if no OpenAI key
        
        # API endpoints
        self.groq_api_base_url = settings.GROQ_API_BASE_URL
        self.groq_transcription_url = f"{self.groq_api_base_url}/audio/transcriptions"
        self.openai_transcription_url = "https://api.openai.com/v1/audio/transcriptions"
        
        # Models
        self.default_transcription_model = "whisper-1"  # Default OpenAI model
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def transcribe_audio(self, audio_file_path: str, model: Optional[str] = None) -> str:
        """
        Transcribe audio using either GROQ API or OpenAI API based on the model specified.
        
        Args:
            audio_file_path: Path to the audio file
            model: Model ID to use for transcription
                - "distil-whisper-large-v3-en": Uses GROQ API
                - "whisper-1": Uses OpenAI API (fallback)
        
        Returns:
            Transcribed text
        """
        try:
            # Check if file exists
            if not os.path.exists(audio_file_path):
                logger.error(f"Audio file not found: {audio_file_path}")
                return "Audio file not found"
            
            # Check if file is empty
            file_size = os.path.getsize(audio_file_path)
            if file_size == 0:
                logger.error(f"Audio file is empty: {audio_file_path}")
                return "Audio file is empty"
            
            logger.info(f"Processing audio file: {audio_file_path}, size: {file_size} bytes")
            
            # Determine which API to use based on the model requested
            requested_model = model or self.default_transcription_model
            if requested_model == "distil-whisper-large-v3-en":
                logger.info(f"Using GROQ API with distil-whisper-large-v3-en model")
                return await self._transcribe_with_groq(audio_file_path, "distil-whisper-large-v3-en")
            else:
                # Default to OpenAI API
                logger.info(f"Using OpenAI API with whisper-1 model")
                return await self._transcribe_with_openai(audio_file_path)
                
        except Exception as e:
            import traceback
            logger.error(f"Error transcribing audio: {str(e)}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            return f"Error transcribing audio: {str(e)}"
    
    async def _transcribe_with_groq(self, audio_file_path: str, model_id: str) -> str:
        """Transcribe audio using GROQ's API"""
        try:
            # Prepare API call
            headers = {
                "Authorization": f"Bearer {self.api_key}"
            }
            
            # Create formdata with file and model parameters
            formdata = {
                'model': model_id,
                'response_format': 'json'
            }
            
            # Log API key status (don't log the actual key)
            if not self.api_key or len(self.api_key) < 10:
                logger.error(f"Invalid or missing GROQ API key. Key length: {len(self.api_key) if self.api_key else 0}")
                return "Error: Invalid GROQ API credentials"
            else:
                logger.info(f"Using GROQ API key: {self.api_key[:4]}...{self.api_key[-4:] if len(self.api_key) > 8 else ''}")
            
            # Open the file for sending
            files = {
                'file': open(audio_file_path, 'rb')
            }
            
            try:
                # Make API call with httpx
                logger.info(f"Making GROQ API call to {self.groq_transcription_url} with model {model_id}")
                async with httpx.AsyncClient(timeout=30.0) as client:
                    response = await client.post(
                        self.groq_transcription_url,
                        headers=headers,
                        data=formdata,
                        files=files
                    )
                    
                    logger.info(f"Received response with status code: {response.status_code}")
                    
                    if response.status_code != 200:
                        logger.error(f"Error from GROQ API: {response.status_code} - {response.text}")
                        # Fall back to OpenAI if GROQ fails
                        logger.info("Falling back to OpenAI API")
                        return await self._transcribe_with_openai(audio_file_path)
                    
                    # Parse JSON response
                    result = response.json()
                    logger.info(f"GROQ API response content: {result}")
                    
                    # Extract transcription text
                    if 'text' in result:
                        transcription = result['text']
                        logger.info(f"GROQ transcription successful: {transcription[:50]}...")
                        return transcription
                    else:
                        logger.error(f"Unexpected response format from GROQ: {result}")
                        # Fall back to OpenAI
                        return await self._transcribe_with_openai(audio_file_path)
            finally:
                # Close the file
                files['file'].close()
        except Exception as e:
            logger.error(f"Error in GROQ transcription: {str(e)}")
            # Fall back to OpenAI
            logger.info("GROQ API call failed, falling back to OpenAI API")
            return await self._transcribe_with_openai(audio_file_path)
    
    async def _transcribe_with_openai(self, audio_file_path: str) -> str:
        """Transcribe audio using OpenAI's API"""
        try:
            model_id = "whisper-1"  # Always use whisper-1 for OpenAI
            
            # Prepare API call
            headers = {
                "Authorization": f"Bearer {self.openai_api_key}"
            }
            
            # Create formdata with file and model parameters
            formdata = {
                'model': model_id,
                'response_format': 'json'
            }
            
            # Log API key status (don't log the actual key)
            if not self.openai_api_key or len(self.openai_api_key) < 10:
                logger.error(f"Invalid or missing OpenAI API key. Key length: {len(self.openai_api_key) if self.openai_api_key else 0}")
                return "Error: Invalid API credentials"
            else:
                logger.info(f"Using OpenAI API key: {self.openai_api_key[:4]}...{self.openai_api_key[-4:] if len(self.openai_api_key) > 8 else ''}")
            
            # Open the file for sending
            files = {
                'file': open(audio_file_path, 'rb')
            }
            
            try:
                # Make API call with httpx
                logger.info(f"Making OpenAI API call to {self.openai_transcription_url}")
                async with httpx.AsyncClient(timeout=30.0) as client:
                    response = await client.post(
                        self.openai_transcription_url,
                        headers=headers,
                        data=formdata,
                        files=files
                    )
                    
                    logger.info(f"Received response with status code: {response.status_code}")
                    
                    if response.status_code != 200:
                        logger.error(f"Error from OpenAI API: {response.status_code} - {response.text}")
                        return f"Error transcribing audio: API returned status {response.status_code}"
                    
                    # Parse JSON response
                    result = response.json()
                    logger.info(f"OpenAI response content: {result}")
                    
                    # Extract transcription text
                    if 'text' in result:
                        transcription = result['text']
                        logger.info(f"OpenAI transcription successful: {transcription[:50]}...")
                        return transcription
                    else:
                        logger.error(f"Unexpected response format from OpenAI: {result}")
                        return "Error processing transcription result: unexpected response format"
            finally:
                # Close the file
                files['file'].close()
        except Exception as e:
            logger.error(f"Error in OpenAI transcription: {str(e)}")
            return f"Error with OpenAI transcription: {str(e)}"

# Create a singleton instance
groq_service = GroqService() 