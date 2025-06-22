# Home Screen

## Overview
The `HomeScreen` serves as the main dashboard for the AI Therapist app, providing users with a comprehensive view of their therapy progress, quick access to sessions, mood tracking, and navigation to other app sections.

## Key Components

### `HomeScreen` Class
- **Type**: StatefulWidget
- **Purpose**: Main dashboard interface for authenticated users
- **Key Features**:
  - User progress overview
  - Quick session access
  - Mood tracking interface
  - Navigation shortcuts
  - Recent activity display

### `_HomeScreenState` Class
- **Type**: State<HomeScreen>
- **Purpose**: Manages home screen state and user interactions
- **Key Methods**:
  - `initState()`: Initialize user data and progress
  - `_loadUserProgress()`: Fetch user statistics and history
  - `_startQuickSession()`: Launch therapy session
  - `_updateMood()`: Handle mood tracking input

## UI Sections

### Header Section
- **User Greeting**: Personalized welcome message
- **Profile Avatar**: User photo with quick profile access
- **Notification Icon**: Unread notifications indicator
- **Settings Access**: Quick settings menu

### Progress Overview
- **Session Streak**: Consecutive days with sessions
- **Total Sessions**: Lifetime session count
- **Mood Trend**: Recent mood pattern visualization
- **Weekly Goals**: Progress toward weekly objectives

### Quick Actions
- **Start Session**: Direct access to therapy chat
- **Voice Session**: Quick voice-only session
- **Mood Check-in**: Rapid mood logging
- **Emergency Support**: Crisis resources access

### Recent Activity
- **Last Session**: Summary of most recent therapy session
- **Mood History**: Recent mood entries with trends
- **Achievements**: Recently earned progress badges
- **Reminders**: Upcoming therapy-related tasks

### Navigation Menu
- **History**: Session history and analytics
- **Progress**: Detailed progress tracking
- **Resources**: Educational materials and tools
- **Profile**: User settings and preferences

## State Management
- **User Progress**: Real-time progress data updates
- **Session Status**: Current/pending session information
- **Mood Data**: Recent mood entries and trends
- **Notification State**: Unread messages and alerts

## Data Loading
- User profile information
- Session statistics and history
- Mood tracking data
- Achievement status
- Notification count

## Navigation Actions
- **Start New Session**: Navigate to `ChatScreen`
- **View History**: Navigate to `HistoryScreen`
- **Check Progress**: Navigate to `ProgressScreen`
- **Access Resources**: Navigate to `ResourcesScreen`
- **Edit Profile**: Navigate to `ProfileScreen`
- **Open Settings**: Navigate to `SettingsScreen`

## Interactive Elements
- **Mood Selector**: Quick mood logging widget
- **Session Timer**: Visual session scheduling
- **Progress Cards**: Tappable statistics cards
- **Action Buttons**: Primary therapy actions

## Error Handling
- Network connectivity issues
- Data loading failures
- Session start failures
- Authentication token expiry

## Refresh Mechanism
- Pull-to-refresh for latest data
- Automatic periodic updates
- Background data synchronization
- Real-time notification updates

## Dependencies
- `flutter_bloc`: State management for user data
- `shared_preferences`: Local storage for quick access
- `connectivity_plus`: Network status monitoring
- Various services for data retrieval

## Accessibility
- Screen reader support
- High contrast mode compatibility
- Large text support
- Voice navigation assistance

## Usage
Primary screen after successful authentication. Central hub for all app functionality.

## Related Files
- `lib/screens/chat_screen.dart` - Therapy session interface
- `lib/screens/progress_screen.dart` - Detailed progress tracking
- `lib/screens/history_screen.dart` - Session history
- `lib/widgets/mood_selector.dart` - Mood tracking widget
- `lib/services/progress_service.dart` - Progress data management
- `lib/models/user_progress.dart` - Progress data model