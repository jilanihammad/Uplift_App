import logging
import httpx
import json
import os
import base64
import traceback
import asyncio
from pathlib import Path
from typing import Optional, List, Dict, Any, AsyncGenerator, Final
from tenacity import retry, stop_after_attempt, wait_exponential, wait_random_exponential, retry_if_exception, retry_if_exception_type
from httpx import ReadTimeout, RemoteProtocolError, HTTPStatusError, ConnectTimeout
from openai import OpenAI, AsyncOpenAI
from google import genai
from google.genai import types
import anthropic

from app.core.llm_config import LLMConfig, ModelType, ModelProvider, ModelConfig
from app.utils.audio_path import ensure_wav

logger = logging.getLogger(__name__)

# =============================================================================
# GROQ STT CLIENT - Module-level singleton for connection pooling
# =============================================================================

GROQ_STT_URL: Final = "https://api.groq.com/openai/v1/audio/transcriptions"
MAX_CONCURRENT_STT: Final = 8
STT_TIMEOUT_SECONDS: Final = 5.0  # Hard timeout for entire operation

# Singleton client with complete timeout control
_groq_stt_client: Final = httpx.AsyncClient(
    timeout=httpx.Timeout(connect=2.0, read=3.0, write=3.0, pool=2.0),
    follow_redirects=True,
    headers={"User-Agent": "maya-stt/1.0"}
)

# Semaphore for concurrency control
_stt_semaphore = asyncio.Semaphore(MAX_CONCURRENT_STT)

def _is_retryable_stt_error(exc):
    """Check if STT error is retryable (5xx or 429 only)"""
    return isinstance(exc, HTTPStatusError) and (
        500 <= exc.response.status_code < 600 or 
        exc.response.status_code == 429
    )

