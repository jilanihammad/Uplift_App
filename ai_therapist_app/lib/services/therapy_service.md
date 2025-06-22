# Therapy Service

## Overview
The `TherapyService` is the core therapy session management service that handles AI-powered therapeutic conversations, session lifecycle management, conversation context, and integration with various LLM providers for delivering personalized therapy experiences.

## Key Components

### `TherapyService` Class
- **Type**: Service Class
- **Purpose**: Manage therapy sessions and AI interactions
- **Key Features**:
  - AI-powered therapeutic conversations
  - Session state management
  - Context preservation across conversations
  - Multi-modal therapy approaches (CBT, Humanistic, etc.)
  - Progress tracking and analytics

### `TherapySession` Class
- **Type**: Data Model
- **Purpose**: Represent individual therapy session state
- **Key Features**:
  - Session metadata and timing
  - Conversation history
  - Mood tracking
  - Progress indicators

### `TherapyServiceMessage` Class
- **Type**: Data Model
- **Purpose**: Structured therapy message representation
- **Key Features**:
  - Message content and metadata
  - Sender identification
  - Timestamp tracking
  - Emotion analysis data

## Core Functionality

### Session Management
- **Session Creation**: Initialize new therapy sessions
- **Session Continuation**: Resume previous conversations
- **Session Termination**: Proper session closure with summary
- **Session History**: Track and retrieve past sessions
- **Session Analytics**: Generate session insights and statistics

### AI Integration
- **LLM Communication**: Interface with various AI providers
- **Context Management**: Maintain conversation context
- **Prompt Engineering**: Optimize therapy-specific prompts
- **Response Filtering**: Ensure therapeutic appropriateness
- **Fallback Handling**: Manage AI service failures

### Therapeutic Approaches
- **Cognitive Behavioral Therapy (CBT)**: Evidence-based CBT techniques
- **Humanistic Therapy**: Person-centered therapeutic approach
- **Mindfulness-Based Therapy**: Mindfulness and meditation guidance
- **Solution-Focused Therapy**: Goal-oriented therapeutic interventions
- **Dialectical Behavior Therapy (DBT)**: Emotion regulation techniques

## Conversation Management

### Context Preservation
- **Memory System**: Long-term conversation memory
- **Session Context**: Within-session context maintenance
- **User Preferences**: Personalized interaction style
- **Therapy Goals**: Goal-oriented conversation direction

### Message Processing
- **Input Analysis**: Analyze user messages for sentiment and intent
- **Response Generation**: Create appropriate therapeutic responses
- **Content Filtering**: Ensure safe and appropriate content
- **Personalization**: Adapt responses to user's therapy style

### Conversation Flow
- **Opening Protocols**: Session initiation routines
- **Check-in Procedures**: Regular mood and status assessments
- **Therapeutic Interventions**: Apply appropriate therapy techniques
- **Closing Routines**: Session summary and next steps

## Progress Tracking

### Session Analytics
- **Mood Tracking**: Monitor emotional state changes
- **Engagement Metrics**: Measure user participation
- **Progress Indicators**: Track therapeutic goal advancement
- **Insight Generation**: Identify patterns and improvements

### Goal Management
- **Goal Setting**: Establish therapeutic objectives
- **Progress Monitoring**: Track goal achievement
- **Adaptive Goals**: Adjust goals based on progress
- **Milestone Celebration**: Acknowledge achievements

## Integration Features

### Backend Services
- **API Communication**: Interface with therapy backend
- **Data Synchronization**: Sync session data across devices
- **Real-time Updates**: Live session updates
- **Offline Support**: Cached responses for offline use

### User Profile Integration
- **Therapy Preferences**: User's preferred therapy style
- **Historical Context**: Previous session insights
- **Personalization Data**: Individual therapy customization
- **Progress History**: Long-term progress tracking

### Voice Integration
- **Speech Analysis**: Analyze voice for emotional cues
- **TTS Responses**: Generate spoken therapy responses
- **Conversation Pacing**: Appropriate response timing
- **Voice Emotion Detection**: Detect emotional state from speech

