# Backend Refactoring Plan - Gradual DI Implementation

## Executive Summary
This plan outlines a careful, phase-based approach to refactoring the AI Therapist backend from service locator patterns to proper dependency injection, prioritizing observability and safety.

## Phase 1: Safety First - Minimal Changes (Week 1-2)

### 1.1 AIService Removal Strategy
**Current State**: AIService exists in multiple locations but is only used in legacy tests
- **Files to Remove**:
  - `app/services/ai_service.py` (main file)
  - `cloud_deploy/app/services/ai_service.py` (deployment copy)
  - `cloud_deploy/app/app/services/ai_service.py` (nested deployment copy)
  - `app/services/openai_service (delete).py` (already marked for deletion)
  - `tests/test_services/test_ai_service.py` (legacy tests)

**Safety Measures**:
- **Create AIService stub** (`ai_service_stub.py`) that raises ImportError with clear migration message
- Add `PYTHONWARNINGS="error::DeprecationWarning"` to CI to catch stray imports
- Comprehensive grep for hidden references in scripts/configs/cron jobs
- Replace AIService tests with LLMManager tests before deletion
- Rollback plan: Keep files in version control for 30 days

### 1.2 Circuit Breaker Implementation
**Library Choice**: `aiobreaker` - battle-tested async circuit breaker
**Implementation Strategy**:
- Per-provider circuit breakers (OpenAI, Anthropic, Google, Groq)
- Per-method granularity (chat, TTS, STT)
- **Failure rate-based**: `fail_ratio=0.5, minimum_calls=20` (prevents single spike failures)
- State storage: In-memory with **Redis fallback** (degrade gracefully on Redis outages)
- Configuration: Rolling window tracking instead of absolute counters

**Target Methods**:
- `LLMManager.generate_response()`
- `LLMManager.text_to_speech()`
- `LLMManager.transcribe_audio()`

### 1.3 Observability Foundation
**Metrics Sink**: Google Cloud Monitoring with OpenTelemetry exporter
**Metrics Control**: Prefix all metrics with `custom.googleapis.com/llm/` and hard-limit label cardinality
**Request Tracing**: 
- Middleware for `X-Request-ID` injection/propagation
- `trace_id` correlation across services
- Structured logging with JSON format
- **Exclude outbound HTTP spans** from server-span duration to prevent double-counting

**Initial SLO Alerts**:
- 95% LLM latency < 2s
- Error rate < 2%
- Circuit breaker trip alerts

### 1.4 Early DI Container Introduction
**Strategy**: Introduce DI container for new services only (legacy services remain unchanged)
**Purpose**: Exercise container wiring for 2 sprints before major cutover
**Implementation**: 
- Create `Container` class with basic service registration
- Use for any new services created during Phase 1-2
- Existing services continue using service locator pattern

## Phase 2: Enhanced Observability (Week 3-4)

### 2.1 Comprehensive Metrics
**LLM Manager Metrics**:
- Request count by provider/method
- Response time percentiles (P50, P95, P99)
- Error rate by provider/error type
- Token usage and cost tracking
- Circuit breaker state changes

**Infrastructure Metrics**:
- Database connection pool usage
- WebSocket connection counts
- Memory usage by service
- CPU usage patterns

### 2.2 Distributed Tracing
**OpenTelemetry Integration**:
- Automatic FastAPI instrumentation
- Custom spans for LLM calls
- Cross-service correlation
- Performance waterfall visualization

### 2.3 Alerting Strategy
**Critical Alerts**:
- Service down (health check failures)
- High error rate (>5% for 5 minutes)
- High latency (P95 > 5s for 5 minutes)
- Circuit breaker trips

**Warning Alerts**:
- Moderate error rate (>2% for 10 minutes)
- Elevated latency (P95 > 2s for 10 minutes)
- Database connection pool exhaustion

## Phase 3: Dependency Injection Foundation (Week 5-6)

### 3.1 DI Container Selection
**Choice**: `dependency-injector` - Python's most mature DI framework
**Architecture**:
- Interface-based design with ABC classes
- Constructor injection throughout
- Singleton lifecycle management
- Configuration injection

