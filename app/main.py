import os
import logging
import traceback
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.cors import CORSMiddleware

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Debug environment variables at startup
logger.info("=================== STARTUP DEBUG ===================")
logger.info(f"PORT env var: {os.environ.get('PORT', 'not set')}")
logger.info(f"OPENAI_API_KEY env var: {'set (not showing value)' if os.environ.get('OPENAI_API_KEY') else 'NOT SET'}")
logger.info(f"OPENAI_TTS_MODEL env var: {os.environ.get('OPENAI_TTS_MODEL', 'not set')}")
logger.info(f"OPENAI_TTS_VOICE env var: {os.environ.get('OPENAI_TTS_VOICE', 'not set')}")
logger.info(f"Current working directory: {os.getcwd()}")
logger.info(f"Directory contents: {os.listdir('.')}")
logger.info("====================================================")

# Create FastAPI app
app = FastAPI(
    title="AI Therapist Backend",
    description="API for AI Therapist App",
    version="1.0.0"
)

# Setup CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static files
try:
    app.mount("/audio", StaticFiles(directory="static/audio"), name="audio")
except Exception as e:
    logger.error(f"Error mounting static files: {str(e)}")

try:
    from app.api.api_v1.api import api_router
    app.include_router(api_router, prefix="/api/v1")
except Exception as e:
    error_msg = f"Error during imports: {str(e)}"
    stack_trace = traceback.format_exc()
    logger.error(error_msg)
    logger.error(stack_trace)

@app.get("/health")
async def health():
    """Health check endpoint for container health checks"""
    logger.info("Health check endpoint called")
    return {"status": "ok"}

@app.get("/")
async def root():
    """Root endpoint"""
    logger.info("Root endpoint called")
    return {"message": "AI Therapist Backend API"}

@app.exception_handler(Exception)
async def handle_exception(request: Request, exc: Exception):
    """Global exception handler"""
    logger.error(f"Unhandled exception: {str(exc)}")
    logger.error(traceback.format_exc())
    return JSONResponse(
        status_code=500,
        content={"message": "Internal server error"}
    ) 