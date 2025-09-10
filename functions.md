# Migration Plan: Cloud Functions (Gen2) + Cloud Run Hybrid

This document describes how to migrate non‑streaming backend endpoints from Cloud Run to Google Cloud Functions (Gen2) while retaining streaming/real‑time endpoints on Cloud Run. The goal is to reduce baseline costs by scaling most compute to zero, while preserving capabilities (WebSockets/streaming, low-latency audio) that Cloud Functions does not support.

- Target project: AI Therapist App
- Frontend: Flutter (BLoC hybrid)
- Backend: FastAPI + SQLAlchemy + Unified LLM Manager (Python)
- Database: Cloud SQL (PostgreSQL)
- Current hosting: Cloud Run
- Target: Hybrid — Cloud Functions (non‑streaming) + Cloud Run (streaming)

---

## High-Level Architecture (Target)

- API Gateway (single public domain)
  - Routes non‑streaming requests to Cloud Functions (Gen2, Python 3.11)
  - Routes streaming/SSE/WebSocket endpoints to Cloud Run
- Cloud Functions (Gen2)
  - Endpoints: `GET /health`, `POST /ai/response` (non‑streaming), `POST /voice/transcribe`, and admin/CRUD
  - Cold start aware; scales to zero; smaller baseline cost
- Cloud Run (min-instances=0)
  - Endpoints: `POST /voice/synthesize` (TTS streaming) and any real-time/streaming routes
- Cloud SQL via Cloud SQL Python Connector (through Serverless VPC Access)
- Secret Manager for all secrets; IAM service-perimeter enforcement

---

## Ground Rules and Constraints

- Do not move streaming endpoints (TTS streaming, WebSockets/SSE) to Functions; keep on Cloud Run
- Keep resources in the same region to avoid cross‑region egress and latency
- Prefer API Gateway for auth/CORS/quota; Functions/Run can require IAM if fully behind Gateway
- Use least‑privilege service accounts; never embed secrets in code or images

---

## Migration Checklist (Progress Tracker)

- [ ] Inventory and classify existing FastAPI routes by streaming vs non‑streaming
- [ ] Create shared backend package used by both FastAPI app and Functions
- [ ] Implement Cloud Functions wrappers for non‑streaming endpoints
- [ ] Configure VPC connector and Cloud SQL connector for Functions
- [ ] Create API Gateway config to route to Functions and Cloud Run
- [ ] Set up secrets in Secret Manager and bind IAM
- [ ] CI/CD: Cloud Build deploys Functions, Cloud Run, and API Gateway; runs DB migrations
- [ ] Update Flutter `API_BASE_URL` to Gateway domain (stage, then prod)
- [ ] Validate latency/SLOs and tune cold‑start mitigations
- [ ] Cut over traffic and decommission old non‑streaming routes on Cloud Run

---

## Phase 1 — Endpoint Inventory

1. Identify all FastAPI routes in `ai_therapist_backend` and classify:
   - To Cloud Functions: `GET /health`, `POST /ai/response` (non‑streaming), `POST /voice/transcribe`, admin/CRUD
   - Stay on Cloud Run: `POST /voice/synthesize` (streaming) and any WebSocket/SSE
2. Confirm that any route using chunked responses or long-lived connections remains on Cloud Run.

Suggested local command (ripgrep) to enumerate routes:
```bash
rg --line-number "@app\.(get|post|put|delete|patch)\(" ai_therapist_backend
```

Deliverable: a short table mapping route → target platform.

---

## Phase 2 — Shared Backend Package

Goal: Reuse core logic across FastAPI (Cloud Run) and Functions (Gen2).

Proposed structure (new subpackage under backend):
```
ai_therapist_backend/
  shared/
    __init__.py
    auth/
      __init__.py
      jwt.py                 # JWT/Firebase verification helpers
    db/
      __init__.py
      session.py             # SQLAlchemy engine/session via Cloud SQL Connector
    llm_manager/
      __init__.py
      manager.py             # Provider selection, response APIs
    services/
      __init__.py
      therapy.py             # Non-streaming response helpers
      audio.py               # Common transcription utilities
```

Key actions:
- Extract LLM orchestration into `shared/llm_manager/manager.py`
- Centralize database engine/session creation in `shared/db/session.py`
- Move reusable business logic (transcription, AI response assembly) into `shared/services/`
- Add lightweight auth helpers for JWT/Firebase in `shared/auth/jwt.py`

