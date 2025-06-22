# Chat Screen

## Overview
The `ChatScreen` is the core therapy session interface where users engage in real-time conversations with the AI therapist. It supports both voice and text interactions, handles message display, recording controls, and manages the entire therapy session lifecycle.

## Key Components

### `ChatScreen` Class
- **Type**: StatefulWidget
- **Purpose**: Primary therapy session interface
- **Key Features**:
  - Real-time messaging with AI therapist
  - Voice recording and playback
  - Message history display
  - Session management
  - Audio/text mode switching

## UI Components

### App Bar
- **Session Info**: Current session details and duration
- **Mode Toggle**: Switch between voice and text modes
- **End Session**: Terminate current session
- **Settings**: Session-specific settings

### Message Display Area
- **Chat Bubble List**: Scrollable conversation history
- **User Messages**: User's text/transcribed voice messages
- **Therapist Responses**: AI-generated therapy responses
- **System Messages**: Session status and notifications
- **Typing Indicators**: Real-time typing/processing feedback

### Input Controls
- **Voice Controls**: Microphone button with recording animation
- **Text Input**: Text field for typed messages
- **Send Button**: Submit text messages
- **Mode Selector**: Toggle between input methods

### Session Controls
- **Recording Status**: Visual feedback for voice recording
- **Audio Playback**: Controls for playing AI responses
- **Session Timer**: Current session duration display
- **Connection Status**: Backend connectivity indicator

## Voice Interaction Features

### Recording Management
- **Push-to-Talk**: Manual recording control
- **Auto-Listen**: Automatic voice detection
- **Noise Cancellation**: RNNoise integration for clear audio
- **Recording Indicators**: Visual and haptic feedback

### Audio Processing
- **Real-time Transcription**: Speech-to-text conversion
- **TTS Playback**: Text-to-speech for AI responses
- **Audio Quality**: Noise reduction and enhancement
- **Format Support**: Multiple audio formats (WAV, MP3, OGG)

### Voice Activity Detection
- **Smart Listening**: Automatic speech detection
- **Silence Handling**: Intelligent pause detection
- **Background Noise**: Adaptive noise filtering
- **Echo Cancellation**: Clear two-way communication

## Text Interaction Features

### Text Input
- **Rich Text**: Emoji and formatting support
- **Auto-correction**: Intelligent text correction
- **Suggestions**: Contextual input suggestions
- **Character Limit**: Reasonable message length limits

### Message Processing
- **Real-time Display**: Immediate message rendering
- **Message Status**: Sent/delivered/read indicators
- **Error Handling**: Failed message retry
- **Offline Queue**: Message queuing for offline mode

## Session Management

### Session Lifecycle
- **Session Start**: Initialize therapy conversation
- **Context Maintenance**: Preserve conversation context
- **Session Pause/Resume**: Handle interruptions
- **Session End**: Proper session termination

### Data Persistence
- **Message History**: Store conversation locally
- **Session Metadata**: Track session statistics
- **Progress Updates**: Update user progress
- **Backup**: Cloud synchronization of session data

## AI Integration

### Therapy AI
- **Context Awareness**: Maintain conversation context
- **Therapeutic Responses**: CBT and therapy-focused replies
- **Emotion Recognition**: Understand user emotional state
- **Personalization**: Adapt to user's therapy style

### Response Processing
- **Real-time Generation**: Fast AI response times
- **Streaming**: Progressive response display
- **Error Recovery**: Handle AI service failures
- **Fallback Responses**: Backup responses for failures

## State Management

### BLoC Integration
- **Voice Session Bloc**: Manage voice interaction state
- **Message State**: Track conversation state
- **UI State**: Handle interface state changes
- **Error State**: Manage error conditions

### Real-time Updates
- **Message Streaming**: Live message updates
- **Status Updates**: Real-time session status
- **Progress Tracking**: Live session progress
- **Notification Handling**: In-session notifications

## Error Handling
- **Network Issues**: Handle connectivity problems
- **Recording Failures**: Microphone access errors
- **AI Service Errors**: Backend service failures
- **Audio Playback Issues**: TTS and audio problems

## Accessibility
- **Screen Reader**: Full voice-over support
- **Voice Commands**: Hands-free operation
- **Visual Indicators**: Audio status visualization
- **Text Scaling**: Dynamic text size support

## Dependencies
- `flutter_bloc`: State management
- `just_audio`: Audio playback
- `record`: Audio recording
- `speech_to_text`: Transcription services
- `flutter_tts`: Text-to-speech
- Various therapy and audio services

## Usage
Primary interface for therapy sessions. Accessed from home screen or direct session links.

## Related Files
- `lib/blocs/voice_session_bloc.dart` - Session state management
- `lib/services/voice_service.dart` - Voice processing
- `lib/services/therapy_service.dart` - AI therapy logic
- `lib/screens/widgets/voice_controls.dart` - Voice UI controls
- `lib/screens/widgets/chat_bubble.dart` - Message display
- `lib/screens/widgets/chat_message_list.dart` - Message list
- `lib/screens/widgets/text_input_bar.dart` - Text input interface