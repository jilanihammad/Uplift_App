
# AI Therapist App Codebase Documentation

This document provides an overview of the files and directories in the `ai_therapist_app` directory, which constitutes the Flutter frontend of the Uplift application.

## Root Directory

- **.gitignore**: Specifies intentionally untracked files to be ignored by Git.
- **.metadata**: A file created by Flutter to track project properties.
- **analysis_options.yaml**: Configures static analysis options for the Dart analyzer.
- **build_...ps1**: PowerShell scripts for building the application for different environments (debug, release, cloud).
- **CLAUDE.md**: Documentation related to the Claude model.
- **debug_logs.txt**: Contains debug logs for troubleshooting.
- **ENV_SETUP.md**: Instructions for setting up the development environment.
- **fix_streaminig.md**: Notes on fixing streaming-related issues.
- **generate_icons.ps1**: PowerShell script for generating app icons.
- **get-pip.py**: A script for installing the Python package manager, pip.
- **pubspec.lock**: A file that lists the exact versions of all dependencies used in the project.
- **pubspec.yaml**: The project's configuration file, which specifies dependencies, assets, and other metadata.
- **README.md**: General information about the `ai_therapist_app` project.
- **refactor.md, refactor_progress.md**: Documents related to code refactoring.
- **rnnoise_integration_plan.md**: Plan for integrating the RNNoise library for noise suppression.
- **run_release_test.ps1, run_release_test.sh**: Scripts for running release tests.
- **TTS_BUFFERING_IMPLEMENTATION.md**: Documentation on the implementation of TTS buffering.
- **update_security.ps1**: PowerShell script for updating security configurations.
- **WAKELOCK_IMPLEMENTATION.md**: Documentation on the implementation of the wakelock feature.

## Directories

### `lib`

This is the main directory containing the Dart source code for the application.

- **main.dart**: The entry point of the application.
- **debug_...dart**: Files related to debugging different parts of the app (API, Firebase, etc.).
- **firebase_options.dart**: Firebase project configuration.

#### `lib/blocs`

Contains the business logic components (BLoCs) of the application, which manage the state of different parts of the app.

- **auth**: BLoCs for handling authentication (login, registration, etc.).
- **voice_session_bloc.dart**: Manages the state of a voice therapy session.

#### `lib/config`

Configuration files for the application.

- **api.dart**: Defines API endpoints and related configurations.
- **app_config.dart**: General application configuration.
- **constants.dart**: Application-level constants.
- **llm_config.dart**: Configuration for the Large Language Models (LLMs) used in the app.
- **routes.dart**: Defines the application's navigation routes using `go_router`.
- **theme.dart**: Defines the application's visual theme.

#### `lib/data`

Contains the data layer of the application, including data sources, repositories, and models.

- **datasources**:
    - **local**: Manages local data storage, including SQLite (`app_database.dart`, `database_provider.dart`) and shared preferences (`prefs_manager.dart`, `secure_storage.dart`).
    - **remote**: `api_client.dart` handles communication with the backend API.
- **models**: Defines the data models used throughout the application (e.g., `user_profile.dart`, `therapy_message.dart`).
- **repositories**: Implements the repository pattern to abstract data sources from the rest of the application (e.g., `auth_repository.dart`, `session_repository.dart`).

#### `lib/di`

Dependency injection setup.

- **dependency_container.dart**: The main dependency injection container.
- **interfaces**: Defines the interfaces (contracts) for the services and repositories.
- **modules**: Organizes dependency registration into modules (e.g., `core_module.dart`, `services_module.dart`).
- **service_locator.dart**: The main service locator setup.

#### `lib/domain`

The domain layer, containing the core business logic and entities.

- **entities**: Defines the core business objects (e.g., `user.dart`, `session.dart`, `message.dart`).
- **repositories**: Abstract definitions of the repositories, implemented in the `data` layer.

#### `lib/presentation`

Contains the UI-related logic.

- **widgets**: Common widgets used across multiple screens.

#### `lib/screens`

Contains the different screens (UI pages) of the application.

- **chat_screen.dart**: The main screen for therapy sessions.
- **home_screen.dart**: The main dashboard of the app.
- **login_screen.dart, register_screen.dart, phone_login_screen.dart**: Authentication screens.
- **onboarding**: Screens for the user onboarding flow.
- **profile_screen.dart**: User profile management.
- **history_screen.dart**: Displays past therapy sessions.
- **settings_screen.dart**: Application settings.

#### `lib/services`

Contains the application's services, which encapsulate specific functionalities.

- **auth_service.dart**: Manages user authentication.
- **therapy_service.dart**: Core service for managing therapy sessions.
- **voice_service.dart**: Handles voice recording, playback, and TTS.
- **memory_manager.dart**: Manages conversation history and context.
- **notification_service.dart**: Manages push notifications.
- **...and more**: Other services for specific features like preferences, progress tracking, etc.

#### `lib/utils`

Utility classes and functions.

- **logger.dart, logging_service.dart, logging_config.dart**: Centralized logging utilities.
- **error_handling.dart**: Utilities for handling errors.
- **connectivity_checker.dart**: Checks for internet connectivity.
- **...and more**: Other helper classes.

### `android`, `ios`, `linux`, `macos`, `windows`, `web`

Platform-specific configuration and code for each target platform.

### `assets`

Contains static assets used by the application.

- **animations**: Lottie animations.
- **fonts**: Custom fonts.
- **icons**: App icons.
- **images**: Images and logos.

### `integration_test`

Contains integration tests for the application.

### `test`

Contains unit and widget tests for the application.
