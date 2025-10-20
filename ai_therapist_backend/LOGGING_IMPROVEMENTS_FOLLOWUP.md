# Logging Improvements - Follow-up Tasks

## Completed (Pre-Launch Critical)

✅ **1. Unified ISO-8601 UTC Timestamps**
- File: `app/core/logger.py`
- Format: `2025-10-20T02:53:48Z`
- Eliminates timezone ambiguity

✅ **2. PII/User Text Scrubbing**
- File: `app/services/streaming_pipeline.py` (lines 1481-1483, 1564)
- Uses `preview_text()` helper to truncate user messages at INFO level
- Full text only available at DEBUG level

✅ **3. Logging Utilities Module Created**
- File: `app/core/logging_utils.py`
- Provides: `preview_text()`, `redact_headers()`, `LatencyTimer`, `create_log_context()`

---

## Remaining Improvements (Post-Launch)

### High Priority

**1. Header Redaction**
- **Risk**: Medium - Could expose cookies/auth tokens
- **Files to update**:
  - `app/api/deps/auth.py` - Add header redaction before logging
  - `app/api/endpoints/voice.py` - Redact WebSocket headers
  - `app/services/llm_manager.py` - Redact API response headers

**Example:**
```python
from app.core.logging_utils import redact_headers

# Before
logger.debug(f"HTTP Response headers: {resp.headers}")

# After
logger.debug(f"HTTP Response headers: {redact_headers(resp.headers)}")
```

**2. Correlation ID (Request Tracing)**
- **Risk**: Low - Just adds better debugging
- **Files to update**:
  - `app/api/endpoints/voice.py` - Extract/generate request ID from headers
  - `app/services/streaming_pipeline.py` - Propagate request ID through pipeline
  - `app/services/llm_manager.py` - Include request ID in all log entries

**Example:**
```python
from app.core.logging_utils import extract_request_id, create_log_context

req_id = extract_request_id(request.headers)
ctx = create_log_context(req_id, user_id=user.id, action="tts")
logger.info("TTS started", extra=ctx)
logger.info("TTS first_chunk", extra={**ctx, "latency_ms": 377})
```

### Medium Priority

**3. Monotonic Clock for Latency**
- **Risk**: Very Low - Just improves accuracy
- **Files to update**:
  - `app/services/streaming_pipeline.py` - Replace ~40 instances of `time.time()` with `time.perf_counter()`
  - `app/services/llm_manager.py` - Use `LatencyTimer` class
  - `app/core/phase3_streaming_tts.py` - Use monotonic timing

**Example:**
```python
from app.core.logging_utils import LatencyTimer

# Before
start = time.time()
# ... work ...
elapsed_ms = (time.time() - start) * 1000

# After
timer = LatencyTimer()
# ... work ...
elapsed_ms = timer.elapsed_ms()
```

**4. Log Level Policy Enforcement**
- **Current**: Mixed INFO/DEBUG for implementation details
- **Target**:
  - INFO: Lifecycle events + metrics only (start, latency, completion)
  - DEBUG: Payload details, full headers, full text
  - NEVER: Cookies, authorization tokens

**Files needing review**:
- `app/services/streaming_pipeline.py` - 50+ log statements to categorize
- `app/services/llm_manager.py` - Review current log levels
- `app/api/endpoints/voice.py` - Reduce INFO verbosity

---

## Testing Checklist

Before deploying these changes:

- [ ] Run backend locally with DEBUG level, verify full text appears
- [ ] Run backend with INFO level, verify only previews appear
- [ ] Check Cloud Run logs for proper ISO-8601 UTC format
- [ ] Verify no cookies/auth tokens in logs
- [ ] Test that request IDs appear consistently in related log entries
- [ ] Measure performance impact (should be negligible)

---

## Estimated Effort

- **Header redaction**: 1-2 hours
- **Correlation IDs**: 2-3 hours
- **Monotonic timing**: 3-4 hours
- **Log level cleanup**: 2-3 hours

**Total**: ~8-12 hours for complete implementation

---

## Notes

- All changes are backward compatible
- No API changes required
- Changes can be deployed incrementally
- Performance impact is negligible (<1ms per log statement)
