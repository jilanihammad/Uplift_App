import logging
import json
import traceback
from typing import Optional, List, Dict, Any
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from app.core.config import settings

logger = logging.getLogger(__name__)

class GroqService:
    def __init__(self):
        self.api_key = settings.GROQ_API_KEY
        
        # API endpoints
        self.groq_api_base_url = settings.GROQ_API_BASE_URL
        self.chat_completions_url = f"{self.groq_api_base_url}/chat/completions"
        
        # Models
        self.chat_model = settings.GROQ_LLM_MODEL_ID
        
        # Check if Groq is available
        self.available = bool(self.api_key) and bool(self.chat_model)
        
        logger.info(f"GroqService initialized with:")
        logger.info(f"API Base URL: {self.groq_api_base_url}")
        logger.info(f"Chat Model: {self.chat_model}")
        logger.info(f"API Key: {'Set' if self.api_key else 'Not set'}")
        logger.info(f"Service available: {'Yes' if self.available else 'No'}")
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def generate_response(self, 
                               message: str,
                               system_prompt: str = "",
                               model: str = None,
                               temperature: float = 0.7,
                               max_tokens: int = 1000,
                               context: List[Dict[str, str]] = None,
                               user_info: Optional[Dict[str, Any]] = None) -> str:
        """
        Generate a response using Groq's chat completions API
        
        Args:
            message: The user's message
            system_prompt: Optional system prompt
            model: Optional model override
            temperature: Temperature for generation
            max_tokens: Maximum tokens to generate
            context: Optional conversation history
            user_info: Additional user information
            
        Returns:
            Generated text response
        """
        if not self.available:
            logger.warning("Groq service unavailable - API key or model not set")
            raise Exception("Groq service unavailable - API key or model not set")
        
        try:
            # Prepare headers
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
            # Build messages array
            messages = []
            
            # Add system prompt if provided
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            else:
                # Default system prompt for a therapist
                default_prompt = """
                You are an AI therapist designed to provide supportive and empathetic conversations to users seeking mental health support. Your primary role is to listen actively to the user. Encourage them to share their thoughts and feelings by asking open-ended questions and providing space for them to express themselves. Show empathy by acknowledging and validating the user's emotions. Use phrases like 'That sounds really tough' or 'I can understand why you feel that way.' Adapt your responses based on the user's input. If they seem to need more support, offer comforting words. If they want to explore solutions, gently guide them towards that. Be prepared to discuss a wide range of mental health topics, including but not limited to depression, anxiety, stress, loneliness, and relationship issues.
                
                Guidelines:
                - Respond with empathy and genuine concern
                - Speak less and listen more
                - When the patient is crying, let them cry without interrupting them, be kind and patient
                - Ask thoughtful, open-ended questions to deepen understanding
                - Offer reflections and gentle observations
                - Suggest practical strategies when appropriate
                - Maintain professional boundaries
                - Encourage self-care and healthy habits
                - Never give medical advice or replace professional mental health care
                """
                messages.append({"role": "system", "content": default_prompt})
            
            # Add conversation history if provided
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            
            # Add current message
            messages.append({"role": "user", "content": message})
            
            # Use provided model or default
            model_to_use = model or self.chat_model
            
            # Prepare the request payload
            payload = {
                "model": model_to_use,
                "messages": messages,
                "temperature": temperature,
                "max_tokens": max_tokens
            }
            
            logger.info(f"Sending request to Groq API with model: {model_to_use}")
            
            # Make the API call using pooled HTTP client
            from app.core.http_client_manager import get_http_client_manager
            http_manager = get_http_client_manager()
            client = http_manager.get_client("groq")
            await client.start()
            
            response = await client.post(
                self.chat_completions_url,
                headers=headers,
                json=payload
            )

            if response.status_code != 200:
                logger.error(f"Error from Groq API: {response.status_code} - {response.text}")
                raise Exception(f"Error from Groq API: {response.status_code} - {response.text}")

            # Parse the response
            result = response.json()

            # Extract the assistant's message
            if "choices" in result and len(result["choices"]) > 0:
                assistant_message = result["choices"][0]["message"]["content"]
                logger.info(f"Successfully generated response with Groq")
                return assistant_message
            else:
                logger.error(f"Unexpected response format from Groq: {result}")
                raise Exception(f"Unexpected response format from Groq: {json.dumps(result)}")
                    
        except Exception as e:
            logger.error(f"Error generating response with Groq: {str(e)}")
            logger.error(traceback.format_exc())
            raise Exception(f"Error generating response with Groq: {str(e)}")
    
    async def test_api(self) -> Dict[str, Any]:
        """
        Test the Groq API key and connection
        
        Returns:
            Dictionary with test results
        """
        try:
            # Prepare the result dictionary
            result = {
                "available": True,
                "model": self.chat_model,
                "error": None
            }
            
            # Check if the key is set
            if not self.api_key:
                result["available"] = False
                result["error"] = "Groq API key is not set"
                return result
            
            try:
                # Prepare headers
                headers = {
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                }
                
                # Prepare a minimal test request
                payload = {
                    "model": self.chat_model,
                    "messages": [
                        {"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "Say hello"}
                    ],
                    "temperature": 0.7,
                    "max_tokens": 10
                }
                
                # Make the API call using pooled HTTP client
                from app.core.http_client_manager import get_http_client_manager
                http_manager = get_http_client_manager()
                client = http_manager.get_client("groq")
                await client.start()
                
                response = await client.post(
                    self.chat_completions_url,
                    headers=headers,
                    json=payload
                )

                if response.status_code == 200:
                    # API key is working
                    result["available"] = True
                    result["message"] = "API key is working correctly"
                    response_json = response.json()
                    result["model"] = response_json.get("model", self.chat_model)
                    self.available = True
                else:
                    # API key is not working
                    result["available"] = False
                    result["error"] = f"Error code: {response.status_code} - {response.text}"
                    self.available = False
                        
            except Exception as api_error:
                # Error making the API call
                result["available"] = False
                result["error"] = str(api_error)
                self.available = False
                
            return result
            
        except Exception as e:
            logger.error(f"Error testing Groq API: {str(e)}")
            logger.error(traceback.format_exc())
            return {
                "available": False,
                "error": str(e)
            }

    async def stream_chat_completion(self, 
                                   message: str,
                                   system_prompt: str = "",
                                   model: str = None,
                                   temperature: float = 0.7,
                                   max_tokens: int = 1000,
                                   context: List[Dict[str, str]] = None,
                                   user_info: Optional[Dict[str, Any]] = None):
        """
        Stream chat completion from Groq's API (yields content chunks as they arrive)
        """
        if not self.available:
            logger.warning("Groq service unavailable - API key or model not set")
            raise Exception("Groq service unavailable - API key or model not set")
        try:
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            messages = []
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            else:
                default_prompt = """
                You are an AI therapist designed to provide supportive and empathetic conversations to users seeking mental health support. Your primary role is to listen actively to the user. Encourage them to share their thoughts and feelings by asking open-ended questions and providing space for them to express themselves. Show empathy by acknowledging and validating the user's emotions. Use phrases like 'That sounds really tough' or 'I can understand why you feel that way.' Adapt your responses based on the user's input. If they seem to need more support, offer comforting words. If they want to explore solutions, gently guide them towards that. Be prepared to discuss a wide range of mental health topics, including but not limited to depression, anxiety, stress, loneliness, and relationship issues.
                
                Guidelines:
                - Respond with empathy and genuine concern
                - Speak less and listen more
                - When the patient is crying, let them cry without interrupting them, be kind and patient
                - Ask thoughtful, open-ended questions to deepen understanding
                - Offer reflections and gentle observations
                - Suggest practical strategies when appropriate
                - Maintain professional boundaries
                - Encourage self-care and healthy habits
                - Never give medical advice or replace professional mental health care
                """
                messages.append({"role": "system", "content": default_prompt})
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            messages.append({"role": "user", "content": message})
            model_to_use = model or self.chat_model
            payload = {
                "model": model_to_use,
                "messages": messages,
                "temperature": temperature,
                "max_tokens": max_tokens,
                "stream": True
            }
            logger.info(f"Streaming request to Groq API with model: {model_to_use}")
            # Use pooled HTTP client for streaming
            from app.core.http_client_manager import get_http_client_manager
            http_manager = get_http_client_manager()
            client = http_manager.get_client("groq")
            await client.start()
            
            async with client.client.stream("POST", self.chat_completions_url, headers=headers, json=payload) as response:
                    if response.status_code != 200:
                        logger.error(f"Error from Groq API (stream): {response.status_code} - {await response.aread()}")
                        raise Exception(f"Error from Groq API (stream): {response.status_code}")
                    async for line in response.aiter_lines():
                        if not line or not line.strip():
                            continue
                        if line.startswith("data: "):
                            data = line[len("data: "):]
                            if data.strip() == "[DONE]":
                                break
                            try:
                                chunk = json.loads(data)
                                # Extract the content delta
                                delta = chunk.get("choices", [{}])[0].get("delta", {})
                                content = delta.get("content")
                                if content:
                                    yield content
                            except Exception as e:
                                logger.warning(f"Error parsing Groq stream chunk: {e}")
                                continue
        except Exception as e:
            logger.error(f"Error streaming response with Groq: {str(e)}")
            logger.error(traceback.format_exc())
            raise Exception(f"Error streaming response with Groq: {str(e)}")

# Create a singleton instance
groq_service = GroqService() 