### 3.2 Interface Definition
**Core Interfaces**:
- `ILLMProvider` (abstract base for AI providers)
- `IConfigurationService` (settings management)
- `IMetricsCollector` (observability)
- `IHealthChecker` (service health)

### 3.3 Service Registration
**Container Structure**:
```python
class Container(DeclarativeContainer):
    config = providers.Configuration()
    
    # Core services
    llm_manager = providers.Singleton(LLMManager, config=config)
    metrics_collector = providers.Singleton(MetricsCollector)
    health_checker = providers.Singleton(HealthChecker)
```

## Phase 4: Gradual Service Decomposition (Week 7-8)

### 4.1 Voice Service Refactoring
**Current State**: 1,688 lines, 9 dependencies
**Target**: <400 lines, 3 dependencies

**Two-Wave Decomposition Strategy**:
**Wave 1**: Extract stateless helpers (delegate back to VoiceService)
- `WebSocketConnectionService` (connection management)
- `SecurityValidationService` (auth/validation)

**Wave 2**: Migrate TTS pipeline (after helpers proven stable)
- `TTSStreamingService` (audio streaming)
- `PipelineCoordinatorService` (message routing)

**Buffer**: Reserve extra sprint for VoiceService decomposition if metrics show error-budget burn

### 4.2 Main Application Refactoring
**Factory Pattern Implementation**:
- `ApplicationFactory` for app creation
- `MiddlewareManager` for security/CORS
- `RouterManager` for endpoint registration

## Migration Safety Measures

### Canary Deployment Strategy
- **Progressive rollout**: 5% for 30 min → 25% for 1 hour → 100%
- Automated rollback on error rate increase
- A/B testing infrastructure
- Performance comparison dashboards

### Testing Strategy
**Pre-Migration**:
- Comprehensive unit tests for all new services
- Integration tests for API endpoints
- Load testing for performance regression
- Chaos engineering for failure scenarios

**During Migration**:
- Parallel running of old/new implementations
- Automated comparison of responses
- Real-time monitoring of key metrics
- Immediate rollback triggers

**Post-Migration**:
- 30-day observation period
- Performance optimization based on metrics
- Documentation updates
- Team training on new architecture

### Rollback Plan
**Immediate Rollback Triggers**:
- Error rate increase >50%
- Latency increase >100%
- Circuit breaker cascade failures
- Database connection failures

**Rollback Procedure**:
1. **Automated one-command rollback**: `gcloud run services update-traffic --to-revisions=PREVIOUS_VERSION=100`
2. Verify service health immediately
3. Post-incident review

**Enhanced Rollback**:
- Use `RELEASE_VERSION` tags in Cloud Run
- Single gcloud command flips traffic to previous tag
- Manual steps eliminated for faster incident response

## Success Metrics

### Technical Metrics
- **Code Quality**: Average service size <400 lines
- **Coupling**: Service dependencies <5 per service
- **Test Coverage**: >80% for all core services
- **Performance**: <500ms P95 response time maintained

### Operational Metrics
- **Reliability**: >99.9% uptime during migration
- **Observability**: 100% request tracing coverage
- **Security**: Zero security incidents
- **Deployment**: <5 minute deployment time

## Timeline Summary

| Phase | Duration | Key Deliverables | Risk Level |
|-------|----------|------------------|------------|
| 1 | Week 1-2 | AIService removal, circuit breakers, basic observability, early DI container | Low |
| 2 | Week 3-4 | Comprehensive metrics, distributed tracing, alerting | Low |
| 3 | Week 5-6 | DI container migration, interface definitions, service registration | Medium |
| 4 | Week 7-8 | Voice service decomposition (2 waves), factory patterns, final testing | High |

## Next Steps
1. **Immediate**: Begin Phase 1 with AIService removal
2. **Week 1**: Implement circuit breakers and basic observability
3. **Week 2**: Deploy to staging environment for testing
4. **Week 3**: Begin canary deployment with 5% traffic
5. **Week 4**: Full production deployment with monitoring

## Additional Implementation Details

### Circuit Breaker Deep Dive
**State Management**:
- **Closed**: Normal operation, tracking failures
- **Open**: Failing fast, rejecting requests
- **Half-Open**: Testing recovery, allowing single probe

