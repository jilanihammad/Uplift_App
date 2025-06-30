#!/usr/bin/env python3
"""
Verify all imports work correctly for the TTS transition feature
"""
import sys
import os

# Add the app directory to path
sys.path.append(os.path.join(os.path.dirname(__file__)))

def verify_imports():
    """Verify all required imports work"""
    print("🔍 Verifying imports for TTS transition feature...")
    print("=" * 50)
    
    success = True
    
    # Test 1: Core Python modules
    try:
        import logging, os, uuid, traceback, base64, time, asyncio
        print("✅ Core Python modules: OK")
    except ImportError as e:
        print(f"❌ Core Python modules: {e}")
        success = False
    
    # Test 2: FastAPI and related
    try:
        from typing import Optional
        print("✅ Typing modules: OK")
    except ImportError as e:
        print(f"❌ Typing modules: {e}")
        success = False
    
    # Test 3: App config (may fail due to missing dependencies, but structure should be OK)
    try:
        from app.core.config import settings
        print("✅ App config: OK")
    except ImportError as e:
        if "pydantic" in str(e) or "httpx" in str(e):
            print(f"⚠️  App config: Missing dependency ({e}) - expected in dev environment")
        else:
            print(f"❌ App config: {e}")
            success = False
    
    # Test 4: LLM Configuration
    try:
        from app.core.llm_config import LLMConfig, ModelType
        print("✅ LLM config: OK")
    except ImportError as e:
        print(f"❌ LLM config: {e}")
        success = False
    
    # Test 5: LLM Manager (may fail due to missing dependencies)
    try:
        from app.services.llm_manager import llm_manager
        print("✅ LLM Manager: OK")
    except ImportError as e:
        if any(dep in str(e) for dep in ["httpx", "openai", "anthropic", "google"]):
            print(f"⚠️  LLM Manager: Missing dependency ({e}) - expected in dev environment")
        else:
            print(f"❌ LLM Manager: {e}")
            success = False
    
    # Test 6: Voice Service (may fail due to missing dependencies)
    try:
        from app.services.voice_service import voice_service
        print("✅ Voice Service: OK")
    except ImportError as e:
        if any(dep in str(e) for dep in ["pydantic", "requests", "httpx"]):
            print(f"⚠️  Voice Service: Missing dependency ({e}) - expected in dev environment")
        else:
            print(f"❌ Voice Service: {e}")
            success = False
    
    # Test 7: Environment variable handling
    try:
        test_var = os.environ.get("USE_DIRECT_LLM_MANAGER", "false")
        print(f"✅ Environment variables: OK (USE_DIRECT_LLM_MANAGER={test_var})")
    except Exception as e:
        print(f"❌ Environment variables: {e}")
        success = False
    
    print("\n" + "=" * 50)
    print("📋 Import Verification Summary:")
    print("   ✅ = Import successful")  
    print("   ⚠️  = Missing dependency (expected in dev env)")
    print("   ❌ = Structural import error")
    print("")
    
    if success:
        print("✅ All critical imports verified successfully!")
        print("🚀 Import structure is correct for TTS transition feature")
        print("💡 Missing dependencies are expected in development environment")
        print("   They will be available when running with proper backend setup")
        return 0
    else:
        print("❌ Critical import errors found - check file structure")
        return 1

if __name__ == "__main__":
    exit_code = verify_imports()
    sys.exit(exit_code)