## Configuration Options

### Therapy Settings
```dart
class TherapyConfig {
  TherapyStyle primaryStyle;     // Primary therapy approach
  int sessionDuration;           // Default session length (minutes)
  bool voiceMode;               // Enable voice interactions
  double responseDelay;         // Thoughtful response timing
  bool moodTracking;           // Enable mood monitoring
  List<String> focusAreas;     // Therapy focus areas
}
```

### AI Configuration
```dart
class AIConfig {
  String llmProvider;           // AI provider ('openai', 'anthropic')
  String model;                // Specific model version
  double temperature;          // Response creativity (0.0-1.0)
  int maxTokens;              // Maximum response length
  bool streaming;             // Enable response streaming
}
```

## Methods

### Session Methods
- `startSession()`: Begin new therapy session
- `continueSession(sessionId)`: Resume existing session
- `endSession()`: Conclude current session
- `pauseSession()`: Temporarily pause session
- `getSessionHistory()`: Retrieve past sessions

### Conversation Methods
- `sendMessage(message)`: Send user message and get response
- `generateResponse(context)`: Create AI response
- `analyzeMessage(message)`: Analyze user input
- `updateContext(message)`: Update conversation context

### Progress Methods
- `trackMood(mood)`: Record current mood
- `updateProgress(metrics)`: Update therapy progress
- `generateInsights()`: Create progress insights
- `setGoals(goals)`: Establish therapy goals

### Configuration Methods
- `setTherapyStyle(style)`: Change therapy approach
- `updatePreferences(prefs)`: Update user preferences
- `configureAI(config)`: Configure AI behavior
- `enableFeatures(features)`: Toggle therapy features

## Error Handling
- **AI Service Failures**: Graceful degradation with fallback responses
- **Network Issues**: Offline mode with cached responses
- **Context Loss**: Context recovery mechanisms
- **Invalid Responses**: Response validation and filtering
- **Session Interruptions**: Proper session state recovery

## Therapeutic Safety

### Content Safety
- **Harmful Content Detection**: Filter potentially harmful responses
- **Crisis Detection**: Identify crisis situations
- **Professional Boundaries**: Maintain appropriate therapeutic boundaries
- **Ethical Guidelines**: Ensure ethical AI therapy practices

### User Safety
- **Emergency Protocols**: Crisis intervention procedures
- **Professional Referrals**: Guidance to human professionals
- **Limitation Awareness**: Clear AI therapy limitations
- **User Consent**: Informed consent for AI therapy

## Analytics and Insights

### Session Analytics
- **Engagement Score**: Measure user engagement
- **Mood Progression**: Track emotional state changes
- **Topic Analysis**: Identify common discussion themes
- **Response Effectiveness**: Measure response helpfulness

### Progress Metrics
- **Goal Achievement**: Track therapeutic goal progress
- **Skill Development**: Monitor coping skill improvement
- **Behavioral Changes**: Identify positive behavior changes
- **Overall Wellbeing**: Holistic progress assessment

## Dependencies
- `http`: Backend API communication
- `shared_preferences`: Local session storage
- `uuid`: Session identifier generation
- Various AI and LLM service integrations

## Usage Example
```dart
final therapyService = serviceLocator<TherapyService>();

// Start new session
final session = await therapyService.startSession();

// Send message and get response
final response = await therapyService.sendMessage(
  "I've been feeling anxious lately"
);

// Track mood
await therapyService.trackMood(Mood.anxious);

// End session
await therapyService.endSession();
```

## Related Files
- `lib/services/backend_service.dart` - Backend communication
- `lib/services/groq_service.dart` - LLM integration
- `lib/models/therapy_message.dart` - Message data model
- `lib/models/user_progress.dart` - Progress tracking
- `lib/services/memory_manager.dart` - Conversation memory
- `lib/config/llm_config.dart` - AI configuration