**Enhanced Per-Provider Configuration**:
```python
CIRCUIT_BREAKER_CONFIG = {
    'openai': {
        'fail_ratio': 0.5, 
        'minimum_calls': 20,
        'reset_timeout': 60, 
        'expected_exception': OpenAIError
    },
    'anthropic': {
        'fail_ratio': 0.4,
        'minimum_calls': 15,
        'reset_timeout': 30, 
        'expected_exception': AnthropicError
    },
    'groq': {
        'fail_ratio': 0.6,
        'minimum_calls': 30,
        'reset_timeout': 120, 
        'expected_exception': GroqError
    }
}
```

### Observability Implementation
**Structured Logging Format**:
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "service": "llm_manager",
  "trace_id": "abc123",
  "request_id": "req-456",
  "provider": "openai",
  "method": "generate_response",
  "duration_ms": 1250,
  "tokens_used": 150,
  "model": "gpt-4"
}
```

**Metrics Collection Points**:
- API endpoint entry/exit
- LLM provider calls
- Database operations
- WebSocket connections
- Circuit breaker state changes

### Testing Strategy Details
**Unit Test Coverage Requirements**:
- All new services: 90% coverage
- Critical paths: 100% coverage
- Error handling: 100% coverage
- Circuit breaker logic: 100% coverage

**Integration Test Scenarios**:
- Provider failover sequences
- Circuit breaker activation/recovery
- Database connection failures
- WebSocket connection drops
- Authentication failures

**Load Testing Parameters**:
- **Real-world based**: Record actual prod RPS + concurrency during peak hour
- **Target**: 120% of production peak traffic
- 95% success rate maintained
- P95 latency < 2s
- Memory usage < 2GB
- CPU usage < 80%

## Risk Assessment Matrix

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Circuit breaker cascade failure | Medium | High | Gradual rollout, fallback mechanisms |
| Performance regression | Low | High | Extensive load testing, monitoring |
| Data loss during migration | Low | Critical | No database schema changes |
| Security vulnerability | Low | Critical | Security review, penetration testing |
| Deployment failure | Medium | Medium | Blue-green deployment, rollback plan |

## Monitoring and Alerting Configuration

### SLO Definitions
**Availability SLO**: 99.9% uptime
- Error budget: 43 minutes/month
- Measurement: HTTP 5xx errors + timeouts

**Latency SLO**: 95% of requests < 2s
- Error budget: 5% of requests
- Measurement: End-to-end API response time

**Throughput SLO**: Handle 1000 req/min
- Error budget: 10% capacity buffer
- Measurement: Successful requests per minute

### Alert Thresholds
**Critical (Page immediately)**:
- Error rate > 5% for 5 minutes
- Latency P95 > 5s for 5 minutes
- Service down for 2 minutes

**Warning (Slack notification)**:
- Error rate > 2% for 10 minutes
- Latency P95 > 2s for 10 minutes
- Circuit breaker open for 5 minutes

**Info (Dashboard only)**:
- Error rate > 1% for 15 minutes
- Latency P95 > 1s for 15 minutes
- High memory usage (>80%)

## Engineering Excellence Additions

### Security and Quality Gates
**Automated Security Scanning**:
- Add Threat Dragon or OWASP CRX scan to CI pipeline
- Block merges on new high-severity security issues
- DI + middleware changes require security review

**Type Safety Enforcement**:
- Enable `mypy --strict` for all new modules
- Legacy code remains opt-out until Phase 4
- Catches interface mismatches during DI migration

### AIService Stub Implementation
```python
# app/services/ai_service_stub.py
class AIService:
    def __init__(self, *args, **kwargs):
        raise ImportError(
            "AIService has been deprecated and replaced with LLMManager. "
            "Please update your imports to use: from app.services.llm_manager import llm_manager. "
            "See backendRefactor.md for complete migration guide."
        )
    
    def __getattr__(self, name):
        raise ImportError(f"AIService.{name} is deprecated. Use LLMManager instead.")
