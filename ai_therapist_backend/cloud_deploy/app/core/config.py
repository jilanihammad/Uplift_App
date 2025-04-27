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
    
    # Default CORS allows all in development, restrict in production
    BACKEND_CORS_ORIGINS: List[str] = ["*"] if not env_settings.is_production else []

    # Groq API settings
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")
    GROQ_API_BASE_URL: str = os.getenv("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1")
    GROQ_LLM_MODEL_ID: str = os.getenv("GROQ_LLM_MODEL_ID", "meta-llama/llama-4-scout-17b-16e-instruct")
    GROQ_TTS_MODEL_ID: str = os.getenv("GROQ_TTS_MODEL_ID", "playai-tts")
    GROQ_TRANSCRIPTION_MODEL_ID: str = os.getenv("GROQ_TRANSCRIPTION_MODEL_ID", "whisper-large-v3-turbo")
    
    # Legacy External API settings (kept for backward compatibility)
    ENCRYPTION_KEY: str = os.getenv("ENCRYPTION_KEY", "your_encryption_key")
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

    # Database settings based on environment
    POSTGRES_SERVER: str = os.getenv("POSTGRES_SERVER", "localhost")
    POSTGRES_USER: str = os.getenv("POSTGRES_USER", "postgres")
    POSTGRES_PASSWORD: str = os.getenv("POSTGRES_PASSWORD", "7860")
    POSTGRES_DB: str = os.getenv("POSTGRES_DB", "ai_therapist")
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