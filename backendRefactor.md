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