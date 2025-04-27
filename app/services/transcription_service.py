import logging
import os
import tempfile
import json
import requests
from fastapi import UploadFile
from pydantic import BaseModel
from typing import Optional
import traceback

from app.core.config import settings

logger = logging.getLogger(__name__)

class TranscriptionService:
    def __init__(self):
        try:
            # Use OpenAI instead of Groq
            self.api_key = settings.OPENAI_API_KEY
            self.base_url = "https://api.openai.com/v1/audio/transcriptions"
            self.model = settings.OPENAI_TRANSCRIPTION_MODEL or "whisper-1"  # Use env var or default
            self.available = bool(self.api_key)
            
            # Print configuration for debugging
            logger.info(f"TranscriptionService initialized with:")
            logger.info(f"API Base URL: {self.base_url}")
            logger.info(f"Model: {self.model}")
            logger.info(f"API Key: {'Set' if self.api_key else 'Not set'}")
            logger.info(f"Service available: {'Yes' if self.available else 'No'}")
            
            if self.api_key and self.model:
                logger.info("TranscriptionService initialized successfully")
            else:
                logger.warning("TranscriptionService initialized with missing configuration")
        except Exception as e:
            logger.error(f"Error initializing TranscriptionService: {str(e)}")
            logger.error(traceback.format_exc())
            # Set default values
            self.api_key = ""
            self.base_url = "https://api.openai.com/v1/audio/transcriptions"
            self.model = "whisper-1"
            self.available = False
            logger.warning("TranscriptionService unavailable - will return fallback responses")

    # ... rest of the file unchanged ... 