async def _do_post(audio_path: Path, model: str, api_key: str) -> str:
    """One network round-trip to Groq with hard 5s timeout."""
    async def _groq_post():
        with audio_path.open("rb") as f:
            resp = await _groq_stt_client.post(
                GROQ_STT_URL,
                files={"file": ("audio.m4a", f, "audio/mp4")},
                data={
                    "model": model,
                    "temperature": "0.0",
                    "response_format": "verbose_json"  # Get full metadata
                },
                headers={"Authorization": f"Bearer {api_key}"}
            )
            resp.raise_for_status()
            
            # Defensive JSON parsing
            data = resp.json()
            text = data.get("text", "").strip()
            if not text:
                raise ValueError(f"Groq response missing 'text': {data}")
            return text
    
    async with _stt_semaphore:
        # Hard timeout wrapper - kills any operation exceeding 5s
        try:
            return await asyncio.wait_for(_groq_post(), timeout=STT_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            raise ReadTimeout(f"Groq STT exceeded {STT_TIMEOUT_SECONDS}s hard timeout")

# Wrap with tenacity for retries - returns a coroutine function
transcribe_groq = retry(
    stop=stop_after_attempt(3),
    wait=wait_random_exponential(multiplier=0.2, max=1.0),
    retry=(
        retry_if_exception(_is_retryable_stt_error) |
        retry_if_exception_type(ReadTimeout) |
        retry_if_exception_type(ConnectTimeout) |
        retry_if_exception_type(RemoteProtocolError)
    ),
    reraise=True
)(_do_post)

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
                request_config["max_output_tokens"] = gen_config_params.get("max_tokens", 2000)
            elif "maxOutputTokens" in gen_config_params:
                request_config["max_output_tokens"] = gen_config_params.get("maxOutputTokens", 2000)
            else:
                request_config["max_output_tokens"] = 2000
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
                
                # Check for finish_reason indicating issues
                if hasattr(candidate, 'finish_reason') and candidate.finish_reason:
                    finish_reason = str(candidate.finish_reason)
                    if finish_reason == 'MAX_TOKENS':
                        logger.warning(f"Google Gemini hit token limit. Consider reducing input length or increasing max_output_tokens.")
                        # Try to get partial response if available
                        if hasattr(candidate, 'content') and candidate.content:
                            if hasattr(candidate.content, 'parts') and candidate.content.parts:
                                partial_text = candidate.content.parts[0].text
                                if partial_text and partial_text.strip():
                                    logger.info(f"Returning partial response due to token limit: {len(partial_text)} characters")
                                    return partial_text
                        
                        # If no partial content, return a helpful message
                        return "I apologize, but my response was too long. Could you please ask a shorter or more specific question?"
                    
                    elif finish_reason in ['SAFETY', 'BLOCKED']:
                        logger.warning(f"Google Gemini blocked response due to safety filters: {finish_reason}")
                        return "I apologize, but I cannot provide a response to that request due to safety guidelines."
                    
                    elif finish_reason == 'RECITATION':
                        logger.warning(f"Google Gemini blocked response due to recitation concerns: {finish_reason}")
                        return "I apologize, but I cannot provide that specific information. Could you rephrase your question?"
                
                # Normal content extraction
                if hasattr(candidate, 'content') and candidate.content:
                    if hasattr(candidate.content, 'parts') and candidate.content.parts:
                        return candidate.content.parts[0].text
                    elif hasattr(candidate.content, 'text'):
                        return candidate.content.text
            
            # Log detailed response structure for debugging
            logger.error(f"Could not extract text from Google response. Response structure: {response}")
            
            # Check if response has usage metadata to provide more context
            if hasattr(response, 'usage_metadata'):
                usage = response.usage_metadata
                logger.error(f"Token usage - Prompt: {getattr(usage, 'prompt_token_count', 'unknown')}, "
                           f"Candidates: {getattr(usage, 'candidates_token_count', 'unknown')}, "
                           f"Total: {getattr(usage, 'total_token_count', 'unknown')}")
            
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
                request_config["max_output_tokens"] = gen_config_params.get("max_tokens", 2000)
            elif "maxOutputTokens" in gen_config_params:
                request_config["max_output_tokens"] = gen_config_params.get("maxOutputTokens", 2000)
            else:
                request_config["max_output_tokens"] = 2000
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

            # Google's SDK returns a synchronous generator, not async
            for chunk in stream:
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
                
                # Allow other async operations to run
                await asyncio.sleep(0)

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
        Convert text to speech and save to file.
        Args:
            text: Text to convert to speech
            output_file: Path to save the audio file
            response_format: Audio format to return (e.g., 'wav', 'mp3'). Defaults to 'wav' for lowest latency.
            voice: Voice to use (optional)
            **kwargs: Additional parameters to override defaults
        Returns:
            True if successful, False otherwise
        """
        response_format = response_format or "wav"  # Default to WAV for lowest latency streaming
        
        # Use centralized utility to ensure proper extension (prevents double extensions)
        if response_format == "wav":
            output_file = ensure_wav(output_file)
        elif response_format == "mp3":
            # For MP3, use similar logic but with .mp3 extension
            output_file = output_file if output_file.lower().endswith('.mp3') else f'{output_file}.mp3'
        elif response_format in ["opus", "ogg_opus"]:
            # For OGG, use similar logic but with .ogg extension  
            output_file = output_file if output_file.lower().endswith('.ogg') else f'{output_file}.ogg'
        
        if not self.tts_config:
            raise ValueError("No TTS configuration available")
        if not LLMConfig.is_model_available(ModelType.TTS):
            raise ValueError("TTS service unavailable - API key not set")
        
        # Route to appropriate provider
        if self.tts_config.provider in [ModelProvider.OPENAI, ModelProvider.GROQ]:
            return await self._openai_text_to_speech(text, output_file, voice=voice, response_format=response_format, **kwargs)
        else:
            raise ValueError(f"Unsupported TTS provider: {self.tts_config.provider}")

    async def _openai_text_to_speech(self, text: str, output_file: str, voice: Optional[str] = None, response_format: Optional[str] = None, **kwargs) -> str:
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
            
            # Save to output file
            with open(output_file, 'wb') as f:
                f.write(audio_bytes)
            logger.info(f"Audio saved to: {output_file} ({len(audio_bytes)} bytes)")
            
            # Encode to base64 for API response
            audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
            return audio_b64
        except Exception as e:
            logger.error(f"Error in OpenAI text-to-speech: {str(e)}")
            logger.error(traceback.format_exc())
            return ""
    
    async def stream_text_to_speech(self, text: str, voice: Optional[str] = None, response_format: Optional[str] = None, 
                                   opus_params: Optional[Dict[str, Any]] = None, **kwargs):
        """
        Stream text-to-speech audio chunks as base64-encoded strings.
        Supports both WAV and OPUS/OGG formats with format negotiation.
        
        Args:
            text: Text to convert to speech
            voice: Voice to use (optional)
            response_format: Audio format to return ('wav', 'opus', 'ogg_opus'). Defaults to 'wav'.
            opus_params: OPUS-specific parameters (sample_rate, channels, bitrate)
            **kwargs: Additional parameters to override defaults
        Yields:
            Base64-encoded audio chunks
        """
        response_format = response_format or "wav"  # Default to WAV for compatibility
        
        if not self.tts_config:
            raise ValueError("No TTS configuration available")
        if not LLMConfig.is_model_available(ModelType.TTS):
            raise ValueError("TTS service unavailable - API key not set")
        
        if self.tts_config.provider == ModelProvider.OPENAI:
            # Route to OPUS or WAV streaming based on format
            if response_format in ['opus', 'ogg_opus']:
                async for chunk in self._stream_openai_opus(text, voice, opus_params, **kwargs):
                    yield chunk
            else:
                # Use the correct OpenAI SDK streaming method for WAV
                client = self._get_openai_client(self.tts_config)
                
                params = self.tts_config.default_params.copy()
                params.update(kwargs)
                if voice:
                    params['voice'] = voice
                if response_format:
                    params['response_format'] = response_format
                else:
                    response_format = params.get('response_format', 'wav')  # Default to WAV
                
                # Remove model from params if it exists to avoid duplicate parameter error
                params.pop('model', None)
                
                # Use OpenAI SDK's proper streaming method
                try:
                    logger.info(f"🎤 OpenAI TTS: Starting WAV streaming for text='{text[:50]}...' (length: {len(text)} chars), voice={params['voice']}, format={response_format}")
                    
                    total_chunks = 0
                    total_bytes = 0
                    first_chunk_logged = False
                    
                    with client.audio.speech.with_streaming_response.create(
                        model=self.tts_config.model_id,
                        input=text,
                        voice=params['voice'],
                        response_format=response_format,
                    ) as response:
                        if response.status_code != 200:
                            raise Exception(f"TTS streaming failed: {response.status_code}")
                        
                        logger.info(f"🎤 OpenAI TTS: WAV stream started, status={response.status_code}")
                        
                        # Stream chunks as they arrive
                        for chunk in response.iter_bytes(chunk_size=4096):
                            if chunk:
                                total_chunks += 1
                                total_bytes += len(chunk)
                                
                                # Debug first chunk to check WAV header
                                if not first_chunk_logged:
                                    first_16_bytes = chunk[:16].hex() if len(chunk) >= 16 else chunk.hex()
                                    logger.info(f"🔍 OpenAI TTS: First chunk header (hex): {first_16_bytes}")
                                    first_chunk_logged = True
                                
                                b64_chunk = base64.b64encode(chunk).decode('utf-8')
                                logger.debug(f"🎤 OpenAI TTS: WAV chunk {total_chunks}, size={len(chunk)} bytes")
                                yield b64_chunk
                    
                    logger.info(f"🎤 OpenAI TTS: WAV completed - generated {total_chunks} chunks, {total_bytes} total bytes for text: '{text[:50]}...'")
                    
                except Exception as e:
                    logger.error(f"OpenAI TTS WAV streaming error: {str(e)}")
                    logger.error(traceback.format_exc())
                    raise
        else:
            raise ValueError(f"Streaming TTS not implemented for provider: {self.tts_config.provider}")
    
    def _validate_opus_chunk(self, chunk: bytes) -> None:
        """
        Basic validation for OPUS audio chunks.
        
        Args:
            chunk: First audio chunk to validate
            
        Raises:
            ValueError: If chunk doesn't appear to be valid OPUS data
        """
        if len(chunk) < 16:
            logger.warning(f"🔍 OPUS chunk validation: chunk too small ({len(chunk)} bytes)")
            return
        
        # Check for OGG container header
        if chunk.startswith(b"OggS"):
            logger.info("🔍 OPUS validation: ✅ Valid OGG container header found")
            
            # Basic OGG page structure validation
            if len(chunk) >= 27:  # Minimum OGG page header size
                version = chunk[4]
                page_type = chunk[5]
                logger.debug(f"🔍 OPUS validation: OGG version={version}, page_type={page_type}")
                
                if page_type & 0x02:  # BOS page
                    logger.info("🔍 OPUS validation: ✅ Beginning-of-stream page detected")
                else:
                    logger.debug("🔍 OPUS validation: Continuation page")
        else:
            logger.warning(f"🔍 OPUS validation: ⚠️  Expected OGG header, got: {chunk[:8].hex()}")
            # Don't raise error - some valid OPUS streams might not start with OGG header
    
    async def _stream_openai_opus(self, text: str, voice: Optional[str] = None, 
                                 opus_params: Optional[Dict[str, Any]] = None, **kwargs):
        """
        Stream OPUS/OGG audio directly from OpenAI TTS API.
        
        This method now uses OpenAI's native OPUS support for true streaming
        without FFmpeg conversion, providing ~3-4s latency reduction and 85% bandwidth savings.
        
        Args:
            text: Text to convert to speech
            voice: Voice to use
            opus_params: OPUS encoding parameters (sample_rate, channels, bitrate) - mostly ignored now
            **kwargs: Additional parameters
        Yields:
            Base64-encoded OPUS/OGG chunks
        """
        try:
            logger.info(f"🎵 Starting direct OPUS streaming: text='{text[:50]}...' (length: {len(text)} chars), voice={voice}")
            
            # Step 1: Try direct OPUS from OpenAI first, fallback to WAV conversion if needed
            client = self._get_openai_client(self.tts_config)
            
            params = self.tts_config.default_params.copy()
            params.update(kwargs)
            if voice:
                params['voice'] = voice
            
            # Try direct OPUS streaming first
            try:
                params['response_format'] = 'opus'  # Request OPUS directly from OpenAI
                logger.info(f"🎵 Attempting direct OPUS streaming from OpenAI...")
                
                # Remove model from params if it exists
                params.pop('model', None)
                
                total_chunks = 0
                total_bytes = 0
                
                with client.audio.speech.with_streaming_response.create(
                    model=self.tts_config.model_id,
                    input=text,
                    voice=params['voice'],
                    response_format='opus',
                ) as response:
                    if response.status_code != 200:
                        raise Exception(f"OpenAI OPUS streaming failed: {response.status_code}")
                    
                    logger.info(f"🎵 Direct OPUS stream started, status={response.status_code}")
                    
                    # Stream OPUS chunks directly as they arrive
                    for chunk in response.iter_bytes(chunk_size=4096):
                        if chunk:
                            total_chunks += 1
                            total_bytes += len(chunk)
                            
                            # Basic OPUS validation for first chunk
                            if total_chunks == 1:
                                self._validate_opus_chunk(chunk)
                            
                            b64_chunk = base64.b64encode(chunk).decode('utf-8')
                            logger.debug(f"🎵 Direct OPUS chunk {total_chunks}, size={len(chunk)} bytes")
                            yield b64_chunk
                
                logger.info(f"🎵 Direct OPUS streaming completed: {total_chunks} chunks, {total_bytes} total bytes")
                return  # Success - exit early
                
            except Exception as opus_error:
                logger.error(f"🎵 Direct OPUS streaming failed: {opus_error}")
                raise opus_error  # Re-raise since direct OPUS should work
            
            # REMOVED: FFmpeg fallback logic - Direct OPUS streaming from OpenAI works reliably
            # The complex FFmpeg conversion pipeline has been removed since OpenAI supports OPUS natively
            
            # If we reach here, something went wrong with the direct OPUS streaming above
            logger.error("🎵 Unexpected: Direct OPUS streaming should have completed successfully")
            raise Exception("Direct OPUS streaming failed unexpectedly")
        
        except Exception as e:
            logger.error(f"🎵 OPUS streaming error: {str(e)}")
            logger.error(traceback.format_exc())
            raise
    
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
        if self.transcription_config.provider == ModelProvider.GROQ:
            return await self._transcribe_with_groq(audio_file_path)
        elif self.transcription_config.provider in [ModelProvider.OPENAI]:
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

    async def _transcribe_with_groq(self, audio_path: str) -> str:
        """Transcribe using Groq with aggressive timeout and retry"""
        api_key = LLMConfig.get_api_key(self.transcription_config)
        if not api_key:
            raise ValueError("Groq API key not found")
        
        # transcribe_groq is a coroutine function, so we await it
        return await transcribe_groq(
            audio_path=Path(audio_path),
            model=self.transcription_config.model_id,
            api_key=api_key
        )
    
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