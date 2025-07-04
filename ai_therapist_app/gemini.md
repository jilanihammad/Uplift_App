
# Gemini Codebase Analysis: Uplift AI Therapist App

## High-Level Summary

This is a Flutter-based mobile application providing AI-powered voice therapy sessions. The app leverages Firebase for backend services, including authentication, data storage (Firestore), and push notifications. State management is handled using BLoC, and the architecture appears to follow a feature-driven structure with a separation of concerns between UI, business logic, and data layers.

**Key Technologies:**

*   **Frontend:** Flutter
*   **Backend:** Firebase (Auth, Firestore, Storage, Messaging)
*   **State Management:** BLoC
*   **Routing:** go_router
*   **HTTP Client:** Dio
*   **Local Storage:** sqflite, shared_preferences
*   **Audio:** record, just_audio, flutter_tts, rnnoise_flutter (for noise suppression)

**Core Features:**

*   User authentication (email/password, Google Sign-In)
*   Voice-based therapy sessions with an AI therapist
*   Session history and progress tracking
*   User profile management
*   Customizable therapist styles
*   Dark mode and theme customization

## Architectural Overview

The application is structured into several layers, each with a distinct responsibility:

*   **`lib/screens` (Presentation Layer):** Contains the UI for each screen of the app.
*   **`lib/blocs` (State Management):** Manages the application's state using the BLoC pattern.
*   **`lib/services` (Business Logic):** Encapsulates the core business logic, such as therapy session management, audio processing, and API interactions.
*   **`lib/data` (Data Layer):** Handles data operations, including communication with local and remote data sources.
*   **`lib/models` (Data Models):** Defines the data structures used throughout the application.
*   **`lib/utils` (Utilities):** Provides common utility functions, such as logging, error handling, and date formatting.
*   **`lib/di` (Dependency Injection):** Manages the app's dependencies using the `get_it` package.

## File-by-File Analysis

### `lib/main.dart`

*   **Purpose:** The entry point of the application.
*   **Responsibilities:**
    *   Initializes Flutter bindings and Firebase services.
    *   Sets up the service locator for dependency injection.
    *   Configures global error handling and logging.
    *   Initializes the main `AiTherapistApp` widget.
    *   Sets up the `AuthBloc` and `ThemeService`.

### `lib/blocs/`

*   **`auth/`:** Handles user authentication state (e.g., `AuthBloc`, `AuthEvents`, `AuthState`).
*   **`voice_session_bloc.dart`:** Manages the state of a voice therapy session, including recording, processing, and displaying messages.

### `lib/services/`

*   **`auth_service.dart`:** Manages user authentication with Firebase.
*   **`therapy_service.dart`:** Orchestrates the entire therapy session, coordinating between the UI, voice service, and backend.
*   **`voice_service.dart`:** Handles audio recording, noise suppression (using `rnnoise_flutter`), and text-to-speech (TTS) synthesis.
*   **`firebase_service.dart`:** Provides a wrapper for Firebase APIs.
*   **`memory_service.dart`:** Manages the conversation history and user preferences.
*   **`user_profile_service.dart`:** Handles user profile data.

### `lib/data/`

*   **`datasources/`:**
    *   **`local/`:** Manages the local SQLite database (`app_database.dart`).
    *   **`remote/`:** Contains the API client for communicating with backend services (`api_client.dart`).
*   **`repositories/`:** Implements the repository pattern to abstract data sources from the business logic.

### `lib/screens/`

*   **`splash_screen.dart`:** The initial screen shown while the app is loading.
*   **`login_screen.dart`, `register_screen.dart`:** User authentication screens.
*   **`home_screen.dart`:** The main screen after login, providing access to therapy sessions and other features.
*   **`chat_screen.dart`:** The UI for the voice therapy session.
*   **`profile_screen.dart`:** Allows users to view and edit their profile.
*   **`settings_screen.dart`:** Provides options for customizing the app, such as theme and therapist style.

## Potential Refactoring & New Features

### Refactoring

*   **State Management:** While BLoC is used, some UI components might be tightly coupled to services. Consider a stricter separation of concerns by ensuring all UI interactions go through a BLoC.
*   **Error Handling:** Implement a more robust and user-friendly error handling strategy, providing clear feedback to the user in case of network failures or other issues.
*   **Code Duplication:** Identify and refactor duplicated code, especially in the UI and business logic layers.
*   **Testing:** Increase test coverage, particularly for the business logic and state management layers.

### New Features

*   **Journaling:** Add a feature for users to write down their thoughts and feelings.
*   **Mood Tracking:** Allow users to track their mood over time and visualize the trends.
*   **Personalized Exercises:** Provide users with personalized exercises and coping mechanisms based on their therapy sessions.
*   **Offline Mode:** Enhance the offline capabilities of the app, allowing users to access some features without an internet connection.
*   **Multi-language Support:** Add support for multiple languages to make the app accessible to a wider audience.
*   **Web Dashboard:** Create a web-based dashboard for users to view their progress and session history.
