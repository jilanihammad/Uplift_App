# Uplift — AI Wellness Companion

**A conversational AI companion for mental wellness support, built with FastAPI and Flutter.**

> ⚠️ **Disclaimer:** Uplift is a research prototype. It is not a medical device and is not intended as a substitute for professional mental health care. If you are in crisis, please contact the [988 Suicide & Crisis Lifeline](https://988lifeline.org/) or your local emergency services.

---

## The Problem

Over 150 million Americans live in federally designated mental health professional shortage areas. Average wait times for a first therapy appointment stretch to 48 days. Cost, stigma, and geographic barriers mean that millions of people who could benefit from support simply never access it.

Uplift doesn't try to replace therapists. It explores a harder question: **can a carefully designed AI companion provide meaningful emotional support in the gaps between professional care** — the 2 AM moments, the waiting-list weeks, the "I'm not sure this is bad enough to call someone" hesitations?

This is a domain where getting the product wrong has real consequences, which is exactly why it's worth building carefully.

---

## How It Works

Uplift pairs a named AI companion, **Maya**, with a real-time voice and text interface. Users can speak or type naturally; Maya responds with empathetic, context-aware conversation grounded in evidence-based wellness techniques.

A typical session:

1. **User speaks or types** → Flutter app captures input (with VAD-based voice detection)
2. **Backend transcribes & processes** → FastAPI routes through the active LLM provider with Maya's persona and safety guardrails
3. **Maya responds** → Streamed text + real-time TTS audio, targeting < 500ms to first byte
4. **Context persists** → Session history, user anchors, and mood patterns build continuity across conversations

---

## Product Decisions & Tradeoffs

These are the choices that shaped the product — and the reasoning behind them:

### Why a named persona ("Maya") instead of a generic chatbot?
Mental wellness conversations require trust. Research on therapeutic alliance shows that perceived personality and consistency drive engagement. Maya has a defined tone (warm, non-judgmental, gently curious), consistent boundaries (she won't diagnose), and a name users can relate to. A generic "AI Assistant" doesn't earn the same trust in sensitive conversations.

### Why multi-LLM architecture instead of a single provider?
The backend routes across **OpenAI, Anthropic Claude, Google Gemini, Groq, and others** through a unified LLM manager. This wasn't over-engineering — it was risk management. In a wellness context, an outage isn't just inconvenient; it's a broken promise to someone who reached out for support. Provider diversity enables automatic failover with circuit breakers and lets us evaluate which models produce the most appropriate responses for sensitive topics.

### Why Flutter for mobile instead of React Native or web-only?
Voice is the primary interaction mode, and voice UX demands tight platform integration: low-latency audio capture, VAD (voice activity detection), noise suppression via RNNoise, and streaming TTS playback. Flutter's compiled performance and direct platform channel access gave us sub-100ms voice detection latency. A web-only approach would have sacrificed the intimacy of a native mobile experience in a domain where UX intimacy matters.

### How do you handle safety and escalation?
Maya is explicitly bounded: she does not diagnose, prescribe, or roleplay as a licensed professional. The system includes input safety classification, response guardrails that redirect crisis language toward professional resources, and rate limiting to prevent compulsive over-use. The persona design itself is a safety mechanism — Maya's framing as a "companion" (not therapist) sets appropriate user expectations from the first interaction.

### Why PostgreSQL over NoSQL?
Wellness data has relational structure: users have sessions, sessions have messages, messages have mood annotations, users have anchors and summaries that reference sessions. PostgreSQL's ACID guarantees matter when you're persisting someone's emotional history — partial writes or eventual consistency aren't acceptable for data this personal. Soft-delete semantics ensure nothing is irretrievably lost.

---

## Technical Architecture

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│   Flutter Mobile     │  REST   │       FastAPI Backend             │
│                      │◄──────►│                                  │
│  • BLoC state mgmt   │   WS    │  • Unified LLM Manager           │
│  • Voice pipeline    │◄──────►│    (OpenAI / Claude / Gemini /   │
│  • RNNoise VAD       │         │     Groq / DeepSeek / Azure)     │
│  • Streaming TTS     │         │  • Streaming audio pipeline      │
│  • SQLite local cache│         │  • Circuit breakers + failover   │
│  • Firebase Auth     │         │  • Rate limiting + security MW   │
└─────────────────────┘         │  • PostgreSQL (Cloud SQL)        │
                                 │  • Firebase JWT validation       │
                                 └──────────────────────────────────┘
```

**Backend:** Python/FastAPI with SQLAlchemy ORM, Alembic migrations, WebSocket streaming for real-time voice, and modular provider architecture with tenacity retry policies.

**Frontend:** Flutter (Android, iOS, desktop) with GetIt DI, GoRouter navigation, and a hybrid voice pipeline featuring VAD, noise suppression, and adaptive TTS format selection (MP3/Opus/WAV based on network conditions).

**Infrastructure:** Google Cloud Run, Cloud SQL (PostgreSQL), Firebase Auth + App Check (Play Integrity), GCP Secret Manager.

---

## Security

A dedicated security review identified and addressed **36 findings** across the stack:

- **Authentication:** Firebase JWT validation on all API endpoints; token storage migrated from SharedPreferences to `FlutterSecureStorage`
- **Network:** HTTPS-only enforcement in release builds via Android network security config; debug localhost access scoped to debug builds only
- **Data Protection:** PII scrubbing in logs (`preview_text()` truncation at INFO level); header redaction for auth tokens; `android:allowBackup="false"` prevents OS-level therapy data backup
- **API Hardening:** Rate limiting (30 req/min per user), security headers (XSS, CSP, clickjacking), origin validation on WebSocket connections
- **App Integrity:** Firebase App Check with Play Integrity for release builds; debug provider scoped to `debugRuntimeOnly`
- **Secrets:** All API keys managed via GCP Secret Manager; `.env` files excluded from production artifacts

---

## By the Numbers

| Metric | Value |
|---|---|
| Commits | 299+ |
| Test files | 111+ (pytest + Flutter unit/widget/integration) |
| LLM providers supported | 6 (OpenAI, Anthropic, Google, Groq, Grok, DeepSeek) |
| Security findings addressed | 36 |
| Target TTS first-byte latency | < 500ms |
| Voice detection latency | < 100ms |

---

## Running Locally

```bash
# Backend
cd ai_therapist_backend
pip install -r requirements.txt
cp .env.example .env  # Add provider API keys
python dev_server.py

# Frontend
cd ai_therapist_app
flutter pub get
flutter run
```

See [backend docs](ai_therapist_backend/README.md) and [frontend docs](ai_therapist_app/README.md) for detailed setup.

---

## Status

Active development. This is a solo-built research project exploring responsible AI design in a high-stakes domain — not a production clinical tool.

---

## License

MIT
