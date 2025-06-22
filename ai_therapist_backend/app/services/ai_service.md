# AI Service

## Overview
The `AIService` handles OpenAI GPT interactions for the AI Therapist backend, managing conversation memory, context preservation, and therapeutic response generation. It serves as the primary interface between the application and OpenAI's language models.

## Key Components

### `AIService` Class
- **Type**: Service Class
- **Purpose**: Manage AI conversations and response generation
- **Key Features**:
  - OpenAI GPT integration
  - Conversation memory management
  - Context-aware therapeutic responses
  - Token usage optimization
  - Error handling and fallbacks

## Core Functionality

### Response Generation
- **Text Generation**: Create therapeutic responses using GPT models
- **Context Integration**: Incorporate conversation history and user context
- **Prompt Engineering**: Optimize prompts for therapeutic effectiveness
- **Response Filtering**: Ensure appropriate and safe responses
- **Streaming Support**: Real-time response generation

### Conversation Memory
- **Context Preservation**: Maintain conversation context across sessions
- **Memory Management**: Efficient storage and retrieval of conversation history
- **Context Limits**: Handle token limits with intelligent truncation
- **Session Continuity**: Seamless conversation flow across interactions

### Therapeutic Specialization
- **CBT Integration**: Cognitive Behavioral Therapy techniques
- **Empathetic Responses**: Emotionally appropriate responses
- **Crisis Detection**: Identify potential crisis situations
- **Professional Boundaries**: Maintain appropriate AI therapist boundaries

## Methods

### `generate_response(message, context)`
- **Purpose**: Generate AI response to user message
- **Parameters**:
  - `message`: User's input message
  - `context`: Conversation context and history
- **Returns**: AI-generated therapeutic response
- **Features**:
  - Context-aware generation
  - Therapeutic prompt engineering
  - Error handling with fallbacks

### `update_conversation_memory(user_message, ai_response)`
- **Purpose**: Store conversation exchange in memory
- **Parameters**:
  - `user_message`: User's message content
  - `ai_response`: AI's response content
- **Features**:
  - Memory optimization
  - Context window management
  - Conversation summarization

### `get_conversation_context(session_id)`
- **Purpose**: Retrieve conversation context for session
- **Parameters**:
  - `session_id`: Unique session identifier
- **Returns**: Formatted conversation context
- **Features**:
  - Session-specific context
  - Memory retrieval optimization
  - Context formatting for AI

## Configuration

### OpenAI Configuration
```python
class OpenAIConfig:
    api_key: str           # OpenAI API key
    model: str            # GPT model ('gpt-4', 'gpt-3.5-turbo')
    max_tokens: int       # Maximum response tokens
    temperature: float    # Response creativity (0.0-1.0)
    top_p: float         # Nucleus sampling parameter
    frequency_penalty: float  # Repetition penalty
    presence_penalty: float   # Topic diversity penalty
```

### Therapeutic Prompts
```python
THERAPEUTIC_SYSTEM_PROMPT = """
You are an AI therapist trained in cognitive behavioral therapy (CBT) 
and other evidence-based therapeutic approaches. Your role is to:

1. Provide empathetic, non-judgmental support
2. Use CBT techniques to help users identify thought patterns
3. Encourage healthy coping strategies
4. Maintain professional boundaries
5. Refer to human professionals when appropriate
"""
```

## Context Management

### Memory Structure
```python
class ConversationMemory:
    session_id: str
    messages: List[Message]
    user_profile: UserProfile
    therapy_goals: List[str]
    current_mood: str
    session_metadata: Dict
```

### Context Optimization
- **Token Management**: Intelligent truncation of long conversations
- **Summary Generation**: Create conversation summaries for context
- **Relevance Filtering**: Include only relevant context
- **Memory Compression**: Efficient context encoding

## Error Handling

### API Errors
- **Rate Limiting**: Handle OpenAI rate limits with exponential backoff
- **Authentication**: Manage API key validation and errors
- **Service Unavailable**: Fallback responses when OpenAI is down
- **Token Limits**: Handle context window limitations

### Fallback Responses
```python
FALLBACK_RESPONSES = [
    "I understand this is important to you. Can you tell me more about how you're feeling?",
    "It sounds like you're going through something difficult. Would you like to explore this together?",
    "I'm here to listen and support you. What's on your mind right now?"
]
```

### Response Validation
- **Content Safety**: Ensure responses are appropriate
- **Therapeutic Quality**: Validate therapeutic value
- **Length Validation**: Ensure appropriate response length
- **Format Checking**: Verify response format consistency

## Security and Privacy

### Data Protection
- **Conversation Encryption**: Encrypt sensitive conversation data
- **API Key Security**: Secure storage of OpenAI credentials
- **Data Retention**: Appropriate data retention policies
- **Access Control**: Limit access to conversation data

### Content Safety
- **Harmful Content Detection**: Filter potentially harmful responses
- **Crisis Intervention**: Detect and respond to crisis situations
- **Professional Boundaries**: Maintain appropriate therapeutic limits
- **Ethical Guidelines**: Ensure ethical AI therapy practices

## Performance Optimization

### Response Speed
- **Streaming Responses**: Real-time response generation
- **Caching**: Cache common responses and patterns
- **Connection Pooling**: Efficient API connection management
- **Async Processing**: Non-blocking response generation

### Token Efficiency
- **Prompt Optimization**: Minimize token usage in prompts
- **Context Compression**: Efficient context representation
- **Response Filtering**: Remove unnecessary tokens
- **Model Selection**: Choose appropriate model for task

## Integration Features

### Database Integration
- **Session Storage**: Store conversation sessions
- **User Context**: Integrate user profile data
- **Progress Tracking**: Store therapy progress metrics
- **Analytics**: Conversation analysis and insights

### Service Integration
- **Voice Integration**: Text-to-speech response conversion
- **Memory Service**: Long-term memory management
- **Progress Service**: Update user progress based on conversations
- **Notification Service**: Trigger notifications based on conversation

## Monitoring and Analytics

### Performance Metrics
- **Response Time**: AI generation latency
- **Token Usage**: Monitor API costs and usage
- **Error Rates**: Track API failures and issues
- **User Satisfaction**: Response quality metrics

### Conversation Analytics
- **Sentiment Analysis**: Track emotional progression
- **Topic Analysis**: Identify common therapy topics
- **Engagement Metrics**: Measure user interaction quality
- **Therapeutic Progress**: Assess conversation effectiveness

## Dependencies
- `openai`: OpenAI API client
- `tiktoken`: Token counting and management
- `asyncio`: Asynchronous processing
- `logging`: Error and usage logging
- `json`: Data serialization
- Database models for conversation storage

## Usage Example
```python
ai_service = AIService()

# Generate response
response = await ai_service.generate_response(
    message="I've been feeling really anxious lately",
    context=conversation_context
)

# Update memory
await ai_service.update_conversation_memory(
    user_message="I've been feeling really anxious lately",
    ai_response=response
)
```

## Related Files
- `app/services/llm_manager.py` - Multi-provider LLM management
- `app/core/config.py` - API configuration
- `app/models/message.py` - Message data models
- `app/models/session.py` - Session data models
- `app/services/therapy_service.py` - Therapy logic integration