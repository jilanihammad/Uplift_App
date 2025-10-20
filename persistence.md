# Persistence & Personalization Recovery Plan

## Goal
Prevent loss of session history, anchors, and personalization by persisting them in the backend, syncing them reliably to the client, and validating the end-to-end flow.

---

## 1. Audit Current State
- [ ] Trace anchor/memory writes: map every call to `MemoryManager`, `PreferencesService`, and `SessionRepository` in the Flutter app; document which data never leaves the device.
- [ ] Review backend models (`app/models`) and API routes to confirm there are no tables/endpoints for anchors, user profiles, or personalization.
- [ ] Identify all data domains to persist (e.g., anchor summaries, preferred name/pronouns, mood logs, session metadata, streaks).
- [ ] Capture current serialization formats (JSON structures stored locally) to reuse or evolve when designing server contracts.

## 2. Design Server Contracts
- [ ] Draft REST/GraphQL schemas for user personalization (`/users/:id/profile`), anchors (`/users/:id/anchors`), and session metadata (`/sessions/:id/summary`).
- [ ] Define request/response payloads, including versioning fields, timestamps, and conflict-resolution metadata (e.g., `last_modified`).
- [ ] Decide on authentication + authorization strategy (Firebase JWT → FastAPI dependency) for new endpoints.
- [ ] Document retention and privacy requirements (GDPR deletion, export) before implementing.

## 3. Backend Storage & Services
- [ ] Create SQLAlchemy models/tables: `user_profile`, `session_anchor`, `user_preferences`, ensure foreign keys to `users`.
- [ ] Add Alembic migrations with downgrade paths; run locally and in staging DB.
- [ ] Implement CRUD services in `app/services` (e.g., `profile_service.py`, `anchor_service.py`) encapsulating DB access, validation, and business rules.
- [ ] Add FastAPI routers under `app/api/endpoints` for profile and anchor management (create, update, list, delete).
- [ ] Cover edge cases: duplicate anchors, soft deletes, maximum limits, PII scrubbing.

## 4. Frontend Sync Layer
- [ ] Extend `TherapyService`/`MemoryService` to call new endpoints when anchors or personalization change.
- [ ] Introduce a sync manager that batches writes, retries on failure, and flags dirty records for offline scenarios.
- [ ] On app launch (and after login), fetch server state and hydrate local stores (`ConversationMemory`, `PreferencesService`, `SessionRepository`).
- [ ] Ensure `_currentSessionId` and backend IDs stay aligned when offline entries are later synced.

## 5. Offline & Conflict Handling
- [ ] Decide merge strategy: client-wins, server-wins, or last-write-wins with timestamps; document rules per data type.
- [ ] Implement optimistic updates with rollback on failure for critical flows (e.g., anchor edits).
- [ ] Queue changes when offline; flush once network resumes (reuse existing `queue_service` if available or build new).
- [ ] Provide user feedback on sync status (snackbar/banner) and expose manual retry option.

## 6. Testing & Observability
- [ ] Write backend unit/integration tests (pytest) covering new models, services, and API contracts.
- [ ] Add Flutter integration/widget tests validating that anchors persist after app restart and that the preferred name is remembered.
- [ ] Instrument backend endpoints with structured logging and metrics (success/failure counts, latency).
- [ ] Add CI steps to run migrations in ephemeral DB and execute new test suites.
- [ ] Set up dashboards/alerts for sync failures or excessive retries.

## 7. Rollout & Backfill
- [ ] Deploy backend changes to staging; run smoke tests with latest client.
- [ ] Implement migration script to backfill existing local anchors (prompt users to sync once) if feasible.
- [ ] Coordinate mobile release: protect new API calls behind a feature flag until backend is stable.
- [ ] Monitor production logs for missing data or increased error rates; adjust retry thresholds as needed.
- [ ] Document the new persistence architecture in `Maya.md` and onboarding materials.

---

## Deliverables
1. Database migrations and models for personalized data.
2. FastAPI endpoints + services with tests.
3. Flutter sync layer with offline handling.
4. Automated tests and monitoring coverage.
5. Updated documentation for engineers and support.
