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
            # Get API key from environment
            self.api_key = settings.OPENAI_API_KEY
            # Check if API key is available
            self.available = bool(self.api_key and len(self.api_key) > 10)
            
            # Set up endpoints
            self.base_url = "https://api.openai.com/v1"
            self.chat_endpoint = f"{self.base_url}/chat/completions"
            self.transcription_endpoint = f"{self.base_url}/audio/transcriptions"
            self.tts_endpoint = f"{self.base_url}/audio/speech"
            
            # Get model names from environment variables
            self.llm_model = settings.OPENAI_LLM_MODEL or "gpt-4.1-mini"
            self.transcription_model = settings.OPENAI_TRANSCRIPTION_MODEL or "whisper-1"
            self.tts_model = settings.OPENAI_TTS_MODEL or "gpt-4o-mini-tts"
            self.tts_voice = settings.OPENAI_TTS_VOICE or "sage"
            
            # Log initialization status
            if self.available:
                logger.info(f"OpenAI service initialized with models: LLM={self.llm_model}, TTS={self.tts_model}, Transcription={self.transcription_model}")
            else:
                logger.warning("OpenAI service unavailable - API key not set or invalid")
            
            # Initialize with openai client
            self.client = OpenAI(api_key=self.api_key)
            
        except Exception as e:
            logger.error(f"Error initializing OpenAIService: {str(e)}")
            logger.error(traceback.format_exc())
            
            # Set default values
            self.api_key = ""
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
            
            logger.info(f"Processing audio file: {audio_file_path}, size: {file_size} bytes using model: {self.transcription_model}")
            
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
                logger.info(f"Making OpenAI API call to {self.transcription_endpoint} with model {self.transcription_model}")
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
                    logger.info(f"OpenAI transcription successful with model {self.transcription_model}")
                    
                    transcription_text = result.get("text", "")
                    if not transcription_text:
                        raise Exception("Received empty transcription from OpenAI API")
                        
                    return transcription_text
                    
        except Exception as e:
            logger.error(f"Error in OpenAI transcription: {str(e)}")
            logger.error(traceback.format_exc())
            raise Exception(f"Transcription error: {str(e)}")
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def text_to_speech(self, text: str, output_path: str, format_params: dict = None) -> bool:
        """
        Convert text to speech using OpenAI's TTS API
        
        Args:
            text: Text to convert to speech
            output_path: Path to save the audio file
            format_params: Optional parameters for audio format and quality
            
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
            
            # Handle file extension based on format
            audio_format = format_params.get("response_format", "mp3") if format_params else "mp3"
            if audio_format == "opus" or audio_format == "mp3":
                # Make sure output path has correct extension
                if not output_path.endswith((".opus", ".mp3")):
                    output_path = output_path.rsplit(".", 1)[0] + ".opus"
            
            # Prepare API call
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
            # Start with base payload
            payload = {
                "model": self.tts_model,
                "input": text,
                "voice": self.tts_voice,
                "response_format": "mp3"  # Default
            }
            
            # Update with any format parameters
            if format_params:
                payload.update(format_params)
                
            logger.info(f"Using TTS parameters: format={payload.get('response_format')}, voice={payload.get('voice')}")
            
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
    
    # Implemented session summary generation method using LLM manager
    async def generate_session_summary(self,
                                     messages: List[Dict[str, Any]],
                                     therapeutic_approach: str = "supportive",
                                     system_prompt: str = "",
                                     memory_context: str = "") -> Dict[str, Any]:
        """
        Generate a summary of a therapy session using the configured LLM service.
        
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
            # Use the LLM manager instead of direct Groq service
            from app.services.llm_manager import LLMManager
            llm_manager = LLMManager()
            
            # Create a comprehensive summarization prompt
            conversation_text = ""
            user_concerns = []
            therapist_suggestions = []
            
            for msg in messages:
                role = "User" if msg.get("isUser", False) else "Therapist"
                content = msg.get('content', '')
                conversation_text += f"{role}: {content}\n\n"
                
                # Extract key themes for better action items
                if msg.get("isUser", False):
                    user_concerns.append(content)
                else:
                    therapist_suggestions.append(content)
            
            summary_prompt = f"""Based on this therapy session, provide a comprehensive summary with personalized action items.

THERAPEUTIC APPROACH: {therapeutic_approach}

CONVERSATION:
{conversation_text}

{memory_context if memory_context else ""}

Please analyze this conversation and provide:

1. **SUMMARY**: A compassionate 2-3 sentence summary highlighting the main topics discussed and progress made

2. **ACTION ITEMS**: 3-5 specific, actionable steps tailored to this client's situation. Make these:
   - Specific to what was discussed in this session
   - Realistic and achievable
   - Related to the coping strategies or insights mentioned
   - Personal to the client's expressed concerns

3. **INSIGHTS**: 2-3 observations about patterns, progress, or strengths noticed

IMPORTANT: Respond ONLY with valid JSON in this exact format:
{{
    "summary": "Your compassionate summary here",
    "action_items": [
        "Specific action based on conversation topic 1",
        "Specific action based on conversation topic 2", 
        "Specific action based on conversation topic 3"
    ],
    "insights": [
        "Insight about patterns or progress",
        "Insight about strengths or observations"
    ]
}}"""
            
            # Get the assistant's response using the LLM manager
            try:
                response_text = await llm_manager.generate_response(
                    message=summary_prompt,
                    context=[],
                    system_prompt="You are an expert therapist creating personalized session summaries. Focus on providing actionable, conversation-specific guidance.",
                    temperature=0.3,  # Lower temperature for consistency
                    max_tokens=1500
                )
            except Exception as llm_error:
                logger.warning(f"Error using LLM manager for session summary: {str(llm_error)}")
                logger.warning("Falling back to conversation-based summary")
                return await self._generate_conversation_based_summary(messages, therapeutic_approach)
            
            # Enhanced JSON parsing with multiple fallback strategies
            try:
                # First, try to extract clean JSON
                json_str = response_text.strip()
                
                # Remove common LLM response prefixes
                prefixes_to_remove = [
                    "Here is the session summary:",
                    "Based on the conversation, here is the summary:",
                    "Here's the session summary:",
                    "Session summary:"
                ]
                
                for prefix in prefixes_to_remove:
                    if json_str.lower().startswith(prefix.lower()):
                        json_str = json_str[len(prefix):].strip()
                
                # Handle markdown code blocks
                if "```json" in json_str:
                    json_str = json_str.split("```json")[1].split("```")[0].strip()
                elif "```" in json_str:
                    json_str = json_str.split("```")[1].strip()
                
                # Find JSON structure using regex if needed
                import re
                if not json_str.startswith('{'):
                    json_match = re.search(r'({[\s\S]*})', json_str)
                    if json_match:
                        json_str = json_match.group(1)
                
                logger.info(f"Attempting to parse JSON: {json_str[:200]}...")
                
                # Parse the JSON string
                result = json.loads(json_str)
                
                # Validate and clean the result
                result = await self._validate_and_clean_summary(result, messages)
                
                logger.info("Session summary generated successfully using LLM manager")
                return result
                
            except (json.JSONDecodeError, KeyError, ValueError) as e:
                logger.warning(f"Failed to parse LLM response as JSON: {str(e)}")
                logger.warning(f"Raw response: {response_text[:300]}...")
                return await self._generate_conversation_based_summary(messages, therapeutic_approach)
                
        except Exception as e:
            logger.error(f"Error generating session summary: {str(e)}")
            logger.error(traceback.format_exc())
            return await self._generate_conversation_based_summary(messages, therapeutic_approach)

    async def _validate_and_clean_summary(self, result: Dict[str, Any], messages: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Validate and clean the summary result, ensuring quality action items."""
        
        # Ensure result is a dictionary
        if not isinstance(result, dict):
            raise ValueError("Response is not a dictionary")
        
        # Validate summary
        if not result.get("summary") or len(result["summary"].strip()) < 20:
            result["summary"] = "Thank you for sharing your thoughts and feelings in this session. We explored important topics together."
        
        # Validate and improve action items
        action_items = result.get("action_items", [])
        if not action_items or len(action_items) == 0:
            # Generate basic action items based on conversation
            action_items = await self._generate_basic_action_items(messages)
        else:
            # Clean existing action items
            cleaned_items = []
            for item in action_items:
                if isinstance(item, str) and len(item.strip()) > 10:
                    cleaned_items.append(item.strip())
            
            if len(cleaned_items) < 2:
                # Add some basic items if we don't have enough
                basic_items = await self._generate_basic_action_items(messages)
                cleaned_items.extend(basic_items[:3])
            
            action_items = cleaned_items[:5]  # Limit to 5 items
        
        result["action_items"] = action_items
        
        # Validate insights
        insights = result.get("insights", [])
        if not insights:
            insights = [
                "You showed courage by sharing your experiences today",
                "Your self-awareness is a valuable strength"
            ]
        
        result["insights"] = insights
        
        return result

    async def _generate_basic_action_items(self, messages: List[Dict[str, Any]]) -> List[str]:
        """Generate basic action items based on conversation content."""
        
        # Extract keywords from user messages to create relevant action items
        user_messages = [msg.get('content', '').lower() for msg in messages if msg.get("isUser", False)]
        conversation_text = ' '.join(user_messages)
        
        action_items = []
        
        # Keyword-based action item suggestions
        if any(word in conversation_text for word in ['stress', 'anxious', 'worry', 'overwhelmed']):
            action_items.append("Practice deep breathing exercises when feeling stressed or anxious")
        
        if any(word in conversation_text for word in ['sleep', 'tired', 'exhausted']):
            action_items.append("Focus on improving your sleep routine and getting adequate rest")
        
        if any(word in conversation_text for word in ['relationship', 'family', 'friends', 'partner']):
            action_items.append("Consider having an open conversation with someone you trust")
        
        if any(word in conversation_text for word in ['work', 'job', 'career']):
            action_items.append("Take regular breaks during work to maintain balance")
        
        if any(word in conversation_text for word in ['exercise', 'physical', 'activity']):
            action_items.append("Incorporate some physical activity into your daily routine")
        
        # Add default items if we don't have enough specific ones
        default_items = [
            "Take time for self-reflection and journaling",
            "Practice mindfulness or meditation for a few minutes daily",
            "Engage in one activity that brings you joy this week",
            "Be kind and patient with yourself as you work through challenges"
        ]
        
        # Combine and ensure we have 3-4 items
        all_items = action_items + default_items
        return list(dict.fromkeys(all_items))[:4]  # Remove duplicates and limit to 4

    async def _generate_conversation_based_summary(self, messages: List[Dict[str, Any]], therapeutic_approach: str) -> Dict[str, Any]:
        """Generate a fallback summary based on conversation analysis."""
        
        logger.info("Generating conversation-based fallback summary")
        
        # Basic conversation analysis
        user_message_count = len([msg for msg in messages if msg.get("isUser", False)])
        therapist_message_count = len([msg for msg in messages if not msg.get("isUser", False)])
        
        # Generate summary based on conversation length and content
        if user_message_count > 5:
            summary = "Thank you for sharing so openly in today's session. We covered several important topics and explored different perspectives together."
        else:
            summary = "Thank you for taking the time to connect today. Even brief conversations can provide valuable insights."
        
        # Generate action items based on conversation
        action_items = await self._generate_basic_action_items(messages)
        
        insights = [
            f"You engaged thoughtfully in our conversation today",
            "Your willingness to explore these topics shows strength and self-awareness"
        ]
        
        return {
            "summary": summary,
            "action_items": action_items,
            "insights": insights
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