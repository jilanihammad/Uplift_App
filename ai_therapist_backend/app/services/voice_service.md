# Voice Service

## Overview
The `VoiceService` handles Text-to-Speech (TTS) functionality using OpenAI's TTS API, providing high-quality voice synthesis for AI therapist responses. It includes audio file management, Cloud Run compatibility, and optimized storage solutions.

## Key Components

### `VoiceService` Class
- **Type**: Service Class
- **Purpose**: Convert text responses to natural speech audio
- **Key Features**:
  - OpenAI TTS API integration
  - Multiple voice options
  - Audio format optimization
  - Cloud storage compatibility
  - Environment-aware file handling

## Core Functionality

### Text-to-Speech Generation
- **Voice Synthesis**: Convert text to natural-sounding speech
- **Voice Selection**: Multiple voice personalities and styles
- **Audio Quality**: High-fidelity audio generation
- **Format Support**: MP3, WAV, OGG audio formats
- **Streaming Support**: Progressive audio generation

### Audio File Management
- **File Generation**: Create audio files from text input
- **Storage Management**: Efficient file storage and cleanup
- **URL Generation**: Provide accessible audio file URLs
- **Cache Management**: Optimize storage with intelligent caching
- **Cleanup Automation**: Automatic temporary file removal

### Cloud Integration
- **Cloud Run Compatibility**: Optimized for serverless deployment
- **Static File Serving**: Efficient audio file delivery
- **CDN Integration**: Content delivery network support
- **Storage Optimization**: Minimize storage costs and usage

## Methods

### `generate_speech(text, voice="alloy")`
- **Purpose**: Generate TTS audio from text input
- **Parameters**:
  - `text`: Text content to convert to speech
  - `voice`: Voice selection (alloy, echo, fable, onyx, nova, shimmer)
- **Returns**: Audio file path or URL
- **Features**:
  - Multiple voice options
  - Audio quality optimization
  - Error handling with fallbacks

### `get_audio_url(audio_file_path)`
- **Purpose**: Generate accessible URL for audio file
- **Parameters**:
  - `audio_file_path`: Local file path to audio
- **Returns**: Public URL for audio access
- **Features**:
  - Environment-aware URL generation
  - CDN integration
  - Secure access URLs

### `cleanup_audio_files()`
- **Purpose**: Remove temporary and expired audio files
- **Features**:
  - Automatic cleanup scheduling
  - Storage optimization
  - Error handling for file operations

## Configuration

### TTS Configuration
```python
class TTSConfig:
    api_key: str              # OpenAI API key
    model: str               # TTS model ('tts-1', 'tts-1-hd')
    voice: str               # Default voice selection
    response_format: str     # Audio format ('mp3', 'opus', 'aac')
    speed: float            # Speech rate (0.25-4.0)
    quality: str            # Audio quality ('standard', 'hd')
```

### Voice Options
```python
AVAILABLE_VOICES = {
    "alloy": "Balanced, neutral voice",
    "echo": "Male voice with clarity",
    "fable": "Warm, engaging voice",
    "onyx": "Deep, authoritative voice",
    "nova": "Young, energetic voice",
    "shimmer": "Soft, gentle voice"
}
```

### Audio Settings
```python
class AudioSettings:
    sample_rate: int = 24000     # Audio sample rate
    bit_rate: int = 64           # Audio bit rate (kbps)
    format: str = "mp3"          # Default audio format
    max_file_size: int = 10485760  # 10MB max file size
    cache_duration: int = 3600    # Cache duration in seconds
```

## Environment Adaptation

### Development Environment
```python
if environment == "development":
    audio_base_url = "http://localhost:8000/static/audio"
    storage_path = "./static/audio"
```

### Production Environment
```python
if environment == "production":
    audio_base_url = f"https://{cloud_run_url}/static/audio"
    storage_path = "/tmp/audio"  # Temporary storage for Cloud Run
```

### Cloud Run Optimization
- **Temporary Storage**: Use `/tmp` for ephemeral file storage
- **Memory Management**: Optimize memory usage for audio processing
- **Startup Time**: Minimize cold start impact
- **Resource Limits**: Work within Cloud Run resource constraints

## Error Handling