Example: `shared/db/session.py` (Cloud SQL connector)
```python
import os
import sqlalchemy
from google.cloud.sql.connector import Connector

_connector: Connector | None = None


def _get_connector() -> Connector:
    global _connector
    if _connector is None:
        _connector = Connector()
    return _connector


def create_engine() -> sqlalchemy.Engine:
    instance = os.environ["INSTANCE_CONNECTION_NAME"]  # "project:region:instance"
    db_user = os.environ["DB_USER"]
    db_pass = os.environ["DB_PASS"]
    db_name = os.environ["DB_NAME"]

    def getconn():
        return _get_connector().connect(
            instance_connection_string=instance,
            driver="pg8000",
            user=db_user,
            password=db_pass,
            db=db_name,
        )

    return sqlalchemy.create_engine(
        "postgresql+pg8000://",
        creator=getconn,
        pool_pre_ping=True,
    )
```

Dependencies (ensure in both environments): `google-cloud-sql-connector`, `sqlalchemy`, `pg8000`.

---

## Phase 3 — Cloud Functions (Gen2) Wrappers

Create a new top‑level `functions/` directory for Functions (one folder per function for clarity):
```
functions/
  requirements.txt
  ai_response/
    main.py
  transcribe/
    main.py
  health/
    main.py
```

`functions/requirements.txt` (example):
```text
functions-framework==3.*
google-cloud-sql-connector==1.*
sqlalchemy==2.*
pg8000==1.*
firebase-admin==6.*
python-dotenv==1.*
# If shared package imports other libs, include them here too
```

Example: `functions/ai_response/main.py` (HTTP function with CORS + JWT)
```python
import json
import functions_framework
from flask import jsonify

# Import shared logic from backend package
from ai_therapist_backend.shared.llm_manager.manager import LlmManager
from ai_therapist_backend.shared.auth.jwt import verify_jwt

llm = LlmManager.from_env()

@functions_framework.http
def ai_response(request):
    # CORS preflight
    if request.method == "OPTIONS":
        resp = jsonify({})
        resp.status_code = 204
        _apply_cors(resp)
        return resp

    _apply_cors_headers = True

    # Auth
    auth_header = request.headers.get("Authorization")
    verify_jwt(auth_header)

    # Parse
    data = request.get_json(silent=True) or {}
    user_message = data.get("message", "")

    # Non-streaming LLM response
    reply_text = llm.respond(user_message)

    resp = jsonify({"reply": reply_text})
    if _apply_cors_headers:
        _apply_cors(resp)
    return resp


def _apply_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
```

Example: `functions/transcribe/main.py`
```python
import base64
import json
import functions_framework
from flask import jsonify
from ai_therapist_backend.shared.auth.jwt import verify_jwt
from ai_therapist_backend.shared.services.audio import transcribe_audio

@functions_framework.http
def transcribe(request):
    if request.method == "OPTIONS":
        resp = jsonify({})
        resp.status_code = 204
        _apply_cors(resp)
        return resp

    verify_jwt(request.headers.get("Authorization"))

    body = request.get_json(silent=True) or {}
    audio_b64 = body.get("audio_data")
    audio_format = body.get("audio_format", "mp3")

    if not audio_b64:
        return jsonify({"error": "audio_data required"}), 400

    audio_bytes = base64.b64decode(audio_b64)
    result = transcribe_audio(audio_bytes, audio_format)

    resp = jsonify(result)
    _apply_cors(resp)
    return resp


def _apply_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
```

Example: `functions/health/main.py`
```python
import functions_framework
from flask import jsonify

@functions_framework.http
def health(request):
    return jsonify({"ok": True})
```

Notes:
- Import from `ai_therapist_backend.shared.*` so business logic is not duplicated
- Keep heavy clients (LLM, db engines) at module import time to amortize cold starts

---

## Phase 4 — Networking and Database

1. Create a Serverless VPC Access connector (one per region):
```bash
gcloud compute networks vpc-access connectors create serverless-us-central1 \
  --region=us-central1 \
  --network=default \
  --range=10.8.0.0/28
```

2. Use Cloud SQL Python Connector in both Cloud Run and Functions; set env vars:
- `INSTANCE_CONNECTION_NAME=project:region:instance`
- `DB_USER`, `DB_PASS`, `DB_NAME`

3. Functions deploy flags will attach the VPC connector and egress settings.

---

## Phase 5 — Secrets and IAM

