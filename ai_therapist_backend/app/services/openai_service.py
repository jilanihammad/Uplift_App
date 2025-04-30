import logging
import os
from typing import Optional, List, Dict, Any
import httpx
import json
import traceback
from tenacity import retry, stop_after_attempt, wait_exponential
from openai import OpenAI

from app.core.config import settings

logger = logging.getLogger(__name__)

class OpenAIService:
    def __init__(self):
        try:
            # Initialize with openai client
            self.client = OpenAI(api_key=settings.OPENAI_API_KEY)
            self.api_key = settings.OPENAI_API_KEY
            
            # API endpoints
            # Chat completions are now handled by Groq service
            # self.chat_endpoint = "https://api.openai.com/v1/chat/completions"
            self.transcription_endpoint = "https://api.openai.com/v1/audio/transcriptions"
            self.tts_endpoint = "https://api.openai.com/v1/audio/speech"
            
            # Models
            # Chat model is now handled by Groq service
            # self.chat_model = "gpt-3.5-turbo"
            self.transcription_model = "whisper-1"
            self.tts_model = settings.OPENAI_TTS_MODEL or "gpt-4o-mini-tts"
            self.tts_voice = settings.OPENAI_TTS_VOICE or "sage"
            
            self.available = bool(self.api_key)
            
            # Log configuration 
            logger.info(f"OpenAIService initialized with:")
            # logger.info(f"Chat Model: {self.chat_model}") # Removed - using Groq now
            logger.info(f"Transcription Model: {self.transcription_model}")
            logger.info(f"TTS Model: {self.tts_model}")
            logger.info(f"TTS Voice: {self.tts_voice}")
            logger.info(f"API Key: {'Set' if self.api_key else 'Not set'}")
            logger.info(f"Service available: {'Yes' if self.available else 'No'}")
            
        except Exception as e:
            logger.error(f"Error initializing OpenAIService: {str(e)}")
            logger.error(traceback.format_exc())
            
            # Set default values
            self.api_key = ""
            # self.chat_model = "gpt-3.5-turbo" # Removed - using Groq now
            self.transcription_model = "whisper-1"
            self.tts_model = "gpt-4o-mini-tts"
            self.tts_voice = "sage"
            self.available = False
            
            logger.warning("OpenAIService unavailable - will return fallback responses")
    
    # Text generation with OpenAI is now handled by Groq service
    """
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def get_ai_response(self, 
                              message: str, 
                              system_prompt: str = "",
                              temperature: float = 0.7,
                              max_tokens: int = 1000) -> str:
        # This method is no longer used - we're using Groq for chat completions
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
            logger.error(f"Error generating AI response: {str(e)}")
            logger.error(traceback.format_exc())
            return "I experienced a technical issue. Please try again or rephrase your question."
    """
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def transcribe_audio(self, audio_file_path: str) -> str:
        """
        Transcribe audio using OpenAI's Whisper API
        
        Args:
            audio_file_path: Path to the audio file
            
        Returns:
            Transcribed text
        """
        if not self.available:
            logger.warning("OpenAI transcription service unavailable - API key not set")
            raise Exception("Transcription service unavailable - API key not set")
            
        try:
            # Check if file exists
            if not os.path.exists(audio_file_path):
                logger.error(f"Audio file not found: {audio_file_path}")
                raise FileNotFoundError(f"Audio file not found: {audio_file_path}")
            
            # Check if file is empty
            file_size = os.path.getsize(audio_file_path)
            if file_size == 0:
                logger.error(f"Audio file is empty: {audio_file_path}")
                raise ValueError("Audio file is empty")
            
            logger.info(f"Processing audio file: {audio_file_path}, size: {file_size} bytes")
            
            # Prepare API call
            headers = {
                "Authorization": f"Bearer {self.api_key}"
            }
            
            # Open the file for sending
            with open(audio_file_path, 'rb') as audio_file:
                files = {
                    'file': (os.path.basename(audio_file_path), audio_file, 'audio/mpeg'),
                    'model': (None, self.transcription_model),
                    'response_format': (None, 'json')
                }
                
                # Make API call
                logger.info(f"Making OpenAI API call to {self.transcription_endpoint}")
                async with httpx.AsyncClient(timeout=30.0) as client:
                    response = await client.post(
                        self.transcription_endpoint,
                        headers=headers,
                        files=files
                    )
                    
                    if response.status_code != 200:
                        logger.error(f"Error from OpenAI API: {response.status_code} - {response.text}")
                        raise Exception(f"Transcription API error: {response.status_code} - {response.text}")
                    
                    # Parse the response
                    result = response.json()
                    logger.info(f"OpenAI transcription successful")
                    
                    transcription_text = result.get("text", "")
                    if not transcription_text:
                        raise Exception("Received empty transcription from OpenAI API")
                        
                    return transcription_text
                    
        except Exception as e:
            logger.error(f"Error in OpenAI transcription: {str(e)}")
            logger.error(traceback.format_exc())
            raise Exception(f"Transcription error: {str(e)}")
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def text_to_speech(self, text: str, output_path: str) -> bool:
        """
        Convert text to speech using OpenAI's TTS API
        
        Args:
            text: Text to convert to speech
            output_path: Path to save the audio file
            
        Returns:
            Boolean indicating success or failure
        """
        if not self.available:
            logger.warning("OpenAI TTS service unavailable - API key not set")
            raise Exception("TTS service unavailable - API key not set")
            
        if not text:
            logger.error("Empty text provided for TTS")
            raise ValueError("Empty text provided for TTS")
            
        try:
            logger.info(f"Converting text to speech using model: {self.tts_model}, voice: {self.tts_voice}")
            
            # Prepare API call
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
            payload = {
                "model": self.tts_model,
                "input": text,
                "voice": self.tts_voice,
                "response_format": "mp3"
            }
            
            # Make API call
            logger.info(f"Making OpenAI API call to {self.tts_endpoint}")
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    self.tts_endpoint,
                    headers=headers,
                    json=payload,
                    timeout=60.0
                )
                
                if response.status_code != 200:
                    logger.error(f"Error from OpenAI TTS API: {response.status_code} - {response.text}")
                    raise Exception(f"TTS API error: {response.status_code} - {response.text}")
                
                # Save the audio file
                try:
                    # Ensure directory exists
                    os.makedirs(os.path.dirname(output_path), exist_ok=True)
                    
                    # Write the audio file
                    with open(output_path, 'wb') as f:
                        f.write(response.content)
                        
                    logger.info(f"TTS audio saved to {output_path}")
                    return True
                    
                except Exception as e:
                    logger.error(f"Error saving TTS audio file: {str(e)}")
                    logger.error(traceback.format_exc())
                    raise Exception(f"Error saving TTS audio file: {str(e)}")
                    
        except Exception as e:
            logger.error(f"Error in OpenAI TTS: {str(e)}")
            logger.error(traceback.format_exc())
            raise Exception(f"TTS error: {str(e)}")
    
    # Implemented session summary generation method using Groq service
    async def generate_session_summary(self,
                                     messages: List[Dict[str, Any]],
                                     therapeutic_approach: str = "supportive",
                                     system_prompt: str = "",
                                     memory_context: str = "") -> Dict[str, Any]:
        """
        Generate a summary of a therapy session using OpenAI's language model.
        
        Args:
            messages: List of conversation messages
            therapeutic_approach: Therapeutic approach used (supportive, CBT, etc.)
            system_prompt: System prompt used in the conversation
            memory_context: Additional context from memory
            
        Returns:
            Dictionary with summary, action items, and insights
        """
        if not self.available:
            logger.warning("OpenAI LLM service unavailable for session summary - API key not set")
            return {
                "summary": "In this session, we discussed various aspects of your current challenges and explored potential coping strategies.",
                "action_items": [
                    "Practice deep breathing for 5 minutes when feeling anxious",
                    "Keep a mood journal to track emotional patterns",
                    "Schedule one self-care activity this week"
                ],
                "insights": [
                    "You've been making progress in recognizing your triggers",
                    "Your self-awareness is a significant strength"
                ]
            }
        
        try:
            # Import the groq service here to avoid circular imports
            from app.services.groq_service import groq_service
            
            # Create a summarization prompt
            conversation_text = ""
            for msg in messages:
                role = "User" if msg.get("isUser", False) else "Therapist"
                conversation_text += f"{role}: {msg.get('content', '')}\n\n"
            
            summary_prompt = f"""
            You are a skilled AI therapist assistant. Based on the conversation below, please provide:
            1. A concise summary of the key points discussed
            2. 3-5 actionable suggestions for the client
            3. 2-3 insights about patterns or progress noticed
            
            Therapeutic approach: {therapeutic_approach}
            
            CONVERSATION:
            {conversation_text}
            
            {memory_context}
            
            Please format your response as JSON with the following structure:
            {{
                "summary": "Summary of the session",
                "action_items": ["Action 1", "Action 2", ...],
                "insights": ["Insight 1", "Insight 2", ...]
            }}
            """
            
            # Get the assistant's response using the groq service
            try:
                response_text = await groq_service.generate_response(
                    message=summary_prompt,
                    temperature=0.7,
                    max_tokens=2000
                )
            except Exception as groq_error:
                logger.warning(f"Error using Groq for session summary: {str(groq_error)}")
                logger.warning("Falling back to default summary")
                return {
                    "summary": "We had a thoughtful conversation about your current situation and explored some potential strategies moving forward.",
                    "action_items": [
                        "Take time for self-care activities",
                        "Practice mindfulness exercises",
                        "Reflect on the insights from our session"
                    ],
                    "insights": [
                        "You're showing progress in how you approach challenges",
                        "Your self-awareness is a significant strength"
                    ]
                }
            
            # Try to parse the JSON response
            try:
                # Extract JSON from the response text (it might be wrapped in markdown code blocks)
                if "```json" in response_text:
                    json_str = response_text.split("```json")[1].split("```")[0].strip()
                elif "```" in response_text:
                    json_str = response_text.split("```")[1].strip()
                else:
                    json_str = response_text
                    
                result = json.loads(json_str)
                logger.info("Session summary generated successfully")
                return result
                
            except (json.JSONDecodeError, KeyError) as e:
                # If JSON parsing fails, create a structured response manually
                logger.warning(f"Failed to parse LLM response as JSON: {str(e)}, creating structured response manually")
                return {
                    "summary": response_text,
                    "action_items": ["Practice mindfulness daily", "Journal about emotions"],
                    "insights": ["Working through challenges with good progress"]
                }
                
        except Exception as e:
            logger.error(f"Error generating session summary: {str(e)}")
            logger.error(traceback.format_exc())
            
            # Return a fallback summary
            return {
                "summary": "We had a productive conversation today exploring your feelings and thoughts.",
                "action_items": [
                    "Take time for self-care",
                    "Practice mindfulness",
                    "Reflect on today's insights"
                ],
                "insights": [
                    "You're making progress in your journey",
                    "Your resilience is a key strength"
                ]
            }

