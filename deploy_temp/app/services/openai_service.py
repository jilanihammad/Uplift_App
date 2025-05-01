import logging
import os
from typing import Optional, List, Dict, Any
import httpx
import json
import traceback
from tenacity import retry, stop_after_attempt, wait_exponential

from app.core.config import settings

logger = logging.getLogger(__name__)

class OpenAIService:
    def __init__(self):
        try:
            # API Keys
            self.api_key = settings.OPENAI_API_KEY
            
            # API endpoints
            self.chat_endpoint = "https://api.openai.com/v1/chat/completions"
            self.transcription_endpoint = "https://api.openai.com/v1/audio/transcriptions"
            self.tts_endpoint = "https://api.openai.com/v1/audio/speech"
            
            # Models
            self.chat_model = settings.OPENAI_LLM_MODEL or "gpt-4.1-mini"  # Use env var or default
            self.transcription_model = settings.OPENAI_TRANSCRIPTION_MODEL or "whisper-1"
            self.tts_model = settings.OPENAI_TTS_MODEL or "gpt-4o-mini-tts"
            self.tts_voice = settings.OPENAI_TTS_VOICE or "sage"
            
            self.available = bool(self.api_key)
            
            # Log configuration 
            logger.info(f"OpenAIService initialized with:")
            logger.info(f"Chat Model: {self.chat_model}")
            logger.info(f"Transcription Model: {self.transcription_model}")
            logger.info(f"TTS Model: {self.tts_model}")
            logger.info(f"TTS Voice: {self.tts_voice}")
            logger.info(f"API Key: {'Set' if self.api_key else 'Not set'}")
            logger.info(f"Service available: {'Yes' if self.available else 'No'}")
            
            if self.api_key and self.chat_model:
                logger.info("OpenAIService initialized successfully")
            else:
                logger.warning("OpenAIService initialized with missing configuration")
                
        except Exception as e:
            logger.error(f"Error initializing OpenAIService: {str(e)}")
            logger.error(traceback.format_exc())
            
            # Set default values
            self.api_key = ""
            self.chat_model = "gpt-4.1-mini"
            self.transcription_model = "whisper-1"
            self.tts_model = "gpt-4o-mini-tts"
            self.tts_voice = "sage"
            self.available = False
            
            logger.warning("OpenAIService unavailable - will return fallback responses")
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def get_ai_response(self, 
                              message: str, 
                              system_prompt: str = "",
                              temperature: float = 0.7,
                              max_tokens: int = 1000) -> str:
        """
        Get a response from the AI using OpenAI ChatGPT API
        
        Args:
            message: The user message
            system_prompt: Optional system prompt to set the context
            temperature: Controls randomness (0-1)
            max_tokens: Maximum number of tokens to generate
            
        Returns:
            AI response text
        """
        if not self.available:
            logger.warning("OpenAI LLM service unavailable - API key not set")
            return "I'm having trouble processing your request right now. Please try again later."
            
        # Prepare messages array
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        
        messages.append({"role": "user", "content": message})
        
        try:
            # Prepare the API request
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
            payload = {
                "model": self.chat_model,
                "messages": messages,
                "temperature": temperature,
                "max_tokens": max_tokens
            }
            
            # Log request details (without the full message content for privacy)
            logger.info(f"Sending request to OpenAI chat endpoint with model: {self.chat_model}")
            
            # Make API call
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    self.chat_endpoint,
                    headers=headers,
                    json=payload
                )
                
                if response.status_code != 200:
                    logger.error(f"Error from OpenAI API: {response.status_code} - {response.text}")
                    return "I'm having trouble processing your request right now. Please try again later."
                
                # Parse the JSON response
                result = response.json()
                
                # Extract the assistant's reply
                if "choices" in result and len(result["choices"]) > 0:
                    assistant_reply = result["choices"][0]["message"]["content"]
                    logger.info(f"OpenAI response generated successfully")
                    return assistant_reply
                else:
                    logger.error(f"Unexpected response format from OpenAI: {result}")
                    return "I'm having trouble understanding your request. Could you please try again?"
                    
        except Exception as e:
            logger.error(f"Error generating OpenAI response: {str(e)}")
            logger.error(traceback.format_exc())
            return "I'm having trouble processing your request right now. Please try again later."

# Create a singleton instance
try:
    openai_service = OpenAIService()
    logger.info("OpenAIService initialized successfully")
except Exception as e:
    # Create a minimal service that returns fallback responses
    logger.error(f"Failed to initialize OpenAIService: {str(e)}")
    logger.error(traceback.format_exc())
    
    class FallbackOpenAIService:
        async def get_ai_response(self, message, **kwargs):
            return "I'm having trouble responding right now. Please try again later."
            
        async def transcribe_audio(self, audio_file_path):
            return "Transcription service is currently unavailable. Please type your message instead."
            
        async def generate_session_summary(self, messages, **kwargs):
            return {
                "summary": "Session summary is currently unavailable.",
                "action_items": ["Please try again later"],
                "insights": ["Service temporarily unavailable"]
            }
    
    openai_service = FallbackOpenAIService()
    logger.warning("Using FallbackOpenAIService as fallback") 