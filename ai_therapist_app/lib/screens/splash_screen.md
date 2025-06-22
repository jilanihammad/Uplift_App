# Splash Screen

## Overview
The `SplashScreen` is the initial loading screen that handles app initialization, service setup, authentication checks, and routing decisions. It provides a smooth user experience while critical app services are being initialized in the background.

## Key Components

### `SplashScreen` Class
- **Type**: StatefulWidget
- **Purpose**: Display loading screen during app initialization
- **Key Features**:
  - Animated logo display
  - Loading progress indicators
  - Service initialization monitoring
  - Automatic navigation to appropriate screen

### `_SplashScreenState` Class
- **Type**: State<SplashScreen>
- **Purpose**: Manages splash screen lifecycle and initialization logic
- **Key Methods**:
  - `initState()`: Starts initialization process
  - `_initializeApp()`: Handles service setup and authentication check
  - `_navigateToNextScreen()`: Determines and navigates to appropriate screen

## Initialization Process
1. **Service Initialization**
   - Firebase services setup
   - Local database initialization
   - Dependency injection container setup
   - Authentication service initialization

2. **Authentication Check**
   - Check for existing user session
   - Validate authentication tokens
   - Determine user onboarding status

3. **Navigation Decision**
   - First-time users → Onboarding flow
   - Authenticated users → Home screen
   - Unauthenticated users → Login screen

## UI Components
- **App Logo**: Centered animated logo with fade-in effect
- **Loading Indicator**: Progress spinner or animated loading bar
- **Status Text**: Optional status messages during initialization
- **Error Handling**: Graceful error display if initialization fails

## Error Handling
- Network connectivity issues
- Firebase initialization failures
- Database setup errors
- Service dependency failures

## Navigation Targets
- `OnboardingWrapper`: For new users
- `HomeScreen`: For authenticated users
- `LoginScreen`: For unauthenticated users
- `ErrorScreen`: For initialization failures

## Animation & Timing
- Minimum display time: 2 seconds (for branding)
- Maximum wait time: 10 seconds (timeout protection)
- Smooth transition animations to next screen
- Loading progress feedback

## Dependencies
- `firebase_core`: Firebase initialization
- `shared_preferences`: Local storage access
- `connectivity_plus`: Network status checking
- Service locator for dependency injection

## Usage
Automatically displayed as the app's initial screen. No manual navigation required.

## Configuration
- Logo assets defined in `pubspec.yaml`
- Initialization timeout configurable in app config
- Navigation routes defined in `routes.dart`

## Related Files
- `lib/di/service_locator.dart` - Service initialization
- `lib/services/auth_service.dart` - Authentication checking
- `lib/config/routes.dart` - Navigation configuration
- `lib/screens/onboarding/onboarding_wrapper.dart` - Onboarding flow
- `lib/screens/home_screen.dart` - Main app screen
- `lib/screens/login_screen.dart` - Authentication screen