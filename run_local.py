"""
Simple script to run the app locally for testing.
"""
import os
import uvicorn
from app.main import app

if __name__ == "__main__":
    # Set API keys in environment for testing
    os.environ["OPENAI_API_KEY"] = "***REMOVED***"
    os.environ["OPENAI_TTS_MODEL"] = "gpt-4o-mini-tts"
    os.environ["OPENAI_TTS_VOICE"] = "sage"
    
    # Run the app
    port = int(os.environ.get("PORT", 8080))
    print(f"Starting server on port {port}...")
    uvicorn.run(app, host="0.0.0.0", port=port) 