### API Errors
```python
try:
    audio_response = await openai_client.audio.speech.create(
        model="tts-1",
        voice=voice,
        input=text
    )
except RateLimitError:
    # Handle rate limiting with exponential backoff
    await asyncio.sleep(retry_delay)
except APIError as e:
    # Handle API errors with fallback
    logger.error(f"OpenAI TTS API error: {e}")
    return None
```

### File System Errors
- **Storage Failures**: Handle disk space and permission issues
- **Network Errors**: Manage upload and download failures
- **Corruption**: Detect and handle corrupted audio files
- **Access Errors**: Handle file access permission problems

### Fallback Strategies
- **Text Response**: Return text when TTS fails
- **Cached Audio**: Use cached responses when possible
- **Alternative Voices**: Try different voices on failure
- **Quality Degradation**: Use lower quality as fallback

## Performance Optimization

### Caching Strategy
```python
class AudioCache:
    def __init__(self):
        self.cache = {}
        self.max_size = 100
        self.ttl = 3600  # 1 hour
    
    async def get_cached_audio(self, text_hash):
        # Return cached audio if available and valid
        pass
    
    async def cache_audio(self, text_hash, audio_path):
        # Store audio in cache with TTL
        pass
```

### Memory Management
- **Stream Processing**: Process audio in chunks
- **Garbage Collection**: Proper cleanup of audio objects
- **Memory Limits**: Monitor and limit memory usage
- **Resource Pooling**: Reuse audio processing resources

### Network Optimization
- **Compression**: Optimize audio file compression
- **Concurrent Requests**: Handle multiple TTS requests
- **Connection Pooling**: Reuse HTTP connections
- **Timeout Management**: Appropriate request timeouts

## Security Features

### API Security
- **API Key Protection**: Secure storage of OpenAI credentials
- **Request Validation**: Validate input text content
- **Rate Limiting**: Prevent API abuse
- **Access Control**: Limit TTS access to authorized users

### Content Safety
- **Text Filtering**: Filter inappropriate content before TTS
- **Content Length**: Limit text length for TTS generation
- **Harmful Content**: Detect and block harmful text
- **Privacy Protection**: Handle sensitive information appropriately

### File Security
- **Secure URLs**: Generate secure audio access URLs
- **Access Expiration**: Time-limited audio file access
- **Path Validation**: Prevent directory traversal attacks
- **File Cleanup**: Automatic removal of sensitive audio files

## Monitoring and Analytics

### Performance Metrics
- **Generation Time**: TTS audio generation latency
- **File Size**: Monitor audio file sizes
- **Success Rate**: TTS generation success percentage
- **Cache Hit Rate**: Audio cache effectiveness

### Usage Analytics
- **Voice Popularity**: Track preferred voice selections
- **Text Length**: Analyze typical text-to-speech lengths
- **Error Patterns**: Identify common failure scenarios
- **Cost Tracking**: Monitor OpenAI API usage costs

## Integration Features

### API Integration
- **RESTful Endpoints**: HTTP endpoints for TTS requests
- **WebSocket Support**: Real-time audio streaming
- **Batch Processing**: Handle multiple TTS requests
- **Status Updates**: Real-time generation status

### Service Integration
- **AI Service**: Convert AI responses to speech
- **Chat Service**: Audio responses in conversations
- **Session Service**: Audio summaries and notifications
- **User Service**: Personalized voice preferences

## Dependencies
- `openai`: OpenAI TTS API client
- `aiofiles`: Async file operations
- `fastapi`: Web framework integration
- `asyncio`: Asynchronous processing
- `pathlib`: File path management
- `hashlib`: Content hashing for caching

## Usage Example
```python
voice_service = VoiceService()

# Generate speech
audio_path = await voice_service.generate_speech(
    text="Hello, how are you feeling today?",
    voice="alloy"
)

# Get accessible URL
audio_url = voice_service.get_audio_url(audio_path)

# Cleanup when done
await voice_service.cleanup_audio_files()
```

## Related Files
- `app/services/ai_service.py` - AI response generation
- `app/api/endpoints/voice.py` - Voice API endpoints
- `app/core/config.py` - Service configuration
- `app/services/transcription_service.py` - Speech-to-text counterpart