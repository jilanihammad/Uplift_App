
# AI Therapist Backend Codebase Documentation

This document provides an overview of the files and directories in the `ai_therapist_backend` directory, which constitutes the Python FastAPI backend of the Uplift application.

## Root Directory

- **alembic.ini**: Configuration file for Alembic, a database migration tool for SQLAlchemy.
- **docker-compose.yml**: Defines the services, networks, and volumes for a multi-container Docker application.
- **dockerfile, dockerfile.bak, Dockerfile.cloudrun, Dockerfile.simple**: Different Docker configurations for building the backend container for various environments (local, Cloud Run, etc.).
- **main.py**: The main entry point for the FastAPI application when run directly.
- **requirements.txt**: Lists the Python dependencies for the project.
- **...and various scripts (.ps1, .py, .yaml)**: Scripts for deployment, testing, and utility tasks.

## `app` Directory

This is the main directory containing the application's source code.

### `app/api`

This module contains the API routing logic.

- **`api/api_v1/api.py`**: The main API router for version 1. It aggregates all the specific endpoint routers (like AI, voice, subscriptions) into a single router that is included in the main FastAPI app.
- **`api/api_v1/endpoints/`**: This directory holds the individual files defining the API endpoints for different functionalities.
    - **`ai.py`**: Defines endpoints related to AI operations, such as generating text responses (`/generate`), checking service status (`/status`), and a WebSocket endpoint for real-time chat (`/ws/chat`). It uses the `llm_manager` to interact with AI models.
    - **`voice.py`**: Defines endpoints for voice-related services, including Text-to-Speech (`/synthesize`) and Speech-to-Text (`/transcribe`). It also contains a sophisticated WebSocket endpoint (`/ws/tts/speech`) for real-time, low-latency streaming of TTS audio, complete with security and rate-limiting features.
    - **`subscriptions.py`**: Handles webhooks from Stripe to manage user subscriptions, processing events like payments, cancellations, and checkouts.

### `app/core`

This module contains the core configuration, security, and setup logic for the application.

- **`config.py`**: A crucial file that centralizes all application settings using Pydantic. It loads configuration from environment variables and `.env` files, adapting settings for different environments (local, production). It manages database connections, CORS policies, and API keys.
- **`environment.py`**: Defines and manages the application's current running environment (e.g., local, development, production).
- **`llm_config.py`**: A key configuration file that defines and manages all LLM, TTS, and Transcription models from various providers (OpenAI, Groq, Anthropic). It allows for easy switching of the active provider for each service.
- **`logger.py`**: Sets up structured, environment-aware logging. It uses Google Cloud Logging in production and a more readable console logger for development.
- **`security.py`**: Provides essential security utilities for password hashing/verification and JWT access token creation.
- **`rate_limiter.py` & `security_middleware.py`**: FastAPI middleware for enforcing request rate limits and adding security headers (like CSP, X-XSS-Protection) to all responses.

### `app/db`

This module manages the database connection and models.

- **`session.py`**: Configures the SQLAlchemy engine and provides the `get_db` dependency for managing database sessions in API endpoints.
- **`base.py` & `base_class.py`**: Defines the declarative base for SQLAlchemy models, allowing them to be automatically discovered by Alembic for migrations.

### `app/models`

Contains the SQLAlchemy ORM models that define the structure of the database tables (e.g., `user.py`, `session.py`, `message.py`).

### `app/schemas`

Contains the Pydantic models (schemas) used for data validation, serialization, and defining the shape of API requests and responses.

### `app/crud`

Stands for Create, Read, Update, Delete. This module contains functions that interact directly with the database to perform these operations on the data models (e.g., `crud/session.py` has functions to create, get, and update sessions).

### `app/services`

This module contains the business logic of the application, encapsulated into various services.

- **`llm_manager.py`**: **A core service.** This acts as a unified interface for all AI model interactions. It abstracts the specific provider (OpenAI, Groq, etc.) being used for LLM, TTS, or transcription, routing requests to the appropriate service based on the central `llm_config.py`.
- **`streaming_pipeline.py`**: Implements an advanced, high-performance asynchronous pipeline specifically for real-time TTS streaming. It manages backpressure, flow control, and jitter buffers to ensure a smooth, low-latency audio stream to the client.
- **`voice_service.py`**: Handles the logic for voice synthesis (TTS), using the `llm_manager` to generate the audio data and saving it to a file.
- **`transcription_service.py`**: Handles audio transcription, using the `llm_manager` to convert speech to text.
- **`rate_limit_coordinator.py`**: A sophisticated service to coordinate and manage rate limits across different components, ensuring fair resource use and preventing API limit errors.

### `app/utils`

Contains utility functions and classes.

- **`text_processor.py`**: A smart text processor designed for streaming TTS. It intelligently breaks text into natural-sounding chunks by detecting sentence boundaries, abbreviations, and pause tokens, which is crucial for achieving low-latency, natural-sounding speech.
