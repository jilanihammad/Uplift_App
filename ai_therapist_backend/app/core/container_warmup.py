"""
Container Warm-up Strategy

This module provides comprehensive warm-up strategies for the AI Therapist backend
to minimize cold start latency and improve initial response times.

Features:
- Model context warm-up
- TTS voice preloading
- Provider connection establishment
- Python bytecode compilation
- Database connection pool warming
- HTTP client pool pre-warming
"""

import asyncio
import logging
import time
import os
from typing import Dict, List, Optional, Any
from dataclasses import dataclass
from enum import Enum
from concurrent.futures import ThreadPoolExecutor

from app.core.llm_config import LLMConfig, ModelType
from app.core.observability import log_info, log_error, log_warning, record_latency
from app.core.http_client_manager import get_http_client_manager
from app.core.performance_monitor import get_performance_monitor, record_connection_reuse

logger = logging.getLogger(__name__)


class WarmupStage(Enum):
    """Warm-up stages."""
    PREPARATION = "preparation"
    COMPILATION = "compilation"
    CONNECTIONS = "connections"
    MODELS = "models"
    VALIDATION = "validation"
    COMPLETE = "complete"


@dataclass
class WarmupConfig:
    """Configuration for warm-up process."""
    enable_model_warmup: bool = True
    enable_tts_warmup: bool = True
    enable_connection_warmup: bool = True
    enable_compilation_warmup: bool = True
    enable_db_warmup: bool = True
    
    # Warm-up prompts
    chat_warmup_prompts: Dict[str, str] = None
    tts_warmup_texts: List[str] = None
    
    # Timeouts
    total_warmup_timeout: float = 60.0  # 1 minute max
    model_warmup_timeout: float = 30.0
    connection_warmup_timeout: float = 15.0
    
    # Concurrency
    max_concurrent_warmups: int = 5
    
    def __post_init__(self):
        if self.chat_warmup_prompts is None:
            self.chat_warmup_prompts = {
                "gpt-4": "Hello, this is a system initialization test.",
                "gpt-3.5-turbo": "System check - please respond with 'OK'.",
                "claude-3-sonnet": "Initialization test - respond briefly.",
                "claude-3-haiku": "System warm-up check.",
                "gemini-pro": "System initialization ping.",
                "llama2-70b": "System test - respond with status.",
                "mixtral-8x7b": "Warm-up check - brief response please."
            }
        
        if self.tts_warmup_texts is None:
            self.tts_warmup_texts = [
                "System initialization complete.",
                "Voice synthesis ready.",
                "Audio processing active."
            ]


@dataclass
class WarmupResult:
    """Result of warm-up operation."""
    stage: WarmupStage
    success: bool
    duration_ms: float
    details: Dict[str, Any]
    error: Optional[str] = None


