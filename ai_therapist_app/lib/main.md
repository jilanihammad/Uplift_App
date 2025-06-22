# Main Application Entry Point

## Overview
The `main.dart` file serves as the primary entry point for the AI Therapist Flutter application. It initializes Firebase services, sets up dependency injection, configures BLoC providers, and manages the app's routing structure.

## Key Components

### `main()` Function
- **Purpose**: Application entry point that initializes all required services
- **Responsibilities**:
  - Firebase initialization with error handling
  - Service locator setup for dependency injection
  - Error boundary configuration
  - App widget instantiation

### `UpliftApp` Class
- **Type**: StatelessWidget
- **Purpose**: Root application widget with BLoC providers and routing
- **Key Features**:
  - Multi-BLoC provider setup for state management
  - GoRouter configuration for navigation
  - Theme configuration
  - Error handling boundaries

### `MyApp` Class
- **Type**: StatefulWidget
- **Purpose**: Main application wrapper handling authentication state
- **Key Features**:
  - Authentication state monitoring
  - Initial route determination
  - Service initialization tracking
  - Error recovery mechanisms

## Dependencies
- `firebase_core`: Firebase initialization
- `flutter_bloc`: State management
- `go_router`: Navigation and routing
- `get_it`: Dependency injection
- Service locator for all app services

## Initialization Flow
1. Firebase services initialization
2. Service locator registration
3. Authentication state check
4. BLoC provider setup
5. Router configuration
6. Theme application
7. App widget rendering

## Error Handling
- Firebase initialization errors are caught and logged
- Service initialization failures trigger fallback behavior
- Error boundaries prevent app crashes during startup

## Usage
This file is automatically executed when the app starts. No manual instantiation required.

## Configuration
- Environment-specific settings loaded from `app_config.dart`
- Debug vs production behavior differentiated
- Service registration handled by `service_locator.dart`

## Related Files
- `lib/config/app_config.dart` - Application configuration
- `lib/di/service_locator.dart` - Dependency injection setup
- `lib/config/routes.dart` - Router configuration
- `lib/config/theme.dart` - App theming
- `lib/blocs/auth/auth_bloc.dart` - Authentication state management