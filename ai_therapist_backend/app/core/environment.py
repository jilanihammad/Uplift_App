import os
from enum import Enum
from functools import lru_cache

class Environment(str, Enum):
    LOCAL = "local"
    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"

class EnvironmentSettings:
    """
    Settings that change based on the environment (local, dev, staging, prod)
    """
    def __init__(self):
        # Determine the current environment
        self.environment = os.getenv("APP_ENV", Environment.LOCAL)
        
        # Base settings for all environments
        self.is_local = self.environment == Environment.LOCAL
        self.is_development = self.environment == Environment.DEVELOPMENT
        self.is_staging = self.environment == Environment.STAGING
        self.is_production = self.environment == Environment.PRODUCTION
        
        # API URL varies by environment
        self.api_base_url = self._get_api_base_url()
        
    def _get_api_base_url(self):
        """Get the base URL for the API based on the current environment"""
        # Check if we're running in Google Cloud
        if os.getenv("GOOGLE_CLOUD", "0") == "1":
            # When in Cloud Run, we should use port 8080
            port = os.getenv("PORT", "8080")
            return f"http://localhost:{port}"
        elif self.is_local:
            port = os.getenv("PORT", "8001")
            return f"http://localhost:{port}"
        elif self.is_development:
            return "https://api-dev-fuukqlcsha-uc.a.run.app"
        elif self.is_staging:
            return "https://api-staging-fuukqlcsha-uc.a.run.app"
        else:  # Production
            return "https://api-fuukqlcsha-uc.a.run.app"

@lru_cache()
def get_environment_settings():
    """
    Get cached environment settings
    """
    return EnvironmentSettings()

# Create a convenience instance for importing
env_settings = get_environment_settings()