```

### Circuit Breaker Resilience Pattern
```python
# Redis fallback implementation
class CircuitBreakerStateStore:
    def __init__(self, redis_url=None):
        self.redis_client = None
        self.memory_store = {}
        
        if redis_url:
            try:
                self.redis_client = redis.from_url(redis_url)
            except Exception as e:
                logger.warning(f"Redis unavailable, using in-memory store: {e}")
    
    def get_state(self, key):
        if self.redis_client:
            try:
                return self.redis_client.get(key)
            except Exception as e:
                logger.warning(f"Redis get failed, using memory: {e}")
        return self.memory_store.get(key)
```

### Metrics Cardinality Control
```python
# Prevent metrics explosion
def sanitize_model_label(model_name):
    """Bucket rare models under 'other' to control cardinality"""
    common_models = {'gpt-4', 'gpt-3.5-turbo', 'claude-3', 'gemini-pro'}
    return model_name if model_name in common_models else 'other'

# Metrics with controlled labels
METRICS_CONFIG = {
    'prefix': 'custom.googleapis.com/llm/',
    'max_label_cardinality': 20,
    'common_labels': ['provider', 'method', 'status']
}
```

## Performance-First Approach Integration

### Latency-Focused KPIs
**Primary Speed Metrics**:
- **Steady-state P95**: Normal operation latency
- **Cold-start P95**: Container/model initialization latency
- **TTFB tracking**: Time-to-first-byte for chat/TTS/STT every minute

**Critical Path Instrumentation**:
`client → FastAPI router → LLMManager → provider-HTTP → LLMManager → WebSocket stream`
- Sample critical path at 100%
- Sample everything else at 1-10%

### Circuit Breaker Micro-Optimizations
**Sub-microsecond overhead techniques**:
```python
# Hot cache pattern - <1µs per call
class FastCircuitBreaker:
    def __init__(self):
        self.memory_state = {}  # Hot cache
        self.redis_sync_interval = 5  # seconds
        
    async def check_circuit(self, provider: str) -> bool:
        # Memory lookup - sub-microsecond
        state = self.memory_state.get(provider, "closed")
        
        # Parallel probe for half-open state
        if state == "half-open":
            probe_task = asyncio.create_task(self._probe_provider(provider))
            # Return immediately, update state async
            return True
            
    async def _sync_to_redis(self):
        # Background task - no request path impact
        while True:
            await asyncio.sleep(self.redis_sync_interval)
            await self._flush_state_to_redis()
```

### HTTP Client Hot-Rodding
**Connection Pool Optimization**:
```python
# Per-provider optimized sessions
PROVIDER_HTTP_CONFIG = {
    'openai': {
        'connector': aiohttp.TCPConnector(
            limit=100,
            keepalive_timeout=75,
            ttl_dns_cache=300,
            use_dns_cache=True
        ),
        'timeout': aiohttp.ClientTimeout(total=30, connect=5),
        'headers': {'Connection': 'keep-alive'}
    },
    'anthropic': {
        'connector': aiohttp.TCPConnector(
            limit=50,
            keepalive_timeout=60,
            ttl_dns_cache=300
        ),
        'timeout': aiohttp.ClientTimeout(total=45, connect=5)
    }
}

# HTTP/2 upgrade where supported
async def create_http2_session(provider_url: str):
    connector = aiohttp.TCPConnector(
        limit=100,
        force_close=False,
        enable_cleanup_closed=True
    )
    return aiohttp.ClientSession(
        connector=connector,
        timeout=aiohttp.ClientTimeout(total=30)
    )
```

### Streaming Performance Optimizations
**Token-1 Streaming**:
```python
async def stream_llm_response(prompt: str, websocket: WebSocket):
    async for chunk in llm_manager.generate_response_stream(prompt):
        # Send immediately on first token
        await websocket.send_text(chunk)
        # No buffering - minimize latency
```

**OPUS Streaming with Smart Buffering**:
```python
# Start playback after 4-8KB for optimal perceived performance
OPUS_BUFFER_THRESHOLDS = {
    'start_playback': 4096,  # 4KB
    'optimal_buffer': 8192,  # 8KB
    'max_buffer': 16384      # 16KB
}
```

### Container Warm-up Strategy
**Boot-time Optimization**:
```python
# Container startup sequence
async def warm_up_services():
    tasks = [
        warm_up_llm_models(),
        preload_tts_voices(),
        compile_pydantic_models(),
        establish_provider_connections()
    ]
    await asyncio.gather(*tasks)