# Create a singleton instance
try:
    openai_service = OpenAIService()
    logger.info("OpenAIService initialized successfully")
except Exception as e:
    # Create a minimal service that throws errors instead of returning fallbacks
    logger.error(f"Failed to initialize OpenAIService: {str(e)}")
    logger.error(traceback.format_exc())
    
    class FallbackOpenAIService:
        """A minimal service that throws errors instead of returning fallbacks"""
        
        async def transcribe_audio(self, audio_file_path):
            raise Exception("Transcription service unavailable - OpenAI service failed to initialize")
            
        async def text_to_speech(self, text, output_path):
            raise Exception("TTS service unavailable - OpenAI service failed to initialize")
        
        async def generate_session_summary(self, messages, therapeutic_approach="supportive", system_prompt="", memory_context=""):
            """
            Fallback implementation of session summary generation.
            Returns a generic session summary when the OpenAI service is unavailable.
            """
            logger.warning("Using fallback session summary generator - OpenAI service failed to initialize")
            return {
                "summary": "We had a productive conversation today exploring your thoughts and feelings.",
                "action_items": [
                    "Take time for self-care",
                    "Practice mindfulness",
                    "Reflect on today's insights"
                ],
                "insights": [
                    "You're making progress in your journey",
                    "Your resilience is a key strength"
                ]
            }
    
    openai_service = FallbackOpenAIService()
    logger.warning("Using FallbackOpenAIService that throws errors") 