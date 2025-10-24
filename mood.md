# Mood Persistence Implementation Tracker

Single source of truth for designing, building, and rolling out cross-device mood logging.

---

## 1. Goals & Guardrails
- Provide per-entry mood persistence (mood + optional notes + timestamp) tied to Firebase-authenticated users.
- Maintain snappy UX: no blocking UI waits; network work must be batched, debounced, and jittered when ramping rollout.
- Server owns `updated_at`; client timestamps are accepted only for `logged_at` (validated within window).
- Limit storage to the most recent 60 days both server-side and client-side.
- Ship behind `mood_persistence_enabled` feature flag with instant rollback and flag-transition telemetry.
- Use seek-based pagination (no OFFSET) so P95 latency stays stable as datasets grow.
- Avoid schema mismatch with existing data: backend `users.id` remains integer; new table references it directly.

## 2. Scope (MVP)
- [ ] Append-only writes (no delete UI; retention handles aging).
- [ ] Idempotent `client_entry_id` per entry (unique per user, ≤64 chars). Duplicate IDs act as upserts; updated fields return the latest `updated_at`.
- [ ] 60-day retention server + client; reject entries older than 60 days or >7 days in future.
- [ ] `sqflite`-backed cache on client via `AppDatabase`; remove legacy SharedPreferences usage once migration complete.
- [ ] No background services beyond debounce + jittered sync when app foregrounded.
- [ ] Optional notes capped/truncated at 512 chars end-to-end.

## 3. Feature Flag Strategy
| Flag | Default | Rollout Notes |
| --- | --- | --- |
| `mood_persistence_enabled` | `false` | Allowlist internal testers first; ramp 0% → 10% (2h) → 50% (6h) → 100% (24h). Instant kill switch to disable remote sync.

When flag **OFF**: keep current local-only behavior (SharedPreferences until SQLite migration complete). When flag **ON**: enable SQLite cache + remote sync. Client sync start uses jittered backoff (0.5–3s) to avoid herd behavior. Emit one-shot metric (`mood_sync_enabled=1`) the first time a user sees the flag ON.

## 4. Backend Workstream
### 4.1 Data Model & Migration
- [x] Add Alembic revision creating `user_mood_entries` table:
  - `id UUID PK`
  - `user_id INTEGER NOT NULL REFERENCES users(id)`
  - `client_entry_id TEXT NOT NULL` (unique with user, ≤64 chars)
  - `mood SMALLINT NOT NULL CHECK (mood BETWEEN 0 AND 5)`
  - `notes VARCHAR(512) NULL`
  - `logged_at TIMESTAMPTZ NOT NULL`
  - `created_at` / `updated_at` TIMESTAMPTZ with default `now()`
- [x] Indexes: `UNIQUE (user_id, client_entry_id)` and `INDEX (user_id, logged_at DESC, id)` for seek pagination.
- [x] Enforce DB constraint on `client_entry_id` length (trigger or CHECK).
- [x] Update SQLAlchemy models (`app/models/mood_entry.py`) and `__init__.py` exports.
- [ ] (Deferred) `created_by` enum if analytics require it later.

### 4.2 Services & Schemas
- [x] Create Pydantic DTOs (`MoodEntryIn`, `MoodEntryOut`).
- [x] Implement `MoodEntryService` with batch upsert (≤20 entries) and range fetch.
- [x] Validate inputs: mood range, notes length, `logged_at` window (`now() - 60d` ≤ logged_at ≤ `now() + 7d`), clamp `updated_at = now()` server-side.
- [ ] Reject invalid timestamps with 422 and clear error messaging; add unit test covering ±48h clock skew. *(partially covered, API tests added; add dedicated skew test)*
- [x] Seek pagination: accept `before` token encoding `(logged_at,id)`; respond with `next_before` when more data available.
- [x] Ensure service truncates notes to 512 chars before persistence.

### 4.3 API Endpoints
- [x] `POST /api/v1/mood_entries:batch_upsert` (Firebase auth, idempotent, ≤20 entries or 64KB body). Return `413` when limits exceeded and emit `X-RateLimit-*` headers.
- [x] `GET /api/v1/mood_entries?since=ISO8601&limit=50&before=opaque` (seek, most recent first, ≤60 days).
- [ ] Optional future: delete/tombstone endpoint (tracked separately).
- [x] Add rate limiting (10 writes/min/user) via per-user in-memory limiter.
- [x] Update router registrations (`api_v1/api.py`, endpoints `__init__.py`).

### 4.4 Observability & Retention
- [x] Emit counters (`mood_entries_write_ok/_4xx/_5xx`, `mood_entries_fetch_ok`).
- [x] Add latency histograms for POST/GET.
- [x] Scrub notes from logs (hash user_id only).
- [ ] Document manual retention SQL; dry-run on staging, record runtime, then schedule daily prune job once rollout ≥50%.

