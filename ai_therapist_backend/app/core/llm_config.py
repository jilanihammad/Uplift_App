import os
from typing import Dict, Any, Optional
from enum import Enum
from dataclasses import dataclass

class ModelProvider(str, Enum):
    OPENAI = "openai"
    GROQ = "groq"
    GROK = "grok"
    ANTHROPIC = "anthropic"
    AZURE_OPENAI = "azure_openai"
    DEEPSEEK = "deepseek"
    GOOGLE = "google"
    
class ModelType(str, Enum):
    LLM = "llm"
    TTS = "tts"
    TRANSCRIPTION = "transcription"

@dataclass
class ModelConfig:
    """Configuration for a specific model"""
    provider: ModelProvider
    model_id: str
    base_url: str
    api_key_env: str
    default_params: Dict[str, Any]
    supports_streaming: bool = False
    max_tokens_limit: int = 4096

class LLMConfig:
    """
    Centralized configuration for all LLM models and providers.
    Change the ACTIVE_* settings to switch between models easily.
    """
    
    # =============================================================================
    # ACTIVE MODEL SELECTION - CHANGE THESE TO SWITCH MODELS EASILY
    # =============================================================================
    ACTIVE_LLM_PROVIDER = ModelProvider.GROK        # Change this to switch LLM provider
    ACTIVE_TTS_PROVIDER = ModelProvider.OPENAI        # Default TTS provider is OpenAI
    ACTIVE_TRANSCRIPTION_PROVIDER = ModelProvider.GROQ  # Change this to switch transcription provider
    
    # Model overrides (optional - leave None to use provider defaults)
    ACTIVE_LLM_MODEL = None  # e.g., "gpt-4" to override default
    ACTIVE_TTS_MODEL = None  # e.g., "tts-1-hd" to override default
    ACTIVE_TRANSCRIPTION_MODEL = None  # e.g., "whisper-1" to override default

    # Default TTS voice (change here to update default voice)
    DEFAULT_TTS_VOICE = os.getenv("DEFAULT_TTS_VOICE", "coral")  # Default Gemini voice; overridden per-provider as needed
    GOOGLE_TTS_MODE = os.getenv("GOOGLE_TTS_MODE", "tts_only").lower()
    GOOGLE_TTS_NATIVE_MIME = os.getenv(
        "GOOGLE_TTS_NATIVE_MIME",
        "audio/ogg; codecs=opus",
    )
    GOOGLE_LIVE_MODE = os.getenv("GOOGLE_LIVE_MODE", "duplex").lower() # tts_only or duplex
    GEMINI_LIVE_INCREMENTAL_TRANSCRIPTS = (
        os.getenv("GEMINI_LIVE_INCREMENTAL_TRANSCRIPTS", "false").lower() == "true"
    )
    
    # Centralized TTS arguments to prevent parameter mismatches
    DEFAULT_TTS_ARGS = {
        "model": os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts"),
        "voice": DEFAULT_TTS_VOICE,
        "response_format": "wav"  # Default format for better TTFB performance
    }
    # =============================================================================
    # MODEL CONFIGURATIONS - Add new models/providers here
    # =============================================================================
    
    MODELS = {
        # OpenAI Models
        (ModelProvider.OPENAI, ModelType.LLM): ModelConfig(
            provider=ModelProvider.OPENAI,
            model_id=os.getenv("OPENAI_LLM_MODEL", "gpt-4o-mini"),
            base_url="https://api.openai.com/v1",
            api_key_env="OPENAI_API_KEY",
            default_params={
                "temperature": 0.7,
                "max_tokens": 1000,
                "top_p": 1.0,
                "frequency_penalty": 0.0,
                "presence_penalty": 0.0
            },
            supports_streaming=True,
            max_tokens_limit=128000
        ),
        
        (ModelProvider.OPENAI, ModelType.TTS): ModelConfig(
            provider=ModelProvider.OPENAI,
            model_id=os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts"),
            base_url="https://api.openai.com/v1",
            api_key_env="OPENAI_API_KEY",
            default_params={
                "voice": os.getenv("OPENAI_TTS_VOICE", "coral"),
                "response_format": "wav",
                "speed": 1.0
            },
            supports_streaming=True
        ),
        
        (ModelProvider.OPENAI, ModelType.TRANSCRIPTION): ModelConfig(
            provider=ModelProvider.OPENAI,
            model_id=os.getenv("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-mini-transcribe"),
            base_url="https://api.openai.com/v1",
            api_key_env="OPENAI_API_KEY",
            default_params={
                "format": "json",
                "temperature": 0.0
            },
            supports_streaming=False
        ),
        
        # Groq Models
        (ModelProvider.GROQ, ModelType.LLM): ModelConfig(
            provider=ModelProvider.GROQ,
            model_id=os.getenv("GROQ_LLM_MODEL_ID", "llama-3.3-70b-versatile"),
            base_url=os.getenv("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1"),
            api_key_env="GROQ_API_KEY",
            default_params={
                "temperature": 0.7,
                "max_tokens": 1000,
                "top_p": 1.0,
                "stream": False
            },
            supports_streaming=True,
            max_tokens_limit=32768
        ),
        
        (ModelProvider.GROQ, ModelType.TTS): ModelConfig(
            provider=ModelProvider.GROQ,
            model_id=os.getenv("GROQ_TTS_MODEL_ID", "tts-1"),
            base_url=os.getenv("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1"),
            api_key_env="GROQ_API_KEY",
            default_params={
                "voice": "nova",
                "format": "wav"
            },
            supports_streaming=False
        ),
        
        (ModelProvider.GROQ, ModelType.TRANSCRIPTION): ModelConfig(
            provider=ModelProvider.GROQ,
            model_id=os.getenv("GROQ_TRANSCRIPTION_MODEL_ID", "whisper-large-v3-turbo"),
            base_url=os.getenv("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1"),
            api_key_env="GROQ_API_KEY",
            default_params={
                "format": "verbose_json",
                "temperature": 0.0
            },
            supports_streaming=False
        ),
        
        # Anthropic Models
        (ModelProvider.ANTHROPIC, ModelType.LLM): ModelConfig(
            provider=ModelProvider.ANTHROPIC,
            model_id=os.getenv("ANTHROPIC_MODEL", "claude-3-5-sonnet-20241022"),
            base_url="https://api.anthropic.com",
            api_key_env="ANTHROPIC_API_KEY",
            default_params={
                "temperature": 0.7,
                "max_tokens": 1000,
                "top_p": 1.0
            },
            supports_streaming=True,
            max_tokens_limit=200000
        ),
        
        # Azure OpenAI Models
        (ModelProvider.AZURE_OPENAI, ModelType.LLM): ModelConfig(
            provider=ModelProvider.AZURE_OPENAI,
            model_id=os.getenv("AZURE_OPENAI_LLM_MODEL", "gpt-4"),
            base_url=os.getenv("AZURE_OPENAI_ENDPOINT", ""),
            api_key_env="AZURE_OPENAI_API_KEY",
            default_params={
                "temperature": 0.7,
                "max_tokens": 1000,
                "api_version": "2024-02-15-preview"
            },
            supports_streaming=True,
            max_tokens_limit=128000
        ),
        
        # DeepSeek Models (Legacy support)
        (ModelProvider.DEEPSEEK, ModelType.LLM): ModelConfig(
            provider=ModelProvider.DEEPSEEK,
            model_id=os.getenv("DEEPSEEK_MODEL", "deepseek-chat"),
            base_url=os.getenv("DEEPSEEK_API_URL", "https://api.deepseek.com/v1"),
            api_key_env="DEEPSEEK_API_KEY",
            default_params={
                "temperature": 0.7,
                "max_tokens": 1000,
                "top_p": 1.0
            },
            supports_streaming=True,
            max_tokens_limit=32768
        ),
        
        # Google (Gemini) Models
        (ModelProvider.GOOGLE, ModelType.LLM): ModelConfig(
            provider=ModelProvider.GOOGLE,
            model_id=os.getenv("GOOGLE_MODEL", "gemini-2.5-flash-lite"),
            base_url="https://generativelanguage.googleapis.com/v1beta",
            api_key_env="GOOGLE_API_KEY",
            default_params={
                "temperature": 0.7,
                "max_tokens": 1000,
                "top_p": 1.0
            },
            supports_streaming=True,
            max_tokens_limit=128000
        ),

        (ModelProvider.GOOGLE, ModelType.TTS): ModelConfig(
            provider=ModelProvider.GOOGLE,
            model_id=os.getenv("GOOGLE_TTS_MODEL", "gemini-2.5-flash-native-audio-preview-09-2025"),
            base_url="https://generativelanguage.googleapis.com/v1beta",
            api_key_env="GOOGLE_API_KEY",
            default_params={
                "voice": os.getenv("GOOGLE_TTS_VOICE", "kore"),
                "audio_encoding": os.getenv("GOOGLE_TTS_AUDIO_ENCODING", "LINEAR16"),
                "sample_rate_hz": int(os.getenv("GOOGLE_TTS_SAMPLE_RATE", "24000")),
                "response_format": (
                    os.getenv("GOOGLE_TTS_RESPONSE_FORMAT", "wav")
                    if GOOGLE_TTS_MODE != "live"
                    else "native"
                ),
                "mode": GOOGLE_TTS_MODE,
                "native_mime_type": GOOGLE_TTS_NATIVE_MIME,
                "live_mode": GOOGLE_LIVE_MODE,
            },
            supports_streaming=True
        ),

        # Grok Models (x.ai)
        (ModelProvider.GROK, ModelType.LLM): ModelConfig(
            provider=ModelProvider.GROK,
            model_id=os.getenv("GROK_LLM_MODEL", "grok-4-fast-non-reasoning"),
            base_url=os.getenv("GROK_API_BASE_URL", "https://api.x.ai/v1"),
            api_key_env="XAI_API_KEY",
            default_params={
                "temperature": 0.7,
                "max_tokens": 1000,
                "top_p": 1.0,
                "stream": False
            },
            supports_streaming=True,
            max_tokens_limit=131072  # Grok supports 131K context window
        )
    }
    
    @classmethod
    def get_active_model_config(cls, model_type: ModelType) -> Optional[ModelConfig]:
        """Get the configuration for the currently active model of the specified type."""
        provider_map = {
            ModelType.LLM: cls.ACTIVE_LLM_PROVIDER,
            ModelType.TTS: cls.ACTIVE_TTS_PROVIDER,
            ModelType.TRANSCRIPTION: cls.ACTIVE_TRANSCRIPTION_PROVIDER
        }
        
        provider = provider_map.get(model_type)
        if not provider:
            return None
            
        config = cls.MODELS.get((provider, model_type))
        if not config:
            return None
            
        # Override model_id if specified
        if model_type == ModelType.LLM and cls.ACTIVE_LLM_MODEL:
            config.model_id = cls.ACTIVE_LLM_MODEL
        elif model_type == ModelType.TTS and cls.ACTIVE_TTS_MODEL:
            config.model_id = cls.ACTIVE_TTS_MODEL
        elif model_type == ModelType.TRANSCRIPTION and cls.ACTIVE_TRANSCRIPTION_MODEL:
            config.model_id = cls.ACTIVE_TRANSCRIPTION_MODEL
            
        return config
    
    @classmethod
    def get_api_key(cls, config: ModelConfig) -> Optional[str]:
        """Get the API key for a model configuration."""
        return os.getenv(config.api_key_env)

    @classmethod
    def get_tts_mode(cls) -> str:
        config = cls.get_active_model_config(ModelType.TTS)
        if not config:
            return "rest"
        return (config.default_params or {}).get("mode", "rest")

    @classmethod
    def get_tts_config(cls) -> Dict[str, Any]:
        """Return the active TTS configuration in a JSON-serializable format."""
        config = cls.get_active_model_config(ModelType.TTS)

        if not config:
            return {
                "provider": cls.ACTIVE_TTS_PROVIDER.value,
                "model": cls.ACTIVE_TTS_MODEL,
                "voice": cls.DEFAULT_TTS_VOICE,
                "sample_rate_hz": 24000,
                "audio_encoding": "LINEAR16",
                "response_format": "wav",
                "supports_streaming": False,
            }

        params = dict(config.default_params or {})

        model_id = cls.ACTIVE_TTS_MODEL or config.model_id
        voice = params.get("voice") or cls.DEFAULT_TTS_VOICE
        sample_rate = params.get("sample_rate_hz", 24000)
        audio_encoding = params.get("audio_encoding", "LINEAR16")
        response_format = params.get("response_format", "wav")

        mode = params.get("mode", "rest")
        native_mime = params.get("native_mime_type")

        mime_type = params.get("mime_type")
        if not mime_type:
            if mode == "live" and native_mime:
                mime_type = native_mime
            else:
                mime_type = "audio/wav"

        return {
            "provider": config.provider.value,
            "model": model_id,
            "voice": voice,
            "mode": mode,
            "sample_rate_hz": sample_rate,
            "audio_encoding": audio_encoding,
            "response_format": response_format,
            "mime_type": mime_type,
            "supports_streaming": bool(config.supports_streaming),
        }

    @classmethod
    def is_gemini_live_duplex_enabled(cls) -> bool:
        return cls.GOOGLE_LIVE_MODE == "duplex"

    @classmethod
    def use_gemini_live_incremental_transcripts(cls) -> bool:
        return cls.GEMINI_LIVE_INCREMENTAL_TRANSCRIPTS

    @classmethod
    def is_model_available(cls, model_type: ModelType) -> bool:
        """Check if the active model for the specified type is available."""
        config = cls.get_active_model_config(model_type)
        if not config:
            return False
        return bool(cls.get_api_key(config))
    
    @classmethod
    def list_available_providers(cls, model_type: ModelType) -> list[ModelProvider]:
        """List all providers that have configurations for the specified model type."""
        providers = []
        for (provider, mtype) in cls.MODELS.keys():
            if mtype == model_type and cls.get_api_key(cls.MODELS[(provider, mtype)]):
                providers.append(provider)
        return providers
    
    @classmethod
    def get_model_info(cls) -> Dict[str, Any]:
        """Get information about all currently active models."""
        llm_config = cls.get_active_model_config(ModelType.LLM)
        tts_config = cls.get_active_model_config(ModelType.TTS)
        transcription_config = cls.get_active_model_config(ModelType.TRANSCRIPTION)
        
        return {
            "llm": {
                "provider": cls.ACTIVE_LLM_PROVIDER,
                "model": llm_config.model_id if llm_config else None,
                "available": cls.is_model_available(ModelType.LLM)
            },
            "tts": {
                "provider": cls.ACTIVE_TTS_PROVIDER,
                "model": tts_config.model_id if tts_config else None,
                "available": cls.is_model_available(ModelType.TTS)
            },
            "transcription": {
                "provider": cls.ACTIVE_TRANSCRIPTION_PROVIDER,
                "model": transcription_config.model_id if transcription_config else None,
                "available": cls.is_model_available(ModelType.TRANSCRIPTION)
            }
        }
    
    @classmethod
    def validate_configuration(cls) -> Dict[str, Any]:
        """Validate the current configuration and return detailed status."""
        validation_result = {
            "valid": True,
            "errors": [],
            "warnings": [],
            "configurations": {}
        }
        
        for model_type in [ModelType.LLM, ModelType.TTS, ModelType.TRANSCRIPTION]:
            config = cls.get_active_model_config(model_type)
            type_name = model_type.value
            
            if not config:
                validation_result["valid"] = False
                validation_result["errors"].append(f"No configuration found for {type_name}")
                continue
            
            # Check if API key is available
            api_key = cls.get_api_key(config)
            if not api_key:
                validation_result["warnings"].append(f"API key not set for {type_name} provider: {config.provider}")
            
            # Store configuration details
            validation_result["configurations"][type_name] = {
                "provider": config.provider,
                "model_id": config.model_id,
                "base_url": config.base_url,
                "api_key_env": config.api_key_env,
                "api_key_available": bool(api_key),
                "supports_streaming": getattr(config, 'supports_streaming', False),
                "max_tokens_limit": getattr(config, 'max_tokens_limit', 'unknown')
            }
        
        return validation_result 
