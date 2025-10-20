# Persistence & Personalization Recovery Plan

## Goal
Persist a minimal, safe subset of personalization (profile basics, vetted anchors, lightweight session summaries) with reliable sync, clear rollback, and low privacy risk.

---

## 1. Scope & Audit
- [ ] Confirm scope guardrails: this patch touches only user profile (preferred_name, pronouns, locale), anchors (non-generic, confidence-gated), and session summaries; defer mood logs, streaks, and free-form memories.
- [ ] Trace where these three domains are currently stored client-side (`MemoryManager`, `PreferencesService`, `SessionRepository`) and document serialization formats.
- [ ] Review backend models/routes to verify no existing persistence for these domains; list any partial overlaps (e.g., current `sessions` table).
- [ ] Inventory privacy considerations for each field (e.g., anchors may contain PII) to inform logging and retention later.

## 2. Data Model & Contracts
- [ ] Define Alembic-backed SQLAlchemy models:
  - `user_profile`: `id (uuid pk)`, `user_id (unique fk)`, `preferred_name`, `pronouns`, `locale`, `version`, `updated_at`.
  - `session_anchor`: `id (uuid pk)`, `user_id`, `client_anchor_id` (unique per user), `anchor_text`, `anchor_type`, `confidence`, `is_deleted`, `last_seen_session_index`, `updated_at`.
  - `session_summary`: `id (uuid pk)`, `user_id`, `session_id` (unique per user), `summary_json`, `updated_at`.
- [ ] Add indices (`user_id`, `updated_at`) and enforce soft deletes via `is_deleted`.
- [ ] Plan REST endpoints with Firebase JWT auth, optimistic concurrency (ETag/If-Match) for profile, idempotent upserts for anchors/summaries, and tombstone propagation.
- [ ] Specify headers (`X-Client-Request-Id`, `If-Match`) and response payloads (server `updated_at`, IDs) for reconciliation.

## 3. Backend Implementation
- [ ] Scaffold Alembic migrations (with downgrade) for the three tables; test locally.
- [ ] Implement SQLAlchemy models + services (`profile_service.py`, `anchor_service.py`, `session_summary_service.py`) with row-level auth enforcing `user_id`.
- [ ] Add FastAPI routers under `/v1/profile`, `/v1/anchors`, `/v1/session_summaries`:
  - `GET /v1/profile` → current profile + `etag`.
  - `PUT /v1/profile` → optimistic update; return new `etag`.
  - `GET /v1/anchors?since=` → deltas with tombstones.
  - `POST /v1/anchors:upsert` → idempotent upsert by `client_anchor_id`.
  - `POST /v1/anchors:delete` → mark tombstone.
  - `POST /v1/session_summaries:upsert` → idempotent by `session_id`.
- [ ] Ensure logging avoids PII (no raw anchor text) and honor `X-Client-Request-Id` for traceability.

## 4. Flutter Sync Layer
- [ ] Introduce a lightweight `SyncManager` inside `MemoryService` to:
  - Pull profile + anchor deltas on app start/login (respecting `last_sync_at`).
  - Queue anchor upserts/deletes with client-generated `client_anchor_id` (UUID v4) and retry/backoff.
  - Upsert session summaries immediately after `/therapy/end_session` completes, mapping to backend `session_id`.
- [ ] Update `MemoryManager` to call `syncManager.upsertAnchor/deleteAnchor` whenever anchors change, and to hydrate from server on init.
- [ ] Maintain optimistic UI updates with rollback on hard failures; never block interactions on network calls.
- [ ] Store `last_sync_at` per user and persist pending ops via existing queue or new local table.

## 5. Conflict & Offline Strategy
- [ ] Profile: use ETag/`version`; on 412 refetch, merge client edits, retry once.
- [ ] Anchors: last-write-wins using `updated_at`; server authoritative timestamp; deletions outrank updates when timestamps match.
- [ ] Session summaries: idempotent on `session_id`; overwrite existing server record if newer `updated_at` arrives.
- [ ] Ensure offline queue flushes with exponential backoff (≤5 min) and expose manual “Retry sync” control.
- [ ] Display fallback copy (“Your saved details will appear here after they sync.”) when remote data unavailable.

## 6. Testing & Observability
- [ ] Backend: pytest coverage for migrations, services, and API contracts including optimistic concurrency and tombstones.
- [ ] Frontend: integration tests confirming profile/anchor persistence across restart and conflict resolution behaviors.
- [ ] Instrument endpoints with structured logs + metrics (request counts, error rates, latency); ensure no anchor_text in logs.
- [ ] Update CI to run Alembic migrations in ephemeral DB and execute new test suites.
- [ ] Configure dashboards/alerts for sync failure spikes or backlog growth.

## 7. Rollout & Backfill
- [ ] Gate new sync behavior behind remote-config flag `memory_persistence_enabled` and default to off until staging validation.
- [ ] Deploy backend to staging; run manual end-to-end sync tests with latest client builds.
- [ ] On first launch after upgrade: if local anchors exist but server empty, batch upsert with generated `client_anchor_id`; otherwise rely on mapping to dedupe.
- [ ] Provide GDPR endpoints (`POST /v1/user:delete_personalization`, `GET /v1/user:export_personalization`) or document as follow-up if out of scope.
- [ ] Update `Maya.md` + onboarding docs with new persistence architecture and support playbook.

---

## Deliverables
1. Minimal schemas (profile, anchors, session summaries) with Alembic migrations.
2. FastAPI endpoints + services implementing the scoped contracts.
3. Flutter sync layer (pull/push, conflict handling, offline queue) for the three domains.
4. Automated tests and monitoring instrumentation verifying persistence.
5. Documentation updates (Maya.md, support guides) and rollout toggles.
