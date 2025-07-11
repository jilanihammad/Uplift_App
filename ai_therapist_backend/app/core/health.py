"""
Health check module to monitor service status and ensure the API can respond
regardless of individual service status.
"""

import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def get_health_status():
    """Get the health status of all services using unified LLM manager"""
    
    health_info = {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "environment": os.environ.get("ENVIRONMENT", "development"),
        "port": os.environ.get("PORT", "8080"),
        "services": {
            "api": "available"
        }
    }
    
    # Check services via unified LLM manager
    try:
        from app.services.llm_manager import llm_manager
        
        # Get comprehensive status from unified manager
        manager_status = llm_manager.get_status()
        
        # Add LLM service status
        llm_config = manager_status["configurations"]["llm"]
        if llm_config["available"]:
            health_info["services"]["llm"] = f"available - {llm_config['provider']} ({llm_config['model']})"
        else:
            health_info["services"]["llm"] = f"unavailable - {llm_config['provider']} not configured"
        
        # Add TTS service status
        tts_config = manager_status["configurations"]["tts"]
        if tts_config["available"]:
            health_info["services"]["tts"] = f"available - {tts_config['provider']} ({tts_config['model']})"
        else:
            health_info["services"]["tts"] = f"unavailable - {tts_config['provider']} not configured"
        
        # Add transcription service status
        transcription_config = manager_status["configurations"]["transcription"]
        if transcription_config["available"]:
            health_info["services"]["transcription"] = f"available - {transcription_config['provider']} ({transcription_config['model']})"
        else:
            health_info["services"]["transcription"] = f"unavailable - {transcription_config['provider']} not configured"
        
        # Add available providers info
        health_info["available_providers"] = manager_status["available_providers"]
        health_info["active_models"] = manager_status["model_info"]
        
    except Exception as e:
        logger.warning(f"LLM manager health check failed: {str(e)}")
        health_info["services"]["llm_manager"] = f"unavailable - {str(e)}"
        health_info["status"] = "degraded"
    
    # Get connection monitor health
    try:
        from app.core.connection_monitor import get_connection_monitor
        monitor = get_connection_monitor()
        connection_health = monitor.get_connection_stats()
        health_info["resource_monitoring"] = {
            "connection_monitor": {
                "status": "available",
                "total_connections": connection_health.get("monitor_stats", {}).get("total_connections_created", 0),
                "active_connections": len(connection_health.get("connections", [])),
                "cleanup_operations": connection_health.get("monitor_stats", {}).get("total_cleanup_operations", 0)
            }
        }
    except ImportError:
        health_info["resource_monitoring"] = {
            "connection_monitor": {"status": "not_available", "reason": "Connection monitor not installed"}
        }
    except Exception as e:
        health_info["resource_monitoring"] = {
            "connection_monitor": {"status": "error", "error": str(e)}
        }
    
    # Get HTTP client manager health
    try:
        from app.core.http_client_manager import get_http_client_manager
        http_manager = get_http_client_manager()
        http_health = http_manager.get_health_status()
        health_info["resource_monitoring"]["http_client_manager"] = http_health
    except ImportError:
        health_info["resource_monitoring"]["http_client_manager"] = {
            "status": "not_available", "reason": "HTTP client manager not installed"
        }
    except Exception as e:
        health_info["resource_monitoring"]["http_client_manager"] = {
            "status": "error", "error": str(e)
        }
    
    return health_info 