"""
AI Therapist Backend Application
Main entry point with modular architecture
"""
import os
import sys
import logging
import traceback
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Dict, Any

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.requests import Request

# Load environment variables early
load_dotenv(".env.dev", override=False)
load_dotenv(".env", override=False)

# Import core components
from app.core.config import settings
from app.core.enhanced_logging import setup_logging, get_logger
from app.core.health import get_health_status
from app.core.request_middleware import RequestTracingMiddleware
from app.core.rate_limiter import RateLimitMiddleware
from app.core.security_middleware import SecurityMiddleware
from app.db.base import Base
from app.db.session import engine

# Setup logging first
setup_logging()
logger = get_logger(__name__)


def init_database() -> None:
    """Initialize database tables and verify connection."""
    try:
        with engine.connect() as connection:
            logger.info(f"Connected to database")
        
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created successfully")
    except Exception as e:
        logger.error(f"Database initialization error: {e}")
        logger.error(traceback.format_exc())
        raise


async def initialize_services() -> Dict[str, Any]:
    """Initialize all required services on startup."""
    results = {"successful": 0, "total": 0, "errors": []}
    
    # Check OpenAI SDK version
    try:
        import openai
        from packaging import version
        
        results["total"] += 1
        if version.parse(openai.__version__) < version.parse("1.85.0"):
            error_msg = f"OpenAI SDK >= 1.85.0 required, found {openai.__version__}"
            logger.error(error_msg)
            results["errors"].append(error_msg)
        else:
            logger.info(f"✅ OpenAI SDK {openai.__version__} compatible")
            results["successful"] += 1
    except ImportError:
        logger.warning("OpenAI SDK not installed")
        results["total"] += 1
    except Exception as e:
        logger.error(f"Error checking OpenAI SDK: {e}")
        results["errors"].append(str(e))
        results["total"] += 1
    
    # Initialize observability
    try:
        from app.core.observability import observability_manager
        results["total"] += 1
        await observability_manager.start()
        logger.info("✅ Observability system started")
        results["successful"] += 1
    except Exception as e:
        logger.warning(f"Observability startup failed: {e}")
        results["errors"].append(f"Observability: {e}")
        results["total"] += 1
    
    # Container warmup
    try:
        from app.core.container_warmup import quick_warmup
        results["total"] += 1
        warmup_result = await quick_warmup()
        logger.info(f"✅ Container warmup: {warmup_result.get('successful_stages', 0)}/{warmup_result.get('total_stages', 0)} stages")
        results["successful"] += 1
    except Exception as e:
        logger.warning(f"Container warmup failed: {e}")
        results["errors"].append(f"Warmup: {e}")
        results["total"] += 1
    
    return results


async def cleanup_services() -> None:
    """Cleanup all services on shutdown."""
    logger.info("Shutting down services...")
    
    # Shutdown HTTP clients
    try:
        from app.core.http_client_manager import get_http_client_manager
        http_manager = get_http_client_manager()
        await http_manager.stop_all_clients()
        logger.info("✅ HTTP clients shut down")
    except Exception as e:
        logger.warning(f"HTTP client shutdown error: {e}")
    
    # Shutdown observability
    try:
        from app.core.observability import observability_manager
        await observability_manager.stop()
        logger.info("✅ Observability system shut down")
    except Exception as e:
        logger.warning(f"Observability shutdown error: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup and shutdown."""
    logger.info(f"🚀 Starting {settings.PROJECT_NAME}")
    logger.info(f"Environment: {os.environ.get('ENVIRONMENT', 'development')}")
    
    # Initialize database
    try:
        init_database()
    except Exception as e:
        logger.critical(f"Database initialization failed: {e}")
        raise
    
    # Initialize services
    service_results = await initialize_services()
    logger.info(f"Services initialized: {service_results['successful']}/{service_results['total']}")
    
    if service_results["errors"]:
        logger.warning(f"Service initialization errors: {service_results['errors']}")
    
    yield
    
    # Shutdown
    await cleanup_services()
    logger.info("👋 Application shutdown complete")


def create_application() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(
        title=settings.PROJECT_NAME,
        description="AI Therapist API for mental health support",
        version="1.0.0",
        openapi_url=f"{settings.API_V1_STR}/openapi.json",
        docs_url=None,  # Disable default docs for security
        redoc_url=None,
        lifespan=lifespan
    )
    
    # Add middleware in correct order
    app.add_middleware(RequestTracingMiddleware)
    app.add_middleware(SecurityMiddleware)
    app.add_middleware(RateLimitMiddleware, requests_per_minute=60)
    
    # CORS configuration
    if settings.BACKEND_CORS_ORIGINS:
        origins = ["*"] if settings.BACKEND_CORS_ORIGINS == ["*"] else [str(o) for o in settings.BACKEND_CORS_ORIGINS]
        app.add_middleware(
            CORSMiddleware,
            allow_origins=origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    
    # Include API routers
    from app.api.api_v1.api import api_router
    from app.api.endpoints import health, sessions, ai_endpoints, voice_endpoints
    
    # Main API routes
    app.include_router(api_router, prefix=settings.API_V1_STR)
    
    # Legacy routes for backward compatibility
    app.include_router(health.router, tags=["health"])
    app.include_router(sessions.router, prefix="/sessions", tags=["sessions"])
    app.include_router(ai_endpoints.router, prefix="/ai", tags=["ai"])
    app.include_router(voice_endpoints.router, prefix="/voice", tags=["voice"])
    
    # Mount static files for audio
    static_path = "/tmp/static/audio" if os.environ.get("GOOGLE_CLOUD") == "1" else "static/audio"
    os.makedirs(static_path, exist_ok=True)
    
    from fastapi.staticfiles import StaticFiles
    app.mount("/audio", StaticFiles(directory=static_path), name="audio")
    
    # Exception handlers
    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception):
        logger.error(f"Unhandled exception: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"detail": "An unexpected error occurred", "timestamp": datetime.utcnow().isoformat()}
        )
    
    @app.exception_handler(404)
    async def not_found_handler(request: Request, exc):
        return JSONResponse(
            status_code=404,
            content={"detail": f"Route not found: {request.url.path}"}
        )
    
    # Root endpoint
    @app.get("/")
    async def root():
        health = get_health_status()
        return {
            "message": f"Welcome to {settings.PROJECT_NAME}",
            "status": health["status"],
            "version": "1.0.0",
            "timestamp": health["timestamp"]
        }
    
    return app


# Create the application instance
app = create_application()

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
