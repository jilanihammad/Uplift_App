"""Health check endpoints"""
from fastapi import APIRouter, status
from datetime import datetime
from typing import Dict, Any

from app.core.health import get_health_status
from app.core.config import settings

router = APIRouter()


@router.get("/health", status_code=status.HTTP_200_OK)
async def health_check() -> Dict[str, Any]:
    """Health check endpoint for load balancers and monitoring."""
    return get_health_status()


@router.get("/performance", status_code=status.HTTP_200_OK)
async def performance_report() -> Dict[str, Any]:
    """Performance monitoring endpoint for optimization tracking."""
    try:
        from app.core.performance_monitor import get_performance_report
        from app.core.http_client_manager import get_http_client_manager
        
        performance_data = get_performance_report()
        http_manager = get_http_client_manager()
        http_health = http_manager.get_health_status()
        
        return {
            "status": "ok",
            "timestamp": datetime.utcnow().isoformat(),
            "performance_metrics": performance_data,
            "http_client_health": http_health,
            "optimization_features": {
                "http2_enabled": True,
                "connection_pooling": "active",
                "dns_caching": "300s TTL",
                "container_warmup": "enabled",
                "openai_tts_streaming": settings.OPENAI_TTS_STREAM
            }
        }
    except Exception as e:
        return {
            "status": "error",
            "timestamp": datetime.utcnow().isoformat(),
            "error": str(e)
        }


@router.get("/metrics", status_code=status.HTTP_200_OK)
async def metrics_endpoint() -> Dict[str, Any]:
    """Real-time performance metrics endpoint."""
    try:
        from app.core.observability import observability_manager
        
        metrics_summary = observability_manager.get_health_status()
        
        return {
            "status": "ok",
            "timestamp": datetime.utcnow().isoformat(),
            "metrics": metrics_summary.get("metrics_summary", {}),
            "targets": {
                "llm_chat_ttfb_ms": {"target": "<500ms", "p95_target": "<1000ms"},
                "tts_first_byte_ms": {"target": "<300ms", "p95_target": "<500ms"},
                "provider_error_rate": {"target": "<5%", "p95_target": "<10%"}
            }
        }
    except Exception as e:
        return {
            "status": "error",
            "timestamp": datetime.utcnow().isoformat(),
            "error": str(e)
        }
