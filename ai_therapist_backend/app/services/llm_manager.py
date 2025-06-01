import logging
import httpx
import json
import os
import base64
import traceback
from typing import Optional, List, Dict, Any, AsyncGenerator
from tenacity import retry, stop_after_attempt, wait_exponential
from openai import OpenAI, AsyncOpenAI
from google import genai
from google.genai import types
import anthropic

from app.core.llm_config import LLMConfig, ModelType, ModelProvider, ModelConfig

logger = logging.getLogger(__name__)

class LLMManager:
    """
    Unified manager for all LLM operations. Routes requests to the appropriate
    provider based on the configuration in LLMConfig.
    """
    
    def __init__(self):
        """Initialize the LLM manager with current configuration."""
        self.llm_config = LLMConfig.get_active_model_config(ModelType.LLM)
        self.tts_config = LLMConfig.get_active_model_config(ModelType.TTS)
        self.transcription_config = LLMConfig.get_active_model_config(ModelType.TRANSCRIPTION)
        
        # Initialize clients based on active providers
        self._openai_client = None
        self._anthropic_client = None
        
        logger.info("LLMManager initialized with:")
        logger.info(f"LLM: {self.llm_config.provider if self.llm_config else 'None'} - {self.llm_config.model_id if self.llm_config else 'None'}")
        logger.info(f"TTS: {self.tts_config.provider if self.tts_config else 'None'} - {self.tts_config.model_id if self.tts_config else 'None'}")
        logger.info(f"Transcription: {self.transcription_config.provider if self.transcription_config else 'None'} - {self.transcription_config.model_id if self.transcription_config else 'None'}")
    
    def _get_openai_client(self, config: ModelConfig) -> OpenAI:
        """Get a new OpenAI client for the given configuration (no caching)."""
        api_key = LLMConfig.get_api_key(config)
        if not api_key:
            raise ValueError(f"API key not found for {config.api_key_env}")
        if config.provider == ModelProvider.AZURE_OPENAI:
            return OpenAI(
                api_key=api_key,
                base_url=f"{config.base_url}/openai/deployments/{config.model_id}",
                default_headers={"api-version": config.default_params.get("api_version", "2024-02-15-preview")}
            )
        else:
            return OpenAI(
                api_key=api_key,
                base_url=config.base_url
            )
    
    def _get_anthropic_client(self, config: ModelConfig) -> anthropic.AsyncAnthropic:
        """Get or create Anthropic client for the given configuration."""
        if not self._anthropic_client:
            api_key = LLMConfig.get_api_key(config)
            if not api_key:
                raise ValueError(f"API key not found for {config.api_key_env}")
            
            self._anthropic_client = anthropic.AsyncAnthropic(api_key=api_key)
        return self._anthropic_client
    
    # =============================================================================
    # LLM CHAT COMPLETION METHODS
    # =============================================================================
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def generate_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> str:
        """
        Generate a chat response using the active LLM provider.
        
        Args:
            message: The user's message
            context: List of previous messages in the conversation
            system_prompt: Optional system prompt to guide the model
            user_info: Additional user information for personalization
            **kwargs: Additional parameters to override defaults
            
        Returns:
            The AI response text
        """
        if not self.llm_config:
            raise ValueError("No LLM configuration available")
        
        if not LLMConfig.is_model_available(ModelType.LLM):
            raise ValueError("LLM service unavailable - API key not set")
        
        # Route to appropriate provider
        if self.llm_config.provider in [ModelProvider.OPENAI, ModelProvider.GROQ, ModelProvider.AZURE_OPENAI]:
            return await self._generate_openai_compatible_response(message, context, system_prompt, user_info, **kwargs)
        elif self.llm_config.provider == ModelProvider.ANTHROPIC:
            return await self._generate_anthropic_response(message, context, system_prompt, user_info, **kwargs)
        elif self.llm_config.provider == ModelProvider.DEEPSEEK:
            return await self._generate_deepseek_response(message, context, system_prompt, user_info, **kwargs)
        elif self.llm_config.provider == ModelProvider.GOOGLE:
            return await self._generate_google_response(message, context, system_prompt, user_info, **kwargs)
        else:
            raise ValueError(f"Unsupported LLM provider: {self.llm_config.provider}")
    
    async def _generate_openai_compatible_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> str:
        """Generate response using OpenAI-compatible API (OpenAI, Groq, Azure OpenAI)."""
        try:
            client = self._get_openai_client(self.llm_config)
            
            # Build messages array
            messages = []
            
            # Add system prompt
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            elif user_info:
                # Build system prompt from user info if provided
                system_prompt = self._build_system_prompt(user_info)
                messages.append({"role": "system", "content": system_prompt})
            
            # Add conversation history
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            
            # Add current message
            messages.append({"role": "user", "content": message})
            
            # Prepare parameters
            params = self.llm_config.default_params.copy()
            params.update(kwargs)
            # Remove model from params if it exists to avoid duplicate parameter error
            params.pop('model', None)
            
            # Make API call
            completion = client.chat.completions.create(
                model=self.llm_config.model_id,
                messages=messages,
                **params
            )
            
            return completion.choices[0].message.content
            
        except Exception as e:
            logger.error(f"Error generating OpenAI-compatible response: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    async def _generate_anthropic_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> str:
        """Generate response using Anthropic Claude API."""
        try:
            client = self._get_anthropic_client(self.llm_config)
            
            # Build messages array (Anthropic format)
            messages = []
            
            # Add conversation history
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            
            # Add current message
            messages.append({"role": "user", "content": message})
            
            # Prepare system prompt
            if not system_prompt and user_info:
                system_prompt = self._build_system_prompt(user_info)
            
            # Prepare parameters
            params = self.llm_config.default_params.copy()
            params.update(kwargs)
            # Remove model from params if it exists to avoid duplicate parameter error
            params.pop('model', None)
            
            # Make API call
            response = await client.messages.create(
                model=self.llm_config.model_id,
                system=system_prompt if system_prompt else "You are a helpful AI assistant.",
                messages=messages,
                **params
            )
            
            return response.content[0].text
            
        except Exception as e:
            logger.error(f"Error generating Anthropic response: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    async def _generate_deepseek_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> str:
        """Generate response using DeepSeek API."""
        try:
            # DeepSeek uses OpenAI-compatible API
            api_key = LLMConfig.get_api_key(self.llm_config)
            if not api_key:
                raise ValueError("DeepSeek API key not found")
            
            # Build messages array
            messages = []
            
            # Add system prompt
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            elif user_info:
                system_prompt = self._build_system_prompt(user_info)
                messages.append({"role": "system", "content": system_prompt})
            
            # Add conversation history
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            
            # Add current message
            messages.append({"role": "user", "content": message})
            
            # Prepare parameters
            params = self.llm_config.default_params.copy()
            params.update(kwargs)
            
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }
            
            payload = {
                "model": self.llm_config.model_id,
                "messages": messages,
                **params
            }
            
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    f"{self.llm_config.base_url}/chat/completions",
                    headers=headers,
                    json=payload
                )
                
                response.raise_for_status()
                result = response.json()
                
                return result["choices"][0]["message"]["content"]
            
        except Exception as e:
            logger.error(f"Error generating DeepSeek response: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    async def _generate_google_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> str:
        """Generate response using Google Gemini API via new GenAI SDK."""
        try:
            api_key = LLMConfig.get_api_key(self.llm_config)
            if not api_key:
                raise ValueError("Google API key not found")

            # Initialize client with new SDK
            client = genai.Client(api_key=api_key)

            # Prepare system instruction
            system_instruction_text = system_prompt
            if not system_instruction_text and user_info:
                system_instruction_text = self._build_system_prompt(user_info)

            # Build conversation contents for new SDK
            contents = []
            
            # Add conversation history first
            if context:
                for msg_from_frontend in context:
                    # Fix: Use correct field name that frontend sends
                    is_user = msg_from_frontend.get("isUser", False)
                    content = msg_from_frontend.get("content", "")
                    
                    if is_user:
                        contents.append({
                            "role": "user",
                            "parts": [{"text": content}]
                        })
                    else:
                        contents.append({
                            "role": "model", 
                            "parts": [{"text": content}]
                        })
            
            # Add current user message
            contents.append({
                "role": "user",
                "parts": [{"text": message}]
            })

            # Prepare generation configuration
            gen_config_params = self.llm_config.default_params.copy()
            gen_config_params.update(kwargs)

            # Create request config for new SDK - FIX: Use correct structure
            request_config = {}
            if system_instruction_text:
                request_config["system_instruction"] = system_instruction_text
            
            # Map parameters to new SDK format - FIX: Don't nest in generation_config
            if "temperature" in gen_config_params:
                request_config["temperature"] = gen_config_params.get("temperature", 0.7)
            if "max_tokens" in gen_config_params:
                request_config["max_output_tokens"] = gen_config_params.get("max_tokens", 1000)
            elif "maxOutputTokens" in gen_config_params:
                request_config["max_output_tokens"] = gen_config_params.get("maxOutputTokens", 1000)
            else:
                request_config["max_output_tokens"] = 1000
            if "top_p" in gen_config_params:
                request_config["top_p"] = gen_config_params.get("top_p", 1.0)
            if "top_k" in gen_config_params:
                request_config["top_k"] = gen_config_params.get("top_k")

            logger.debug(f"Sending to Google Gemini: model={self.llm_config.model_id}, system_instruction_present={bool(system_instruction_text)}, contents_length={len(contents)}")
            
            # Generate response using new SDK
            response = client.models.generate_content(
                model=self.llm_config.model_id,
                contents=contents,
                config=request_config
            )
            
            # Extract text from response
            if hasattr(response, 'text') and response.text:
                return response.text
            elif hasattr(response, 'candidates') and response.candidates:
                # Try to extract from candidates structure
                candidate = response.candidates[0]
                if hasattr(candidate, 'content') and candidate.content:
                    if hasattr(candidate.content, 'parts') and candidate.content.parts:
                        return candidate.content.parts[0].text
                    elif hasattr(candidate.content, 'text'):
                        return candidate.content.text
            
            logger.error(f"Could not extract text from Google response. Response structure: {response}")
            raise ValueError("Failed to extract text from Google Gemini response")

        except Exception as e:
            logger.error(f"Error generating Google response using new SDK: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    # =============================================================================
    # STREAMING METHODS
    # =============================================================================
    
    async def stream_chat_completion(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> AsyncGenerator[str, None]:
        """
        Stream chat completion from the active LLM provider.
        
        Args:
            message: The user's message
            context: List of previous messages in the conversation
            system_prompt: Optional system prompt to guide the model
            user_info: Additional user information for personalization
            **kwargs: Additional parameters to override defaults
            
        Yields:
            Streaming text chunks from the AI response
        """
        if not self.llm_config:
            raise ValueError("No LLM configuration available")
        
        if not LLMConfig.is_model_available(ModelType.LLM):
            raise ValueError("LLM service unavailable - API key not set")
        
        if not self.llm_config.supports_streaming:
            # Fall back to non-streaming if provider doesn't support it
            logger.info(f"Provider {self.llm_config.provider} ({self.llm_config.model_id}) does not support streaming or it's disabled. Falling back to non-streaming.")
            response = await self.generate_response(message, context, system_prompt, user_info, **kwargs)
            yield response
            return
        
        # Route to appropriate provider for streaming
        if self.llm_config.provider in [ModelProvider.OPENAI, ModelProvider.GROQ, ModelProvider.AZURE_OPENAI]:
            async for chunk in self._stream_openai_compatible_response(message, context, system_prompt, user_info, **kwargs):
                yield chunk
        elif self.llm_config.provider == ModelProvider.ANTHROPIC:
            async for chunk in self._stream_anthropic_response(message, context, system_prompt, user_info, **kwargs):
                yield chunk
        elif self.llm_config.provider == ModelProvider.GOOGLE: # New case for Google streaming
            async for chunk in self._stream_google_response(message, context, system_prompt, user_info, **kwargs):
                yield chunk
        else:
            # Fall back to non-streaming for unsupported providers if streaming flag was somehow true
            logger.warning(f"Streaming not implemented for provider {self.llm_config.provider} ({self.llm_config.model_id}), but supports_streaming is True. Falling back to non-streaming.")
            response = await self.generate_response(message, context, system_prompt, user_info, **kwargs)
            yield response
    
    async def _stream_openai_compatible_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> AsyncGenerator[str, None]:
        """Stream response using OpenAI-compatible API."""
        try:
            client = self._get_openai_client(self.llm_config)
            
            # Build messages array
            messages = []
            
            # Add system prompt
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            elif user_info:
                system_prompt = self._build_system_prompt(user_info)
                messages.append({"role": "system", "content": system_prompt})
            
            # Add conversation history
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            
            # Add current message
            messages.append({"role": "user", "content": message})
            
            # Prepare parameters
            params = self.llm_config.default_params.copy()
            params.update(kwargs)
            params["stream"] = True
            # Remove model from params if it exists to avoid duplicate parameter error
            params.pop('model', None)
            
            # Make streaming API call
            stream = client.chat.completions.create(
                model=self.llm_config.model_id,
                messages=messages,
                **params
            )
            
            for chunk in stream:
                if chunk.choices[0].delta.content is not None:
                    yield chunk.choices[0].delta.content
            
        except Exception as e:
            logger.error(f"Error streaming OpenAI-compatible response: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    async def _stream_anthropic_response(
        self, 
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> AsyncGenerator[str, None]:
        """Stream response using Anthropic Claude API."""
        try:
            client = self._get_anthropic_client(self.llm_config)
            
            # Build messages array
            messages = []
            
            # Add conversation history
            if context:
                for msg in context:
                    role = "user" if msg.get("isUser", False) else "assistant"
                    messages.append({"role": role, "content": msg.get("content", "")})
            
            # Add current message
            messages.append({"role": "user", "content": message})
            
            # Prepare system prompt
            if not system_prompt and user_info:
                system_prompt = self._build_system_prompt(user_info)
            
            # Prepare parameters
            params = self.llm_config.default_params.copy()
            params.update(kwargs)
            # Remove model from params if it exists to avoid duplicate parameter error
            params.pop('model', None)
            
            # Make streaming API call
            async with client.messages.stream(
                model=self.llm_config.model_id,
                system=system_prompt if system_prompt else "You are a helpful AI assistant.",
                messages=messages,
                **params
            ) as stream:
                async for text in stream.text_stream:
                    yield text
            
        except Exception as e:
            logger.error(f"Error streaming Anthropic response: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    async def _stream_google_response(
        self,
        message: str,
        context: List[Dict[str, str]] = None,
        system_prompt: str = "",
        user_info: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> AsyncGenerator[str, None]:
        """Stream response using Google Gemini API via new GenAI SDK."""
        try:
            api_key = LLMConfig.get_api_key(self.llm_config)
            if not api_key:
                raise ValueError("Google API key not found")

            # Initialize client with new SDK
            client = genai.Client(api_key=api_key)

            # Prepare system instruction
            system_instruction_text = system_prompt
            if not system_instruction_text and user_info:
                system_instruction_text = self._build_system_prompt(user_info)

            # Build conversation contents for new SDK
            contents = []
            
            # Add conversation history first
            if context:
                for msg_from_frontend in context:
                    # Fix: Use correct field name that frontend sends
                    is_user = msg_from_frontend.get("isUser", False)
                    content = msg_from_frontend.get("content", "")
                    
                    if is_user:
                        contents.append({
                            "role": "user",
                            "parts": [{"text": content}]
                        })
                    else:
                        contents.append({
                            "role": "model", 
                            "parts": [{"text": content}]
                        })
            
            # Add current user message
            contents.append({
                "role": "user",
                "parts": [{"text": message}]
            })

            # Prepare generation configuration
            gen_config_params = self.llm_config.default_params.copy()
            gen_config_params.update(kwargs)

            # Create request config for new SDK - FIX: Use correct structure
            request_config = {}
            if system_instruction_text:
                request_config["system_instruction"] = system_instruction_text
            
            # Map parameters to new SDK format - FIX: Don't nest in generation_config
            if "temperature" in gen_config_params:
                request_config["temperature"] = gen_config_params.get("temperature", 0.7)
            if "max_tokens" in gen_config_params:
                request_config["max_output_tokens"] = gen_config_params.get("max_tokens", 1000)
            elif "maxOutputTokens" in gen_config_params:
                request_config["max_output_tokens"] = gen_config_params.get("maxOutputTokens", 1000)
            else:
                request_config["max_output_tokens"] = 1000
            if "top_p" in gen_config_params:
                request_config["top_p"] = gen_config_params.get("top_p", 1.0)
            if "top_k" in gen_config_params:
                request_config["top_k"] = gen_config_params.get("top_k")

            logger.debug(f"Streaming from Google Gemini: model={self.llm_config.model_id}, system_instruction_present={bool(system_instruction_text)}, contents_length={len(contents)}")

            # Stream response using new SDK
            stream = client.models.generate_content_stream(
                model=self.llm_config.model_id,
                contents=contents,
                config=request_config
            )

            async for chunk in stream:
                # Extract text from streaming chunk
                if hasattr(chunk, 'text') and chunk.text:
                    yield chunk.text
                elif hasattr(chunk, 'candidates') and chunk.candidates:
                    candidate = chunk.candidates[0]
                    if hasattr(candidate, 'content') and candidate.content:
                        if hasattr(candidate.content, 'parts') and candidate.content.parts:
                            for part in candidate.content.parts:
                                if hasattr(part, 'text') and part.text:
                                    yield part.text
                        elif hasattr(candidate.content, 'text') and candidate.content.text:
                            yield candidate.content.text

        except Exception as e:
            logger.error(f"Error streaming Google response using new SDK: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    # =============================================================================
    # TEXT-TO-SPEECH METHODS
    # =============================================================================
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def text_to_speech(self, text: str, output_file: str, response_format: Optional[str] = None, voice: Optional[str] = None, **kwargs):
        """
        Convert text to speech using the active TTS provider.
        Args:
            text: Text to convert to speech
            output_file: Path to save the audio file
            response_format: Audio format to return (e.g., 'mp3', 'opus'). Defaults to 'opus'.
            voice: Voice to use (optional)
            **kwargs: Additional parameters to override defaults
        Returns:
            True if successful, False otherwise
        """
        response_format = response_format or "opus"
        # Ensure file extension matches format
        if response_format in ["opus", "ogg_opus"]:
            if not output_file.endswith(".ogg"):
                output_file = output_file.rsplit(".", 1)[0] + ".ogg"
        elif response_format == "mp3":
            if not output_file.endswith(".mp3"):
                output_file = output_file.rsplit(".", 1)[0] + ".mp3"
        if not self.tts_config:
            raise ValueError("No TTS configuration available")
        if not LLMConfig.is_model_available(ModelType.TTS):
            raise ValueError("TTS service unavailable - API key not set")
        # Route to appropriate provider
        if self.tts_config.provider in [ModelProvider.OPENAI, ModelProvider.GROQ]:
            return await self._openai_text_to_speech(text, voice=voice, response_format=response_format, **kwargs)
        else:
            raise ValueError(f"Unsupported TTS provider: {self.tts_config.provider}")

    async def _openai_text_to_speech(self, text: str, voice: Optional[str] = None, response_format: Optional[str] = None, **kwargs) -> str:
        """Convert text to speech using OpenAI TTS API and return base64-encoded audio data."""
        try:
            client = self._get_openai_client(self.tts_config)
            # Prepare parameters
            params = self.tts_config.default_params.copy()
            params.update(kwargs)
            # Remove model from params if it exists to avoid duplicate parameter error
            params.pop('model', None)
            if voice:
                params['voice'] = voice
            if response_format:
                params['response_format'] = response_format
            else:
                response_format = params.get('response_format', 'mp3')
            # Make API call
            response = client.audio.speech.create(
                model=self.tts_config.model_id,
                input=text,
                **params
            )
            # Read audio bytes
            audio_bytes = response.content if hasattr(response, 'content') else response.read()
            # Encode to base64 for API response
            audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
            return audio_b64
        except Exception as e:
            logger.error(f"Error in OpenAI text-to-speech: {str(e)}")
            logger.error(traceback.format_exc())
            return ""
    
    async def stream_text_to_speech(self, text: str, voice: Optional[str] = None, response_format: Optional[str] = None, **kwargs):
        """
        Stream text-to-speech audio chunks as base64-encoded strings.
        Args:
            text: Text to convert to speech
            voice: Voice to use (optional)
            response_format: Audio format to return (e.g., 'mp3', 'opus'). Defaults to 'opus'.
            **kwargs: Additional parameters to override defaults
        Yields:
            Base64-encoded audio chunks
        """
        response_format = response_format or "opus"
        if not self.tts_config:
            raise ValueError("No TTS configuration available")
        if not LLMConfig.is_model_available(ModelType.TTS):
            raise ValueError("TTS service unavailable - API key not set")
        if self.tts_config.provider == ModelProvider.OPENAI:
            # Use httpx for streaming since OpenAI SDK may not support TTS streaming yet
            api_key = LLMConfig.get_api_key(self.tts_config)
            url = f"{self.tts_config.base_url}/audio/speech"
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }
            params = self.tts_config.default_params.copy()
            params.update(kwargs)
            if voice:
                params['voice'] = voice
            if response_format:
                params['response_format'] = response_format
            else:
                response_format = params.get('response_format', 'mp3')
            payload = {
                "model": self.tts_config.model_id,
                "input": text,
                "voice": params['voice'],
                "response_format": response_format,
                "stream": True
            }
            import httpx
            async with httpx.AsyncClient(timeout=120.0) as client:
                async with client.stream("POST", url, headers=headers, json=payload, timeout=120.0) as resp:
                    if resp.status_code != 200:
                        detail = await resp.aread()
                        raise Exception(f"TTS streaming failed: {resp.status_code} {detail}")
                    async for chunk in resp.aiter_bytes():
                        if chunk:
                            b64_chunk = base64.b64encode(chunk).decode('utf-8')
                            yield b64_chunk
        else:
            raise ValueError(f"Streaming TTS not implemented for provider: {self.tts_config.provider}")
    
    # =============================================================================
    # TRANSCRIPTION METHODS
    # =============================================================================
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    async def transcribe_audio(self, audio_file_path: str, **kwargs) -> str:
        """
        Transcribe audio using the active transcription provider.
        
        Args:
            audio_file_path: Path to the audio file
            **kwargs: Additional parameters to override defaults
            
        Returns:
            Transcribed text
        """
        if not self.transcription_config:
            raise ValueError("No transcription configuration available")
        
        if not LLMConfig.is_model_available(ModelType.TRANSCRIPTION):
            raise ValueError("Transcription service unavailable - API key not set")
        
        # Route to appropriate provider
        if self.transcription_config.provider in [ModelProvider.OPENAI, ModelProvider.GROQ]:
            return await self._openai_transcribe_audio(audio_file_path, **kwargs)
        else:
            raise ValueError(f"Unsupported transcription provider: {self.transcription_config.provider}")
    
    async def _openai_transcribe_audio(self, audio_file_path: str, **kwargs) -> str:
        """Transcribe audio using OpenAI Whisper API."""
        try:
            if not os.path.exists(audio_file_path):
                raise FileNotFoundError(f"Audio file not found: {audio_file_path}")
            
            client = self._get_openai_client(self.transcription_config)
            
            # Prepare parameters - remove 'model' from kwargs to avoid duplicate
            params = self.transcription_config.default_params.copy()
            params.update(kwargs)
            # Remove model from params if it exists to avoid duplicate parameter error
            params.pop('model', None)
            
            # Make API call
            with open(audio_file_path, 'rb') as audio_file:
                transcript = client.audio.transcriptions.create(
                    model=self.transcription_config.model_id,
                    file=audio_file,
                    **params
                )
            
            return transcript.text
            
        except Exception as e:
            logger.error(f"Error in OpenAI transcription: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
    # =============================================================================
    # UTILITY METHODS
    # =============================================================================
    
    def _build_system_prompt(self, user_info: Optional[Dict[str, Any]] = None) -> str:
        """Build a personalized system prompt based on user information."""
        base_prompt = """
        You are an AI therapist designed to provide supportive and empathetic conversations to users seeking mental health support. Your primary role is to listen actively to the user. Encourage them to share their thoughts and feelings by asking open-ended questions and providing space for them to express themselves. Show empathy by acknowledging and validating the user's emotions. Use phrases like 'That sounds really tough' or 'I can understand why you feel that way.' Adapt your responses based on the user's input. If they seem to need more support, offer comforting words. If they want to explore solutions, gently guide them towards that. Be prepared to discuss a wide range of mental health topics, including but not limited to depression, anxiety, stress, loneliness, and relationship issues. Recognize when a user's situation might require professional intervention and gently suggest seeking help from a human therapist or counselor. Always remember that you are an AI, not a human therapist. Make this clear to the user and emphasize that while you can provide support, you are not a substitute for professional mental health care. Respect the user's privacy and do not store or share any personal information. Be mindful of cultural differences and avoid making assumptions based on stereotypes. Show respect for the user's background and experiences. Use a warm, friendly, and conversational tone. Avoid jargon or overly technical language unless the user specifically requests it. Guide the conversation gently, ensuring it stays focused on the user's needs. Use techniques like reflective listening and summarizing to show understanding. Be patient and allow the user time to express themselves. Do not rush the conversation or push for quick resolutions. If the user mentions thoughts of self-harm or suicide, respond with immediate concern and strongly encourage them to seek help from a mental health professional or a crisis hotline. Provide resources if possible. Celebrate the user's progress and efforts, even small steps. Use encouraging language to motivate them. Maintain a consistent and caring persona throughout the conversation, so the user feels a sense of continuity and trust
        
        Guidelines:
        - Respond with empathy and genuine concern
        - Speak less and listen more
        - When the patient, client or customer is crying, let them cry without interrupting them, be kind and patient
        - Ask thoughtful, open-ended questions to deepen understanding
        - Offer reflections and gentle observations
        - Suggest practical strategies when appropriate
        - Maintain professional boundaries
        - Encourage self-care and healthy habits
        - Never give medical advice or replace professional mental health care
        """
        
        if not user_info:
            return base_prompt
        
        # Add personalization based on user_info
        personalization = []
        
        if "name" in user_info:
            personalization.append(f"You're speaking with {user_info['name']}.")
        
        if "assessment" in user_info and user_info["assessment"]:
            assessment = user_info["assessment"]
            
            if "primary_goal" in assessment:
                personalization.append(
                    f"Their primary therapy goal is {assessment['primary_goal']}."
                )
            
            if "challenges" in assessment and assessment["challenges"]:
                challenges = ", ".join(assessment["challenges"])
                personalization.append(
                    f"They're currently dealing with: {challenges}."
                )
            
            if "preferred_approach" in assessment:
                approach = assessment["preferred_approach"]
                if approach == "practical":
                    personalization.append(
                        "They prefer a practical, solution-focused approach."
                    )
                elif approach == "emotional":
                    personalization.append(
                        "They prefer emotional support and validation."
                    )
                elif approach == "balanced":
                    personalization.append(
                        "They prefer a balance of practical advice and emotional support."
                    )
        
        if personalization:
            return base_prompt + "\n\n" + "\n".join(personalization)
        
        return base_prompt
    
    async def test_api(self) -> Dict[str, Any]:
        """Test all active API configurations."""
        results = {}
        
        # Test LLM
        if self.llm_config:
            try:
                test_response = await self.generate_response(
                    "Say hello", 
                    max_tokens=10,
                    temperature=0.1
                )
                results["llm"] = {
                    "available": True,
                    "provider": self.llm_config.provider,
                    "model": self.llm_config.model_id,
                    "message": "LLM test successful"
                }
            except Exception as e:
                results["llm"] = {
                    "available": False,
                    "provider": self.llm_config.provider,
                    "model": self.llm_config.model_id,
                    "error": str(e)
                }
        else:
            results["llm"] = {
                "available": False,
                "error": "No LLM configuration available"
            }
        
        # Test TTS
        if self.tts_config:
            results["tts"] = {
                "available": LLMConfig.is_model_available(ModelType.TTS),
                "provider": self.tts_config.provider,
                "model": self.tts_config.model_id,
                "message": "TTS configuration available" if LLMConfig.is_model_available(ModelType.TTS) else "TTS API key not available"
            }
        else:
            results["tts"] = {
                "available": False,
                "error": "No TTS configuration available"
            }
        
        # Test Transcription
        if self.transcription_config:
            results["transcription"] = {
                "available": LLMConfig.is_model_available(ModelType.TRANSCRIPTION),
                "provider": self.transcription_config.provider,
                "model": self.transcription_config.model_id,
                "message": "Transcription configuration available" if LLMConfig.is_model_available(ModelType.TRANSCRIPTION) else "Transcription API key not available"
            }
        else:
            results["transcription"] = {
                "available": False,
                "error": "No transcription configuration available"
            }
        
        return results
    
    def get_status(self) -> Dict[str, Any]:
        """Get status of all configured services."""
        return {
            "model_info": LLMConfig.get_model_info(),
            "configurations": {
                "llm": {
                    "provider": self.llm_config.provider if self.llm_config else None,
                    "model": self.llm_config.model_id if self.llm_config else None,
                    "supports_streaming": self.llm_config.supports_streaming if self.llm_config else False,
                    "available": LLMConfig.is_model_available(ModelType.LLM)
                },
                "tts": {
                    "provider": self.tts_config.provider if self.tts_config else None,
                    "model": self.tts_config.model_id if self.tts_config else None,
                    "available": LLMConfig.is_model_available(ModelType.TTS)
                },
                "transcription": {
                    "provider": self.transcription_config.provider if self.transcription_config else None,
                    "model": self.transcription_config.model_id if self.transcription_config else None,
                    "available": LLMConfig.is_model_available(ModelType.TRANSCRIPTION)
                }
            },
            "available_providers": {
                "llm": LLMConfig.list_available_providers(ModelType.LLM),
                "tts": LLMConfig.list_available_providers(ModelType.TTS),
                "transcription": LLMConfig.list_available_providers(ModelType.TRANSCRIPTION)
            }
        }

# Create singleton instance
llm_manager = LLMManager() 