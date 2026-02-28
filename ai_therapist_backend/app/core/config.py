import urllib.parse
import secrets
from typing import Any, Dict, List, Optional, Union
from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
import os
from app.core.environment import env_settings, Environment

class Settings(BaseSettings):
    PROJECT_NAME: str = "AI Therapist API"
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = os.getenv("SECRET_KEY", secrets.token_urlsafe(32))
    # 60 minutes * 24 hours * 8 days = 8 days
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 8
    
    # Server settings based on environment
    SERVER_HOST: str = env_settings.api_base_url
    
    # CORS: allow all in dev; production defaults to Capacitor/Ionic origins.
    # Override in production via BACKEND_CORS_ORIGINS env var (comma-separated or JSON array).
    BACKEND_CORS_ORIGINS: List[str] = ["*"] if not env_settings.is_production else [
        "capacitor://localhost",
        "ionic://localhost",
    ]

    # WebSocket Security Configuration
    WEBSOCKET_ALLOWED_ORIGINS: List[str] = [
        "https://localhost:*",  # Local development
        "https://127.0.0.1:*",  # Local development
        "https://*.vercel.app",  # Vercel deployments
        "https://*.netlify.app",  # Netlify deployments
        "capacitor://localhost",  # Capacitor/Ionic apps
        "ionic://localhost",  # Ionic apps
        "http://localhost:*"  # Development only - remove in production
    ] if not env_settings.is_production else [
        "capacitor://localhost",  # Production Capacitor apps
        "ionic://localhost"  # Production Ionic apps
    ]
    
    WEBSOCKET_ALLOWED_SUBPROTOCOLS: List[str] = [
        "ai-therapist-v1",  # Primary protocol for the app
        "streaming-tts",    # TTS streaming protocol
        "therapist-chat"    # Chat protocol
    ]
    
    # WebSocket rate limiting (requests per minute per user)
    WEBSOCKET_RATE_LIMIT_PER_MINUTE: int = 30
    WEBSOCKET_RATE_LIMIT_WINDOW_SECONDS: int = 60
    
    # Audio processing debug settings
    VERBOSE_AUDIO_CHUNKS: bool = os.getenv("VERBOSE_AUDIO_CHUNKS", "false").lower() == "true"
    
    # OpenAI TTS streaming settings (defaults to True for testing)  
    OPENAI_TTS_STREAM: bool = os.getenv("OPENAI_TTS_STREAM", "true").lower() == "true"
    
    # TTS streaming feature flag for safe rollback
    TTS_STREAMING_ENABLED: bool = os.getenv("TTS_STREAMING_ENABLED", "true").lower() == "true"

    # Groq API settings
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")
    GROQ_API_BASE_URL: str = os.getenv("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1")
    GROQ_LLM_MODEL_ID: str = os.getenv("GROQ_LLM_MODEL_ID", "meta-llama/llama-4-scout-17b-16e-instruct")
    GROQ_TTS_MODEL_ID: str = os.getenv("GROQ_TTS_MODEL_ID", "playai-tts")
    GROQ_TRANSCRIPTION_MODEL_ID: str = os.getenv("GROQ_TRANSCRIPTION_MODEL_ID", "whisper-large-v3-turbo")
    
    # Legacy External API settings (kept for backward compatibility)
    ENCRYPTION_KEY: str = os.environ["ENCRYPTION_KEY"] if env_settings.is_production else os.getenv("ENCRYPTION_KEY", "dev-only-encryption-key")
    DEEPSEEK_API_KEY: str = os.getenv("DEEPSEEK_API_KEY", "dummy_key")
    DEEPSEEK_API_URL: str = os.getenv("DEEPSEEK_API_URL", "https://api.deepseek.com/v1")
    SESAME_API_KEY: str = os.getenv("SESAME_API_KEY", "dummy_key")
    SESAME_API_URL: str = os.getenv("SESAME_API_URL", "https://api.sesame.ai/v1/speech")
    
    # Stripe settings
    STRIPE_SECRET_KEY: str = os.getenv("STRIPE_SECRET_KEY", "dummy_key")
    STRIPE_WEBHOOK_SECRET: str = os.getenv("STRIPE_WEBHOOK_SECRET", "dummy_key")
    BASIC_MONTHLY_PRICE_ID: str = os.getenv("BASIC_MONTHLY_PRICE_ID", "price_basic_monthly")
    BASIC_YEARLY_PRICE_ID: str = os.getenv("BASIC_YEARLY_PRICE_ID", "price_basic_yearly")
    PREMIUM_MONTHLY_PRICE_ID: str = os.getenv("PREMIUM_MONTHLY_PRICE_ID", "price_premium_monthly")
    PREMIUM_YEARLY_PRICE_ID: str = os.getenv("PREMIUM_YEARLY_PRICE_ID", "price_premium_yearly")

    # OpenAI compatibility
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_LLM_MODEL: str = os.getenv("OPENAI_LLM_MODEL", "gpt-3.5-turbo")
    OPENAI_TTS_MODEL: str = os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts")
    OPENAI_TTS_VOICE: str = os.getenv("OPENAI_TTS_VOICE", "sage")
    OPENAI_TRANSCRIPTION_MODEL: str = os.getenv("OPENAI_TRANSCRIPTION_MODEL", "whisper-1")
    
    # Legacy Groq names mapped to new ones for backward compatibility
    GROQ_LLM_MODEL: str = os.getenv("GROQ_LLM_MODEL", "llama3-70b-8192")  # Alias for GROQ_LLM_MODEL_ID

    # Firebase authentication settings
    FIREBASE_PROJECT_ID: str = os.getenv("FIREBASE_PROJECT_ID", "")
    FIREBASE_AUTH_AUDIENCE: Optional[str] = os.getenv("FIREBASE_AUTH_AUDIENCE")

    @field_validator("BACKEND_CORS_ORIGINS", mode="before")
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> Union[List[str], str]:
        if not v:  # Handle empty string case
            return ["*"]
        if isinstance(v, str):
            if v == "*":  # Special case for allow all
                return ["*"]
            try:
                if v.startswith("["):
                    import json
                    return json.loads(v)
                else:
                    return [i.strip() for i in v.split(",")]
            except Exception as e:
                print(f"Error parsing CORS origins: {e}, defaulting to allow all")
                return ["*"]
        elif isinstance(v, list):
            return v
        return ["*"]  # Default to allow all in case of any errors

    @field_validator("WEBSOCKET_ALLOWED_ORIGINS", mode="before")
    def assemble_websocket_origins(cls, v: Union[str, List[str]]) -> List[str]:
        """Parse and validate WebSocket allowed origins"""
        if not v:
            return ["*"] if not env_settings.is_production else []
        if isinstance(v, str):
            if v == "*":
                return ["*"]
            try:
                if v.startswith("["):
                    import json
                    return json.loads(v)
                else:
                    return [i.strip() for i in v.split(",")]
            except Exception as e:
                print(f"Error parsing WebSocket origins: {e}, using defaults")
                return ["*"] if not env_settings.is_production else []
        elif isinstance(v, list):
            return v
        return ["*"] if not env_settings.is_production else []

    # Database settings based on environment
    POSTGRES_SERVER: str = os.getenv("POSTGRES_SERVER", "localhost")
    POSTGRES_USER: str = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD: str = os.environ["POSTGRES_PASSWORD"] if env_settings.is_production else os.getenv("POSTGRES_PASSWORD", "7860")
    POSTGRES_DB: str = os.getenv("POSTGRES_DB", "ai_therapist_new")
    SQLALCHEMY_DATABASE_URI: Optional[str] = None

    @field_validator("SQLALCHEMY_DATABASE_URI", mode="before")
    def assemble_db_connection(cls, v: Optional[str], info) -> Any:
        if isinstance(v, str):
            return v
            
        # Check for direct database URL from environment (for Firebase/GCP)
        db_url = os.getenv("DATABASE_URL")
        if db_url:
            return db_url
            
        values = info.data
        
        # Use values from environment variables or defaults
        username = values.get("POSTGRES_USER")
        password = values.get("POSTGRES_PASSWORD")
        server = values.get("POSTGRES_SERVER")
        db = values.get("POSTGRES_DB")
        
        # URL encode the password to handle special characters
        encoded_password = urllib.parse.quote(password)
        
        uri = f"postgresql://{username}:{encoded_password}@{server}/{db}"
        
        print(f"Generated Database URI for environment {env_settings.environment}: {uri}")
        return uri

    # Config settings with appropriate env file based on environment
    model_config = SettingsConfigDict(
        env_file=f".env.{env_settings.environment}" if os.path.exists(f".env.{env_settings.environment}") else ".env",
        case_sensitive=True,
        extra="ignore"
    )

settings = Settings()
