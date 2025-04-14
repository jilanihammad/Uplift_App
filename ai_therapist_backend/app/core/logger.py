import logging
import os
import sys
import google.cloud.logging
from app.core.environment import env_settings, Environment

def setup_logging():
    """
    Configure logging based on the environment
    - Local/Development: Console logging with colored output
    - Production/Staging: Cloud Logging for GCP integration
    """
    # Clear existing handlers
    root_logger = logging.getLogger()
    for handler in root_logger.handlers:
        root_logger.removeHandler(handler)
    
    # Set log level (more verbose in development)
    log_level = logging.DEBUG if env_settings.is_local or env_settings.is_development else logging.INFO
    root_logger.setLevel(log_level)
    
    # For GCP environments, use Cloud Logging
    if env_settings.is_production or env_settings.is_staging:
        try:
            # Setup Google Cloud Logging
            client = google.cloud.logging.Client()
            client.setup_logging()
            
            logger = logging.getLogger(__name__)
            logger.info(f"Google Cloud Logging initialized in {env_settings.environment} environment")
        except Exception as e:
            # Fall back to standard logging if Cloud Logging setup fails
            handler = logging.StreamHandler(sys.stdout)
            formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
            handler.setFormatter(formatter)
            root_logger.addHandler(handler)
            
            logger = logging.getLogger(__name__)
            logger.error(f"Failed to initialize Google Cloud Logging: {str(e)}")
            logger.info(f"Falling back to standard logging")
    else:
        # For local/development environments, use console logging
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        root_logger.addHandler(handler)
        
        logger = logging.getLogger(__name__)
        logger.info(f"Console logging initialized in {env_settings.environment} environment") 