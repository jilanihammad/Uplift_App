import secrets
from typing import Any, Dict, List, Optional, Union
from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "AI Therapist API"
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = secrets.token_urlsafe(32)
    # 60 minutes * 24 hours * 8 days = 8 days
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 8
    SERVER_HOST: AnyHttpUrl = "http://localhost:8000"
    BACKEND_CORS_ORIGINS: List[AnyHttpUrl] = []

    @field_validator("BACKEND_CORS_ORIGINS", mode="before")
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> Union[List[str], str]:
        if isinstance(v, str) and not v.startswith("["):
            return [i.strip() for i in v.split(",")]
        elif isinstance(v, (list, str)):
            return v
        raise ValueError(v)

    # These values will be overridden by .env file
    POSTGRES_SERVER: str = "localhost"  # Use string for default values
    POSTGRES_USER: str = "postgres"
    POSTGRES_PASSWORD: str = "7860"
    POSTGRES_DB: str = "ai_therapist"
    SQLALCHEMY_DATABASE_URI: Optional[str] = None

    @field_validator("SQLALCHEMY_DATABASE_URI", mode="before")
    def assemble_db_connection(cls, v: Optional[str], info) -> Any:
        if isinstance(v, str):
            return v
        values = info.data
        return f"postgresql://{values.get('POSTGRES_USER')}:{values.get('POSTGRES_PASSWORD')}@{values.get('POSTGRES_SERVER')}/{values.get('POSTGRES_DB') or ''}"

    # Default dummy values that will be overridden by .env
    DEEPSEEK_API_KEY: str = "dummy_key"
    DEEPSEEK_API_URL: str = "https://api.deepseek.com/v1"
    
    SESAME_API_KEY: str = "dummy_key"
    SESAME_API_URL: str = "https://api.sesame.ai/v1/speech"
    
    STRIPE_SECRET_KEY: str = "dummy_key"
    STRIPE_WEBHOOK_SECRET: str = "dummy_key"
    
    BASIC_MONTHLY_PRICE_ID: str = "price_basic_monthly"
    BASIC_YEARLY_PRICE_ID: str = "price_basic_yearly"
    PREMIUM_MONTHLY_PRICE_ID: str = "price_premium_monthly"
    PREMIUM_YEARLY_PRICE_ID: str = "price_premium_yearly"
    
    DATA_RETENTION_DAYS: int = 365  # 1 year by default
    
    ENCRYPTION_KEY: str = "dummy_encryption_key"

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)


settings = Settings()