Secrets to store in Secret Manager:
- `OPENAI_API_KEY`, `GROQ_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `AZURE_OPENAI_*`, `DEEPSEEK_API_KEY`
- `DB_USER`, `DB_PASS` (or use Cloud SQL IAM DB Authn if preferred)
- Any third‑party service keys used by `shared/*`

Service Accounts:
- `functions-invoker@PROJECT.iam.gserviceaccount.com` (invoked by API Gateway)
- `backend-runtime@PROJECT.iam.gserviceaccount.com` for Functions/Run execution

Grant roles:
- Cloud SQL Client
- Secret Manager Secret Accessor (specific secrets only)
- Logging Writer, Error Reporting Writer
- Cloud Run Invoker (to API Gateway SA) and Cloud Functions Invoker if requiring IAM

Optional: Bind secrets at deploy time via `--set-secrets`.

---

## Phase 6 — API Gateway Routing

OpenAPI spec `apigw/openapi.yaml` (example):
```yaml
openapi: 3.0.0
info:
  title: ai-therapist-api
  version: 1.0.0
servers:
  - url: https://api.your-domain.com
paths:
  /health:
    get:
      x-google-backend:
        address: https://REGION-PROJECT.cloudfunctions.net/health
  /ai/response:
    post:
      x-google-backend:
        address: https://REGION-PROJECT.cloudfunctions.net/ai_response
  /voice/transcribe:
    post:
      x-google-backend:
        address: https://REGION-PROJECT.cloudfunctions.net/transcribe
  /voice/synthesize:
    post:
      x-google-backend:
        address: https://CLOUD_RUN_SERVICE-REGION.a.run.app
components:
  securitySchemes:
    firebase:
      type: oauth2
      flows:
        implicit: {}
security:
  - firebase: []
```

Deploy API and Gateway:
```bash
gcloud api-gateway apis create ai-therapist-api

gcloud api-gateway api-configs create ai-therapist-config \
  --api=ai-therapist-api \
  --openapi-spec=apigw/openapi.yaml \
  --backend-auth-service-account=functions-invoker@PROJECT.iam.gserviceaccount.com

gcloud api-gateway gateways create ai-therapist-gw \
  --api=ai-therapist-api \
  --api-config=ai-therapist-config \
  --location=us-central1
```

Lock down backends (optional but recommended):
- Cloud Run: set ingress to internal and lb‑only; allow only API Gateway SA to invoke
- Cloud Functions: require IAM if entirely behind Gateway and remove public access

---

## Phase 7 — Deployment Commands (Manual)

Deploy Functions (Gen2):
```bash
# Health
gcloud functions deploy health \
  --gen2 --region=us-central1 --runtime=python311 \
  --source=functions/health \
  --entry-point=health --trigger-http --allow-unauthenticated \
  --timeout=60s --memory=256MB

# AI response
gcloud functions deploy ai_response \
  --gen2 --region=us-central1 --runtime=python311 \
  --source=functions/ai_response \
  --entry-point=ai_response --trigger-http --allow-unauthenticated \
  --timeout=300s --memory=1024MB \
  --set-env-vars="INSTANCE_CONNECTION_NAME=project:region:instance,DB_USER=...,DB_PASS=...,DB_NAME=..." \
  --vpc-connector=serverless-us-central1 --egress-settings=all

# Transcribe
gcloud functions deploy transcribe \
  --gen2 --region=us-central1 --runtime=python311 \
  --source=functions/transcribe \
  --entry-point=transcribe --trigger-http --allow-unauthenticated \
  --timeout=300s --memory=1024MB \
  --set-env-vars="INSTANCE_CONNECTION_NAME=project:region:instance,DB_USER=...,DB_PASS=...,DB_NAME=..." \
  --vpc-connector=serverless-us-central1 --egress-settings=all
```

Update Cloud Run (streaming service):
```bash
gcloud run services update voice-streaming \
  --region=us-central1 --min-instances=0 --cpu-boost --concurrency=80
```

Update API Gateway to point to new backends (recreate config + rollout gateway).

---

## Phase 8 — CI/CD (Cloud Build)

Create `cloudbuild.yaml` at repo root (example):
```yaml
steps:
  - name: gcr.io/cloud-builders/gcloud
    id: Install Python deps for tests
    entrypoint: bash
    args: ["-lc", "pip install -r ai_therapist_backend/requirements-dev.txt"]

  - name: gcr.io/cloud-builders/gcloud
    id: Run backend tests
    entrypoint: bash
    args: ["-lc", "pytest -q"]

  # Build and deploy Cloud Run (streaming)
  - name: gcr.io/cloud-builders/docker
    id: Build backend image
    args: ["build", "-t", "gcr.io/$PROJECT_ID/ai-therapist-backend:$COMMIT_SHA", "."]

  - name: gcr.io/cloud-builders/gcloud
    id: Deploy Cloud Run
    args: ["run", "deploy", "voice-streaming", "--image", "gcr.io/$PROJECT_ID/ai-therapist-backend:$COMMIT_SHA", "--region", "us-central1", "--platform", "managed"]

  # Deploy functions
  - name: gcr.io/cloud-builders/gcloud
    id: Deploy function: health
    args:
      ["functions", "deploy", "health", "--gen2", "--region", "us-central1", "--runtime", "python311",
       "--source", "functions/health", "--entry-point", "health", "--trigger-http", "--allow-unauthenticated",
       "--timeout", "60s", "--memory", "256MB"]

  - name: gcr.io/cloud-builders/gcloud
    id: Deploy function: ai_response
    args:
      ["functions", "deploy", "ai_response", "--gen2", "--region", "us-central1", "--runtime", "python311",
       "--source", "functions/ai_response", "--entry-point", "ai_response", "--trigger-http", "--allow-unauthenticated",
       "--timeout", "300s", "--memory", "1024MB",
       "--set-env-vars", "INSTANCE_CONNECTION_NAME=${_INSTANCE_CONNECTION_NAME},DB_USER=${_DB_USER},DB_PASS=${_DB_PASS},DB_NAME=${_DB_NAME}",
       "--vpc-connector", "serverless-us-central1", "--egress-settings", "all"]

  - name: gcr.io/cloud-builders/gcloud
    id: Deploy function: transcribe
    args:
      ["functions", "deploy", "transcribe", "--gen2", "--region", "us-central1", "--runtime", "python311",
       "--source", "functions/transcribe", "--entry-point", "transcribe", "--trigger-http", "--allow-unauthenticated",
       "--timeout", "300s", "--memory", "1024MB",
       "--set-env-vars", "INSTANCE_CONNECTION_NAME=${_INSTANCE_CONNECTION_NAME},DB_USER=${_DB_USER},DB_PASS=${_DB_PASS},DB_NAME=${_DB_NAME}",
       "--vpc-connector", "serverless-us-central1", "--egress-settings", "all"]

  # Deploy API Gateway config
  - name: gcr.io/cloud-builders/gcloud
    id: Update API Gateway config
    entrypoint: bash
    args:
      - -lc
      - |
        gcloud api-gateway api-configs create ai-therapist-config-$COMMIT_SHA \
          --api=ai-therapist-api \
          --openapi-spec=apigw/openapi.yaml \
          --backend-auth-service-account=functions-invoker@${PROJECT_ID}.iam.gserviceaccount.com
        gcloud api-gateway gateways update ai-therapist-gw \
          --api=ai-therapist-api \
          --api-config=ai-therapist-config-$COMMIT_SHA \
          --location=us-central1

  # Optional: run Alembic migrations via Cloud Run Job
  - name: gcr.io/cloud-builders/gcloud
    id: Run DB migrations
    entrypoint: bash
    args:
      - -lc
      - |
        gcloud run jobs execute backend-migrations --region us-central1 || \
        gcloud run jobs create backend-migrations \
          --image gcr.io/$PROJECT_ID/ai-therapist-backend:$COMMIT_SHA \
          --region us-central1 \
          --command "bash" \
          --args "-lc,alembic upgrade head" && \
        gcloud run jobs execute backend-migrations --region us-central1

substitutions:
  _INSTANCE_CONNECTION_NAME: "project:us-central1:instance"
  _DB_USER: "appuser"
  _DB_PASS: "changeme"
  _DB_NAME: "therapist"
```

Grant Cloud Build service account the necessary roles (Cloud Functions Developer, Cloud Run Admin, API Gateway Admin, Secret Manager Accessor for CI secrets, Cloud SQL Client for jobs).

---

## Phase 9 — Client Updates (Flutter)

1. Update `API_BASE_URL` to the API Gateway domain for staging first:
```bash
flutter run --dart-define=API_BASE_URL=https://api-staging.your-domain.com
```
2. Verify CORS, auth headers, and request formats are unchanged
3. Once validated, update production builds to the production Gateway domain

---

## Phase 10 — Observability & SLOs

- Logging: Cloud Logging with structured logs in both Functions and Cloud Run
- Metrics: Request count, latency (p50/p95), error ratios; set alerts on p95 latency and 5xx rates
- Dashboards: Create a unified dashboard across Functions and Run
- Tracing: Enable Cloud Trace (optional) for cross‑service spans via OpenTelemetry

Target performance:
- AI response p50 latency: < 600ms (post‑cold‑start) for short prompts
- Transcribe p50 end‑to‑end: < 1.5s for small clips
- Streaming TTS first byte: < 500ms (remains on Cloud Run)

Cold‑start mitigation options:
- Keep heavy imports at module scope (clients initialized once)
- Optional Cloud Scheduler warm‑up pings for critical functions
- Tune memory upward slightly if starts are sluggish (faster cold starts)

---

## Phase 11 — Security Hardening

- API Gateway performs JWT validation; Functions and Run require IAM invoker from Gateway SA
- Use Secret Manager; do not set raw secrets as env vars unless via `--set-secrets`
- Set Cloud Run ingress to internal and lb‑only; disable unauthenticated if behind Gateway
- Minimize OAuth scopes and IAM roles for each service account
- Enable CMEK (optional) for Cloud SQL and logs per compliance needs

---

## Phase 12 — Rollout, Validation, and Cutover

1. Stage deployment:
   - Deploy Functions and update Gateway in staging
   - Update Flutter staging `API_BASE_URL`
   - Smoke tests via curl/postman and Flutter integration tests
2. Canary:
   - Temporarily route a small cohort (or internal testers) to Gateway
   - Monitor logs/latency/errors
3. Cutover:
   - Point production Gateway to Functions for non‑streaming routes
   - Remove public access from old Cloud Run non‑streaming handlers
4. Decommission:
   - Delete unused endpoints on Cloud Run after a stabilization period

Validation commands:
```bash
# Health
curl -i https://api.your-domain.com/health

# AI response
curl -i -X POST https://api.your-domain.com/ai/response \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <JWT>" \
  -d '{"message":"Hello"}'

# Transcription
curl -i -X POST https://api.your-domain.com/voice/transcribe \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <JWT>" \
  -d '{"audio_data":"<base64>","audio_format":"mp3"}'

# Streaming TTS (remains Cloud Run)
curl -i -X POST https://api.your-domain.com/voice/synthesize \
  -H "Content-Type: application/json" \
  -d '{"text":"Test TTS"}'
```

---

## Phase 13 — Cost & Limits Tuning

- Cloud Functions
  - Set `--max-instances` to prevent runaway scale and control spend
  - Right‑size memory to balance cold‑start speed vs cost
  - Timeouts aligned with workload (e.g., 60–300s)
- Cloud Run
  - `--min-instances=0` to scale to zero; increase only if SLOs need it
  - High concurrency for streaming endpoints if CPU‑bound is low
- Networking
  - Co‑locate in a single region; avoid egress
  - Use VPC connector only when needed (Cloud SQL access)

---

## Phase 14 — Backout Plan

- If latency or errors regress, switch API Gateway routes back to Cloud Run for impacted paths
- Keep existing Cloud Run non‑streaming handlers for one release as a safety net
- Rollback is a Gateway config update; no client changes required

---

## Appendix A — IAM Matrix (Indicative)

- API Gateway SA → Cloud Functions Invoker, Cloud Run Invoker
- Functions/Run runtime SA → Cloud SQL Client, Secret Manager Accessor (scoped), Logging Writer, Error Reporting Writer
- Cloud Build SA → Functions Developer, Run Admin, API Gateway Admin, Service Account User, Secret Manager Accessor (CI secrets), Cloud SQL Client (for jobs)

---

## Appendix B — Local Dev

- Continue local backend dev via FastAPI dev server:
```bash
cd ai_therapist_backend
python dev_server.py
```
- Functions local testing (optional):
```bash
pip install -r functions/requirements.txt
functions-framework --target=ai_response --source=functions/ai_response/main.py --port=8081
```

---

## Appendix C — Open Questions / Decisions

- JWT verification location: API Gateway vs function edge (document the final choice)
- Transcription duration limits on Functions; consider async offload via Cloud Tasks + Pub/Sub for long files
- DB auth method: password vs IAM DB Authn
- Whether to group multiple endpoints into a single multi‑route function (fewer functions) or keep one‑per‑endpoint (simpler blast radius)

---

## Final Deliverables

- `ai_therapist_backend/shared/*` with DB, auth, LLM, and services modules
- `functions/*` with HTTP entrypoints and requirements
- `apigw/openapi.yaml` routing config
- `cloudbuild.yaml` for CI/CD
- Deployed Cloud Functions and updated API Gateway
- Updated Flutter `API_BASE_URL` to Gateway domain
