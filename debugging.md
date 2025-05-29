# App Stability and Configuration Fixes

This document outlines the steps to resolve critical issues identified in the AI Therapist application, including database errors, LLM configuration mismatches, and Firebase initialization warnings.

---

## Issue 1: SQLite PRAGMA Errors ([FRONTEND])

**Symptoms:**
- `DatabaseException(unknown error (code 0 SQLITE_OK[0]): Queries can be performed using SQLiteDatabase query or rawQuery methods only.) sql 'PRAGMA busy_timeout = 10000;'`
- `DatabaseException(unknown error (code 0 SQLITE_OK[0]): Queries can be performed using SQLiteDatabase query or rawQuery methods only.) sql 'PRAGMA journal_mode = WAL;'`

**Potential Cause:** Incorrect method of executing PRAGMA statements with the `sqflite` plugin in the Flutter app.

**Plan:**

1.  **Step 1.1: Review Database Initialization Code ([FRONTEND])**
    *   **Action:** Locate where `PRAGMA busy_timeout = 10000;` and `PRAGMA journal_mode = WAL;` are executed. This is likely in your `AppDatabase` class or a `DatabaseProvider` service within `ai_therapist_app/lib/services/` or `ai_therapist_app/lib/database/`.
    *   **File(s) to inspect:** `app_database.dart`, `database_provider.dart` (or similar).

2.  **Step 1.2: Modify PRAGMA Execution ([FRONTEND])**
    *   **Action:** Adjust how these PRAGMAs are set according to `sqflite` best practices.
        *   For `PRAGMA journal_mode = WAL;`: This is best enabled by setting `singleInstance: true` when calling `openDatabase`. If you are already doing that, `sqflite` might handle WAL mode enabling by default. Explicitly executing it via `db.execute()` might be problematic.
        *   For `PRAGMA busy_timeout = 10000;`: This PRAGMA can often be executed, but it should ideally be done within the `onConfigure` callback of the `openDatabase` method.
    *   **Files to modify:** `app_database.dart` or equivalent in the Flutter project.

3.  **Step 1.3: Test ([FRONTEND])**
    *   **Action:** Clean build and run the Flutter app on your device. Check the Flutter logs for the disappearance of these specific `DatabaseException` errors related to PRAGMAs.
    *   **Expected Outcome:** No PRAGMA-related `DatabaseException`s in Flutter logs.

---

## Issue 2: LLM Model ID Mismatch ([FRONTEND] & [BACKEND])

**Symptoms:**
- Frontend logs `LLM Model ID: meta-llama/llama-4-scout-17b-16e-instruct`.
- Backend has been (or is being) configured for a Google Gemini model (e.g., `gemini-1.5-flash-latest`).
- This mismatch likely contributes significantly to context loss and unexpected AI behavior.

**Goal:** Ensure frontend and backend are aligned on the LLM model being used, specifically targeting Gemini.

**Plan:**

1.  **Step 2.1: Confirm Backend LLM Configuration ([BACKEND])**
    *   **Action:** Double-check your deployed backend's environment variables on Cloud Run and your `ai_therapist_backend/app/core/llm_config.py` to ensure it's definitively configured to use the intended Gemini model (e.g., `gemini-1.5-flash-latest` or the specific Gemini model you want).
    *   **Verification:** Review Cloud Run service configuration and backend Python code.

2.  **Step 2.2: Frontend - Centralize and Correct LLM Configuration ([FRONTEND])**
    *   **Action:** Investigate `ai_therapist_app/lib/core/config/app_config.dart` (or your `ConfigService` equivalent) where `LLM Model ID: meta-llama/llama-4-scout-17b-16e-instruct` is being logged.
    *   **Change:** Modify this default/loaded value to the correct Gemini model ID that the backend is using (e.g., `gemini-1.5-flash-latest`). Ensure this configuration is reliably loaded and used by the Flutter app.
    *   **Files to inspect/modify:** `app_config.dart`, `config_service.dart` or where `.env` variables are loaded and processed for LLM settings in the Flutter project.

3.  **Step 2.3: Frontend - Review Model-Specific Logic ([FRONTEND] - Review/Minor Adjustment if any)**
    *   **Action:** Briefly review if any frontend logic *explicitly* formats data or expects responses in a Llama-specific way. The goal is for the backend to handle most model-specific adaptations, particularly for history. The frontend should primarily send its message list.
    *   **Verification:** Ensure the `model` field in API requests (if any) or history payloads aligns with Gemini, if the backend expects this.

4.  **Step 2.4: Test ([FRONTEND] & [BACKEND])**
    *   **Action:** After aligning frontend and backend on the Gemini model:
        1.  **Re-test the backend's `/sessions/{session_id}/chat_stream` endpoint directly** (using `curl` or Postman) to ensure it's working flawlessly with the Gemini model and the correct role mapping.
        2.  Run the Flutter app, initiate a session, and carefully observe:
            *   Frontend logs for the correct Gemini `LLM Model ID`.
            *   Backend logs for successful interaction with the Gemini API.
            *   The AI's responses for coherence and context retention.
    *   **Expected Outcome:** Frontend reports the correct Gemini model ID. Backend processes requests using Gemini. Noticeable improvement in conversation quality and context retention.

---

## Issue 3: Firebase Duplicate App Warning ([FRONTEND])

**Symptoms:**
- `[main.dart] Error during Firebase initialization: [core/duplicate-app] A Firebase App named "[DEFAULT]" already exists`

**Potential Cause:** `Firebase.initializeApp()` is being called more than once for the default Firebase app in the Flutter code.

**Plan:**

1.  **Step 3.1: Review Firebase Initialization Points ([FRONTEND])**
    *   **Action:** Search your entire Flutter codebase (especially `main.dart` and any service initialization logic) for all occurrences of `Firebase.initializeApp()`.
    *   **Tool:** Use your IDE's "Find in Files" feature within the `ai_therapist_app` directory.

2.  **Step 3.2: Ensure Singleton Initialization ([FRONTEND])**
    *   **Action:** Ensure `Firebase.initializeApp()` is called only once during the app's lifecycle, typically in `main()`. Remove or guard subsequent calls.
    *   **Files to modify:** `main.dart` and any other files in the Flutter project calling `Firebase.initializeApp()`.

3.  **Step 3.3: Test ([FRONTEND])**
    *   **Action:** Clean build and run the Flutter app. Check Flutter logs.
    *   **Expected Outcome:** The "[core/duplicate-app]" warning should disappear from Flutter logs.

---

## General Testing Strategy

*   **Incremental Testing:** After implementing the fix for each *major step* (e.g., after Step 1.2, Step 2.2, Step 3.2), clean build the app, run it, and check the logs for the specific issue you addressed.
*   **Full Session Test:** After addressing all issues, conduct a full therapy session in the app. Pay close attention to:
    *   Startup speed and lack of errors in logs.
    *   VAD behavior.
    *   TTS quality and timing.
    *   The AI's conversational ability, and specifically, **context retention** over several turns.
    *   Any crashes or unexpected behavior.