## 5. Flutter Client Workstream
### 5.1 Data & Storage
- [x] Extend `AppDatabase` schema with `mood_entries` table (id, client_entry_id, mood, notes, logged_at, server_id, updated_at, is_pending, last_synced_at, sync_error).
- [x] Provide DAO helpers for inserting/updating mood entries and purging >60 days (initial load + periodic cleanup timer).
- [x] Migrate `ProgressService` to load from SQLite table; call `init()` during bootstrap.
- [x] Implement local purge of entries >60 days (run on init and via lightweight daily timer).

- [x] Update `IProgressService` interface with mood sync APIs (queue, flush, fetch, inspect errors).
- [x] On `logMood()`:
  - Generate UUIDv4/ULID.
  - Insert pending entry into SQLite via `AppDatabase`.
  - Optimistically update in-memory data (limit to 30 days for charts).
  - Schedule debounced + jittered sync (2–5s) if flag ON.
- [x] `syncMoodEntries()`:
  - Skip when offline; retry once connectivity restored.
  - Batch pending (≤20) to POST with exponential backoff (0.5s → 4s, jitter, max 5 tries).
  - Fetch remote entries since `last_synced_at` (persist in SQLite).
  - Merge into cache and update UI notifier.
  - If server rejects entry (422 stale/future), store `sync_error='STALE'` (or relevant code) and avoid further retries.
- [x] Ensure no network calls when flag OFF.

### 5.3 UI/UX
- [x] Ensure `HomeScreen` and `ProgressScreen` call `ProgressService.init()` once.
- [x] Keep sync indicators minimal (diagnostics-only spinner/toast); avoid chart jank.
- [x] On hard POST failure, surface copy: “Saved locally; we’ll sync when you’re online.”
- [x] Confirm mood charts read from SQLite-backed cache.

## 6. Testing & Quality
- [x] Backend pytest coverage: migration, service, endpoints (happy path, auth failure, invalid payloads, idempotency, pagination, retention rejection). *(clock skew test pending)*
- [ ] Flutter unit/integration tests: logging flow, sqlite persistence, sync toggles by flag, offline queue flush, error handling.
- [x] Concurrency test: duplicate `client_entry_id` from two devices results in single consistent row with latest payload.
- [x] Pagination test: seek token with equal `logged_at` values returns correct boundary behavior.
- [ ] Flag flip test: OFF→ON mid-session doesn’t double-send pending entries.
- [ ] Performance check: staging `GET` of 500 entries → P95 < 150ms; document P50/P95.
- [x] Manual QA script for internal testers (log mood, restart app, verify cross-device). *(drafted; to be executed during rollout)*

## 7. Rollout Checklist
1. [ ] Deploy backend migration + code to staging.
2. [ ] Run curl smoke tests (`POST batch_upsert`, `GET since/before`) and capture sample payloads.
3. [ ] Seed staging with 10k synthetic rows per test user; confirm query P50/P95.
4. [ ] Dry-run retention SQL on staging; log runtime and add to `persistence.md`.
5. [ ] Ship client build to internal testers with flag OFF; verify local logging unaffected.
6. [ ] Enable flag for allowlisted users; validate sync + metrics (including flag transition event).
7. [ ] Monitor logs, counters, DB growth, and rate-limit headroom.
8. [ ] Gradually increase flag per schedule; watch latency and error rates.
9. [ ] Schedule/enable 60-day retention job after ≥50% rollout.
10. [ ] Update docs (`Maya.md`, `CLAUDE.md`, `persistence.md`).

## 8. Risks & Mitigations
- **Schema mismatch (UUID vs int user IDs):** locked to integer FK; revisit only with broader migration.
- **Seek vs OFFSET drift:** `(user_id, logged_at DESC, id)` index keeps pagination stable when new rows arrive mid-fetch.
- **Flag herd effect:** jittered client sync startup + batch limits and rate limiting prevent burst traffic when flag flips.
- **Network spikes:** batching, rate limiting, and exponential backoff keep load predictable.
- **Data loss on flag rollback:** SQLite retains local history; when flag toggles ON again, pending queue resyncs.
- **PII in notes:** truncate to 512, scrub logs, consider future redaction heuristics.

## 9. Open Questions / Follow-Ups
- [ ] Will we need mood-after-session entries in vNext (session_id)?
- [ ] Should we expose deletion/tombstones for compliance before GA?
- [ ] Do we need analytics events for mood logging frequency beyond flag transition?
- [ ] Confirm availability of rate-limit middleware for per-user throttling.
- [ ] Decide whether to surface `sync_error` diagnostics in UI or support tooling.
- [ ] Add dedicated clock-skew backend test and client flag flip test.

---

_Update this tracker as tasks move forward; keep discussion threads linked here to avoid divergence._