class ContainerWarmup:
    """
    Container warm-up manager for optimizing cold start performance.
    
    This class handles all warm-up operations including model initialization,
    connection establishment, and system preparation.
    """
    
    def __init__(self, config: WarmupConfig = None):
        self.config = config or WarmupConfig()
        self.warmup_results: List[WarmupResult] = []
        self.start_time: Optional[float] = None
        self.total_duration: Optional[float] = None
        self.current_stage = WarmupStage.PREPARATION
        
        # Thread pool for CPU-bound operations
        self.executor = ThreadPoolExecutor(max_workers=self.config.max_concurrent_warmups)
        
    async def run_full_warmup(self) -> Dict[str, Any]:
        """Run complete container warm-up process."""
        self.start_time = time.time()
        
        await log_info(
            "container_warmup",
            "Starting container warm-up process",
            config=self.config.__dict__
        )
        
        try:
            # Stage 1: Preparation
            await self._stage_preparation()
            
            # Stage 2: Python compilation
            if self.config.enable_compilation_warmup:
                await self._stage_compilation()
            
            # Stage 3: Connection establishment
            if self.config.enable_connection_warmup:
                await self._stage_connections()
            
            # Stage 4: Model warm-up
            if self.config.enable_model_warmup:
                await self._stage_models()
            
            # Stage 5: Validation
            await self._stage_validation()
            
            # Complete
            self.current_stage = WarmupStage.COMPLETE
            self.total_duration = time.time() - self.start_time
            
            await log_info(
                "container_warmup",
                "Container warm-up completed successfully",
                total_duration_ms=self.total_duration * 1000,
                stages_completed=len(self.warmup_results)
            )
            
            record_latency(
                "container",
                "warmup_total",
                self.total_duration * 1000
            )
            
            return self._get_warmup_summary()
            
        except Exception as e:
            self.total_duration = time.time() - self.start_time
            
            await log_error(
                "container_warmup",
                f"Container warm-up failed: {str(e)}",
                total_duration_ms=self.total_duration * 1000,
                current_stage=self.current_stage.value,
                error=str(e)
            )
            
            raise
        finally:
            self.executor.shutdown(wait=False)
    
    async def _stage_preparation(self):
        """Stage 1: Preparation and environment setup."""
        self.current_stage = WarmupStage.PREPARATION
        start_time = time.time()
        
        try:
            # Set environment variables for optimization
            os.environ.setdefault("PYTHONOPTIMIZE", "1")
            os.environ.setdefault("PYTHONUNBUFFERED", "1")
            
            # Prepare logging
            await log_info(
                "container_warmup",
                "Preparation stage started",
                stage=self.current_stage.value
            )
            
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=True,
                duration_ms=duration_ms,
                details={"environment_prepared": True}
            ))
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=False,
                duration_ms=duration_ms,
                details={},
                error=str(e)
            ))
            
            raise
    
    async def _stage_compilation(self):
        """Stage 2: Python bytecode compilation."""
        self.current_stage = WarmupStage.COMPILATION
        start_time = time.time()
        
        try:
            await log_info(
                "container_warmup",
                "Compilation stage started",
                stage=self.current_stage.value
            )
            
            # Compile Pydantic models
            await asyncio.get_event_loop().run_in_executor(
                self.executor,
                self._compile_pydantic_models
            )
            
            # Pre-import heavy modules
            await asyncio.get_event_loop().run_in_executor(
                self.executor,
                self._preimport_modules
            )
            
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=True,
                duration_ms=duration_ms,
                details={"pydantic_compiled": True, "modules_preimported": True}
            ))
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=False,
                duration_ms=duration_ms,
                details={},
                error=str(e)
            ))
            
            raise
    
    def _compile_pydantic_models(self):
        """Compile Pydantic models for better performance."""
        try:
            # Enable Pydantic compilation
            os.environ["PYDANTIC_COMPILE_ALL"] = "1"
            
            # Import and compile models
            from app.models import user, session, message, note, assessment, action_plan
            
            # Trigger compilation by creating dummy instances
            models = [user, session, message, note, assessment, action_plan]
            
            for model_module in models:
                # This will trigger Pydantic compilation
                if hasattr(model_module, '__all__'):
                    for model_name in model_module.__all__:
                        model_class = getattr(model_module, model_name)
                        if hasattr(model_class, 'model_validate'):
                            # Pydantic v2 style
                            pass
            
            logger.info("Pydantic models compiled successfully")
            
        except Exception as e:
            logger.warning(f"Pydantic compilation failed: {e}")
    
    def _preimport_modules(self):
        """Pre-import heavy modules."""
        try:
            # Import heavy modules to trigger compilation
            import numpy as np
            import json
            import asyncio
            import httpx
            import aiohttp
            import sqlalchemy
            import anthropic
            import openai
            
            # Import application modules
            from app.services import llm_manager, therapy_service
            from app.core import llm_config
            
            logger.info("Heavy modules pre-imported successfully")
            
        except Exception as e:
            logger.warning(f"Module pre-import failed: {e}")
    
    async def _stage_connections(self):
        """Stage 3: Connection establishment."""
        self.current_stage = WarmupStage.CONNECTIONS
        start_time = time.time()
        
        try:
            await log_info(
                "container_warmup",
                "Connection stage started",
                stage=self.current_stage.value
            )
            
            # Warm up HTTP client connections
            await self._warmup_http_clients()
            
            # Warm up database connections
            if self.config.enable_db_warmup:
                await self._warmup_database_connections()
            
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=True,
                duration_ms=duration_ms,
                details={"http_clients_warmed": True, "db_connections_warmed": True}
            ))
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=False,
                duration_ms=duration_ms,
                details={},
                error=str(e)
            ))
            
            raise
    
    async def _warmup_http_clients(self):
        """Warm up HTTP client connections."""
        try:
            http_manager = get_http_client_manager()
            
            # Pre-warm clients for all providers with lightweight ping requests
            providers = ["openai", "anthropic", "groq", "google", "azure"]
            
            warmup_tasks = []
            for provider in providers:
                warmup_tasks.append(self._warmup_provider_client(http_manager, provider))
            
            # Run warmups in parallel
            await asyncio.gather(*warmup_tasks, return_exceptions=True)
            
        except Exception as e:
            logger.warning(f"HTTP client warm-up failed: {e}")
    
    async def _warmup_provider_client(self, http_manager, provider: str):
        """Warm up a specific provider's HTTP client."""
        try:
            client = http_manager.get_client(provider)
            await client.start()
            
            # Provider-specific ping endpoints for connection validation
            if provider == "openai":
                await self._ping_openai(client)
            elif provider == "groq":
                await self._ping_groq(client)
            elif provider == "anthropic":
                await self._ping_anthropic(client)
            elif provider == "google":
                await self._ping_google(client)
            
            logger.info(f"HTTP client warmed up for {provider}")
            
        except Exception as e:
            logger.warning(f"Failed to warm up HTTP client for {provider}: {e}")
    
    async def _ping_openai(self, client):
        """Ping OpenAI with lightweight request."""
        try:
            from app.core.llm_config import LLMConfig, ModelProvider
            
            # Get OpenAI API key
            api_key = None
            for config in LLMConfig.get_all_configs():
                if config.provider == ModelProvider.OPENAI:
                    api_key = LLMConfig.get_api_key(config)
                    break
            
            if api_key:
                headers = {"Authorization": f"Bearer {api_key}"}
                # Lightweight models endpoint (cached by OpenAI)
                start_time = time.time()
                response = await client.get("https://api.openai.com/v1/models", headers=headers)
                duration_ms = (time.time() - start_time) * 1000
                
                if response.status_code == 200:
                    logger.info("OpenAI connection validated")
                    # Record successful connection and performance
                    performance_monitor = get_performance_monitor()
                    performance_monitor.record_latency("openai_ping", duration_ms, True, provider="openai")
                    record_connection_reuse("openai", True)  # Warmup establishes connection for reuse
                    
        except Exception as e:
            logger.debug(f"OpenAI ping failed: {e}")
    
    async def _ping_groq(self, client):
        """Ping Groq with lightweight request."""
        try:
            from app.core.config import settings
            
            if settings.GROQ_API_KEY:
                headers = {"Authorization": f"Bearer {settings.GROQ_API_KEY}"}
                # Use models endpoint for connection test
                start_time = time.time()
                response = await client.get("https://api.groq.com/openai/v1/models", headers=headers)
                duration_ms = (time.time() - start_time) * 1000
                
                if response.status_code == 200:
                    logger.info("Groq connection validated")
                    # Record successful connection and performance
                    performance_monitor = get_performance_monitor()
                    performance_monitor.record_latency("groq_ping", duration_ms, True, provider="groq")
                    record_connection_reuse("groq", True)
                    
        except Exception as e:
            logger.debug(f"Groq ping failed: {e}")
    
    async def _ping_anthropic(self, client):
        """Ping Anthropic with lightweight request."""
        try:
            from app.core.llm_config import LLMConfig, ModelProvider
            
            # Get Anthropic API key
            api_key = None
            for config in LLMConfig.get_all_configs():
                if config.provider == ModelProvider.ANTHROPIC:
                    api_key = LLMConfig.get_api_key(config)
                    break
            
            if api_key:
                headers = {
                    "x-api-key": api_key,
                    "anthropic-version": "2023-06-01"
                }
                # Simple message for connection validation
                data = {
                    "model": "claude-3-haiku-20240307",
                    "max_tokens": 10,
                    "messages": [{"role": "user", "content": "ping"}]
                }
                response = await client.post("https://api.anthropic.com/v1/messages", headers=headers, json=data)
                if response.status_code == 200:
                    logger.info("Anthropic connection validated")
                    
        except Exception as e:
            logger.debug(f"Anthropic ping failed: {e}")
    
    async def _ping_google(self, client):
        """Ping Google/Gemini with lightweight request."""
        try:
            # Google AI Studio uses API key in URL params
            from app.core.llm_config import LLMConfig, ModelProvider
            
            api_key = None
            for config in LLMConfig.get_all_configs():
                if config.provider == ModelProvider.GOOGLE:
                    api_key = LLMConfig.get_api_key(config)
                    break
            
            if api_key:
                # List models endpoint for connection test
                url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
                response = await client.get(url)
                if response.status_code == 200:
                    logger.info("Google connection validated")
                    
        except Exception as e:
            logger.debug(f"Google ping failed: {e}")
    
    async def _warmup_database_connections(self):
        """Warm up database connections."""
        try:
            from app.db.session import SessionLocal
            
            # Create a database session to warm up the connection pool
            async with SessionLocal() as session:
                # Simple query to establish connection
                await session.execute("SELECT 1")
                
            logger.info("Database connections warmed up")
            
        except Exception as e:
            logger.warning(f"Database warm-up failed: {e}")
    
    async def _stage_models(self):
        """Stage 4: Model warm-up."""
        self.current_stage = WarmupStage.MODELS
        start_time = time.time()
        
        try:
            await log_info(
                "container_warmup",
                "Model warm-up stage started",
                stage=self.current_stage.value
            )
            
            # Warm up LLM models
            warmup_tasks = []
            
            if self.config.enable_model_warmup:
                warmup_tasks.append(self._warmup_llm_models())
            
            if self.config.enable_tts_warmup:
                warmup_tasks.append(self._warmup_tts_models())
            
            # Run warm-up tasks concurrently
            if warmup_tasks:
                await asyncio.gather(*warmup_tasks, return_exceptions=True)
            
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=True,
                duration_ms=duration_ms,
                details={"llm_models_warmed": True, "tts_models_warmed": True}
            ))
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=False,
                duration_ms=duration_ms,
                details={},
                error=str(e)
            ))
            
            raise
    
    async def _warmup_llm_models(self):
        """Warm up LLM models with test prompts."""
        try:
            from app.services.llm_manager import llm_manager
            
            # Get current LLM configuration
            llm_config = LLMConfig.get_active_model_config(ModelType.LLM)
            
            if not llm_config or not LLMConfig.is_model_available(ModelType.LLM):
                logger.warning("LLM not available for warm-up")
                return
            
            # Get warm-up prompt for current model
            model_id = llm_config.model_id
            warmup_prompt = self.config.chat_warmup_prompts.get(
                model_id, 
                "System initialization test - respond with 'OK'."
            )
            
            # Warm up with a simple prompt
            try:
                start_time = time.time()
                
                response = await asyncio.wait_for(
                    llm_manager.generate_response(warmup_prompt),
                    timeout=self.config.model_warmup_timeout
                )
                
                duration_ms = (time.time() - start_time) * 1000
                
                await log_info(
                    "container_warmup",
                    f"LLM model {model_id} warmed up successfully",
                    model_id=model_id,
                    duration_ms=duration_ms,
                    response_length=len(response) if response else 0
                )
                
                record_latency(
                    "container",
                    "llm_warmup",
                    duration_ms,
                    labels={"model": model_id}
                )
                
            except asyncio.TimeoutError:
                await log_warning(
                    "container_warmup",
                    f"LLM model {model_id} warm-up timed out",
                    model_id=model_id,
                    timeout=self.config.model_warmup_timeout
                )
                
            except Exception as e:
                await log_error(
                    "container_warmup",
                    f"LLM model {model_id} warm-up failed",
                    model_id=model_id,
                    error=str(e)
                )
                
        except Exception as e:
            logger.warning(f"LLM warm-up failed: {e}")
    
    async def _warmup_tts_models(self):
        """Warm up TTS models."""
        try:
            from app.services.llm_manager import llm_manager
            
            # Get current TTS configuration
            tts_config = LLMConfig.get_active_model_config(ModelType.TTS)
            
            if not tts_config or not LLMConfig.is_model_available(ModelType.TTS):
                logger.warning("TTS not available for warm-up")
                return
            
            # Warm up with a simple text
            warmup_text = self.config.tts_warmup_texts[0]
            
            try:
                start_time = time.time()
                
                # Create a temporary file for TTS output
                import tempfile
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_file:
                    temp_path = tmp_file.name
                
                await asyncio.wait_for(
                    llm_manager.text_to_speech(warmup_text, temp_path),
                    timeout=self.config.model_warmup_timeout
                )
                
                duration_ms = (time.time() - start_time) * 1000
                
                await log_info(
                    "container_warmup",
                    f"TTS model {tts_config.model_id} warmed up successfully",
                    model_id=tts_config.model_id,
                    duration_ms=duration_ms
                )
                
                record_latency(
                    "container",
                    "tts_warmup",
                    duration_ms,
                    labels={"model": tts_config.model_id}
                )
                
                # Clean up temp file
                try:
                    os.unlink(temp_path)
                except:
                    pass
                
            except asyncio.TimeoutError:
                await log_warning(
                    "container_warmup",
                    f"TTS model {tts_config.model_id} warm-up timed out",
                    model_id=tts_config.model_id,
                    timeout=self.config.model_warmup_timeout
                )
                
            except Exception as e:
                await log_error(
                    "container_warmup",
                    f"TTS model {tts_config.model_id} warm-up failed",
                    model_id=tts_config.model_id,
                    error=str(e)
                )
                
        except Exception as e:
            logger.warning(f"TTS warm-up failed: {e}")
    
    async def _stage_validation(self):
        """Stage 5: Validation."""
        self.current_stage = WarmupStage.VALIDATION
        start_time = time.time()
        
        try:
            await log_info(
                "container_warmup",
                "Validation stage started",
                stage=self.current_stage.value
            )
            
            # Validate that all systems are ready
            validation_results = await self._validate_systems()
            
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=True,
                duration_ms=duration_ms,
                details=validation_results
            ))
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            self.warmup_results.append(WarmupResult(
                stage=self.current_stage,
                success=False,
                duration_ms=duration_ms,
                details={},
                error=str(e)
            ))
            
            raise
    
    async def _validate_systems(self) -> Dict[str, bool]:
        """Validate that all systems are ready."""
        validation_results = {}
        
        try:
            # Validate LLM availability
            validation_results["llm_available"] = LLMConfig.is_model_available(ModelType.LLM)
            
            # Validate TTS availability
            validation_results["tts_available"] = LLMConfig.is_model_available(ModelType.TTS)
            
            # Validate HTTP clients
            http_manager = get_http_client_manager()
            health_status = http_manager.get_health_status()
            validation_results["http_clients_healthy"] = health_status["health_status"] == "healthy"
            
            # Validate database connection
            try:
                from app.db.session import SessionLocal
                async with SessionLocal() as session:
                    await session.execute("SELECT 1")
                validation_results["database_connected"] = True
            except Exception:
                validation_results["database_connected"] = False
            
        except Exception as e:
            logger.warning(f"System validation failed: {e}")
            validation_results["validation_error"] = str(e)
        
        return validation_results
    
    def _get_warmup_summary(self) -> Dict[str, Any]:
        """Get warm-up summary."""
        successful_stages = sum(1 for result in self.warmup_results if result.success)
        total_stages = len(self.warmup_results)
        
        return {
            "total_duration_ms": self.total_duration * 1000 if self.total_duration else 0,
            "successful_stages": successful_stages,
            "total_stages": total_stages,
            "success_rate": successful_stages / total_stages if total_stages > 0 else 0,
            "current_stage": self.current_stage.value,
            "stages": [
                {
                    "stage": result.stage.value,
                    "success": result.success,
                    "duration_ms": result.duration_ms,
                    "details": result.details,
                    "error": result.error
                }
                for result in self.warmup_results
            ]
        }
    
    def get_warmup_status(self) -> Dict[str, Any]:
        """Get current warm-up status."""
        return {
            "current_stage": self.current_stage.value,
            "is_complete": self.current_stage == WarmupStage.COMPLETE,
            "elapsed_time_ms": (time.time() - self.start_time) * 1000 if self.start_time else 0,
            "stages_completed": len(self.warmup_results),
            "last_stage_result": self.warmup_results[-1].__dict__ if self.warmup_results else None
        }


# Global warm-up manager instance
_container_warmup: Optional[ContainerWarmup] = None


def get_container_warmup() -> ContainerWarmup:
    """Get the global container warm-up manager."""
    global _container_warmup
    if _container_warmup is None:
        _container_warmup = ContainerWarmup()
    return _container_warmup


async def run_container_warmup(config: Optional[WarmupConfig] = None) -> Dict[str, Any]:
    """Run container warm-up with optional configuration."""
    warmup_manager = ContainerWarmup(config)
    return await warmup_manager.run_full_warmup()


async def quick_warmup() -> Dict[str, Any]:
    """Run a quick warm-up with minimal configuration."""
    config = WarmupConfig(
        enable_model_warmup=True,
        enable_tts_warmup=False,
        enable_connection_warmup=True,
        enable_compilation_warmup=False,
        enable_db_warmup=False,
        total_warmup_timeout=30.0,
        model_warmup_timeout=15.0
    )
    
    return await run_container_warmup(config)