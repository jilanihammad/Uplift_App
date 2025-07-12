#!/usr/bin/env python3
"""
Local development server for AI Therapist Backend.

Environment variables are loaded from .env.dev (then .env fallback)
via python-dotenv in app/main.py

Usage: python dev_server.py

This script provides:
- Auto-reload on file changes
- Local SQLite database
- Debug logging enabled
- Port 8000 for local development
"""
import uvicorn

if __name__ == "__main__":
    print("🚀 Starting AI Therapist Backend Development Server")
    print("📁 Environment: .env.dev (with fallback to .env)")
    print("🔄 Auto-reload: Enabled")
    print("🌐 Server: http://localhost:8000")
    print("❤️  Health check: http://localhost:8000/health")
    print("")
    
    uvicorn.run(
        "app.main:app", 
        host="0.0.0.0", 
        port=8000, 
        reload=True,  # Auto-reload on file changes
        log_level="info"
    )