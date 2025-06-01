# Wakelock Implementation for AI Therapist App

## Overview
This document describes the implementation of wakelock functionality to prevent the device screen from turning off during therapy sessions, ensuring uninterrupted user experience.

## Problem Solved
- **Issue**: Device screen was turning off during therapy sessions, disrupting the user experience
- **Solution**: Implemented comprehensive wakelock management using `wakelock_plus` package

## Implementation Details

### 1. WakelockService (`lib/services/wakelock_service.dart`)
A centralized service that manages screen wake functionality:

**Features:**
- Enable/disable wakelock with error handling
- Periodic checks every 2 minutes to ensure wakelock stays active
- Refresh functionality for long sessions
- Status checking capability
- Automatic cleanup when disabled

**Key Methods:**
- `enable()`: Activates wakelock and starts periodic monitoring
- `disable()`: Deactivates wakelock and stops monitoring
- `refresh()`: Refreshes wakelock for long sessions
- `isEnabled`: Checks current wakelock status

### 2. Chat Screen Integration (`lib/screens/chat_screen.dart`)
Enhanced the main therapy session screen with comprehensive wakelock management:

**Lifecycle Management:**
- Enables wakelock when session starts (`initState`)
- Disables wakelock when session ends (`dispose`)
- Handles app lifecycle changes (background/foreground)
- Manages wakelock during session termination

**User Interaction Triggers:**
- Refreshes wakelock on message sending
- Refreshes wakelock on voice control interactions
- Refreshes wakelock on mode switching (voice/text)
- Periodic refresh every 10 minutes during active sessions

**Visual Indicator:**
- Green screen lock icon in app bar showing wakelock is active
- Tooltip explaining the feature to users

### 3. App Lifecycle Handling
Implements `WidgetsBindingObserver` to handle various app states:

- **Resumed**: Re-enables wakelock when app returns to foreground
- **Paused/Inactive**: Keeps wakelock active during brief interruptions
- **Hidden**: Maintains wakelock when app is hidden but running
- **Detached**: Properly disables wakelock when app is terminated

### 4. Error Handling
Robust error handling throughout:
- Try-catch blocks around all wakelock operations
- Debug logging for troubleshooting
- Graceful degradation if wakelock fails
- No blocking of app functionality if wakelock unavailable

## Dependencies

### Required Package
```yaml
dependencies:
  wakelock_plus: ^1.1.4
```

### Android Permissions
Already configured in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

## Usage

The wakelock functionality is automatically managed:

1. **Session Start**: Wakelock activates when entering chat screen
2. **During Session**: Periodic refreshes and user interaction triggers
3. **Session End**: Wakelock deactivates when leaving chat screen
4. **Background**: Maintains wakelock during brief app backgrounding

## Testing

Test file: `test/services/wakelock_service_test.dart`
- Tests enable/disable functionality
- Tests refresh behavior
- Tests error handling scenarios

## Benefits

1. **Uninterrupted Sessions**: Screen stays awake during therapy sessions
2. **Battery Efficient**: Only active during sessions, not globally
3. **User-Friendly**: Automatic management, no user intervention required
4. **Robust**: Handles edge cases and app lifecycle changes
5. **Transparent**: Visual indicator shows when feature is active

## Technical Notes

- Uses static methods for easy access across the app
- Implements singleton pattern for state management
- Periodic timer ensures wakelock persistence on problematic devices
- Graceful handling of platform-specific limitations
- Debug logging for development and troubleshooting

## Future Enhancements

Potential improvements:
- User preference to enable/disable wakelock
- Different timeout settings for different session types
- Integration with device battery optimization settings
- Analytics on wakelock effectiveness

## Troubleshooting

If screen still turns off:
1. Check device battery optimization settings
2. Verify WAKE_LOCK permission is granted
3. Check debug logs for wakelock errors
4. Test on different devices/Android versions
5. Consider device-specific power management settings 