async def warm_up_llm_models():
    # 5-token warm-up per model
    warm_up_prompts = {
        'gpt-4': 'Hello world test',
        'claude-3': 'System check',
        'gemini-pro': 'Initialization'
    }
    
    for model, prompt in warm_up_prompts.items():
        await llm_manager.generate_response(prompt, model=model)
```

### Observability with Micro-Overhead
**Smart Sampling Strategy**:
```python
# Production sampling configuration
OBSERVABILITY_CONFIG = {
    'tracing_sample_rate': 0.05,  # 5% in production
    'canary_sample_rate': 1.0,    # 100% in canary
    'metrics_export_interval': 5,  # 5 seconds
    'log_batch_size': 1000,
    'log_flush_interval': 2
}

# Non-blocking log queue
class PerformantLogger:
    def __init__(self):
        self.queue = asyncio.Queue(maxsize=10000)
        self.background_task = asyncio.create_task(self._flush_logs())
    
    async def log_async(self, message: dict):
        # Non-blocking - drops if queue full
        try:
            self.queue.put_nowait(message)
        except asyncio.QueueFull:
            # Emit metric about dropped logs
            pass
```

### Performance Gates and Validation
**Automated Performance Testing**:
```python
# Phase gate criteria
PERFORMANCE_GATES = {
    'phase_1': {
        'max_latency_increase': 0.10,  # 10% increase max
        'baseline_metric': 'p95_chat_ttfb',
        'test_load': '50_req_per_second'
    },
    'phase_2': {
        'max_latency_increase': 0.15,  # 15% with observability
        'baseline_metric': 'p95_chat_ttfb',
        'test_load': '100_req_per_second'
    },
    'phase_3': {
        'max_latency_delta': 0.05,  # 5% old vs new
        'comparison_type': 'a_b_test',
        'test_duration': '10_minutes'
    }
}
```

**CI Performance Validation**:
```bash
# Automated performance gate in CI
#!/bin/bash
# performance_gate.sh

# Run baseline test
k6 run --vus 50 --duration 60s baseline_test.js > baseline_results.json

# Run new implementation test  
k6 run --vus 50 --duration 60s current_test.js > current_results.json

# Compare results
python validate_performance.py baseline_results.json current_results.json --threshold 0.10

# Fail build if performance regression detected
if [ $? -ne 0 ]; then
    echo "Performance regression detected - failing build"
    exit 1
fi
```

### MessagePack Optimization
**Binary Protocol for Internal APIs**:
```python
# Use MessagePack for large payloads
import msgpack
import orjson

def serialize_payload(data: dict, use_msgpack: bool = True) -> bytes:
    if use_msgpack and len(str(data)) > 1024:  # >1KB
        return msgpack.packb(data)
    return orjson.dumps(data)

# 30-50% size reduction for large responses
def deserialize_payload(data: bytes, is_msgpack: bool = True) -> dict:
    if is_msgpack:
        return msgpack.unpackb(data, raw=False)
    return orjson.loads(data)
```

### Performance Monitoring Dashboard
**Real-time Performance Metrics**:
- **Latency Waterfall**: Breakdown of request components
- **Provider Performance**: Per-provider latency and success rates
- **Circuit Breaker Status**: State and trip frequency
- **Connection Pool Health**: Active connections and queue depth
- **Streaming Metrics**: TTFB, chunk delivery rate, buffer sizes

### Implementation Timeline with Performance Focus

| Phase | Performance Additions | Expected Latency Impact |
|-------|----------------------|-------------------------|
| 1 | HTTP optimization, warm-up, instrumentation | -30ms to -50ms |
| 2 | Circuit breaker optimization, smart sampling | -5ms to -10ms |
| 3 | MessagePack, streaming optimization | -10ms to -20ms |
| 4 | Profile-driven micro-optimizations | -5ms to -15ms |

**Total Expected Improvement**: 50-95ms latency reduction while improving reliability and observability.