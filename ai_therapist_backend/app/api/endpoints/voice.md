# Voice API Endpoints

## Overview
The `voice.py` module contains FastAPI endpoints for voice processing functionality, including Text-to-Speech (TTS), audio transcription, and WebSocket streaming for real-time voice interactions with security validation and streaming pipeline integration.

## Key Components

### TTS Endpoints
- **Text-to-Speech Generation**: Convert text responses to audio
- **Voice Selection**: Multiple voice options and personalities
- **Audio Format Support**: Various audio formats (MP3, WAV, OGG)
- **Quality Control**: High-quality audio generation
- **Error Handling**: Robust error recovery

### Transcription Endpoints
- **Speech-to-Text**: Convert audio to text transcription
- **Multiple Formats**: Support various audio input formats
- **Quality Optimization**: Audio preprocessing for better transcription
- **Language Support**: Multi-language transcription capability

### WebSocket Streaming
- **Real-time Communication**: Live voice interaction streaming
- **Security Validation**: Token-based authentication for WebSockets
- **Streaming Pipeline**: Integration with enhanced async pipeline
- **Connection Management**: Handle client connections and disconnections

## Endpoints

### POST `/tts`
Generate text-to-speech audio from text input.

#### Request Body
```json
{
  "text": "Hello, how are you feeling today?",
  "voice": "alloy",
  "format": "mp3",
  "speed": 1.0
}
```

#### Response
```json
{
  "audio_url": "https://api.example.com/static/audio/abc123.mp3",
  "duration": 3.5,
  "format": "mp3",
  "file_size": 45632
}
```

#### Implementation
```python
@router.post("/tts")
async def generate_tts(
    request: TTSRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        audio_path = await voice_service.generate_speech(
            text=request.text,
            voice=request.voice
        )
        
        audio_url = voice_service.get_audio_url(audio_path)
        
        return TTSResponse(
            audio_url=audio_url,
            duration=await get_audio_duration(audio_path),
            format=request.format,
            file_size=os.path.getsize(audio_path)
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

### POST `/transcribe`
Convert audio to text transcription.

#### Request
- **Content-Type**: `multipart/form-data`
- **File**: Audio file (WAV, MP3, OGG, M4A)
- **Parameters**: Language, model preferences

#### Response
```json
{
  "transcript": "I've been feeling anxious lately and need help.",
  "confidence": 0.95,
  "language": "en",
  "duration": 4.2
}
```

#### Implementation
```python
@router.post("/transcribe")
async def transcribe_audio(
    file: UploadFile = File(...),
    language: str = "en",
    current_user: User = Depends(get_current_user)
):
    # Validate file format
    if not file.filename.endswith(('.wav', '.mp3', '.ogg', '.m4a')):
        raise HTTPException(
            status_code=400, 
            detail="Unsupported audio format"
        )
    
    # Save uploaded file temporarily
    temp_path = await save_upload_file(file)
    
    try:
        # Transcribe audio
        result = await transcription_service.transcribe_audio(
            audio_path=temp_path,
            language=language
        )
        
        return TranscriptionResponse(
            transcript=result.text,
            confidence=result.confidence,
            language=result.language,
            duration=result.duration
        )
    finally:
        # Cleanup temporary file
        os.unlink(temp_path)
```

### WebSocket `/ws/voice`
Real-time voice streaming for live conversations.

#### Connection Parameters
- **Token**: Authentication token in query parameters
- **Session ID**: Therapy session identifier
- **Format**: Audio format preference

#### Message Types
```python
# Client to Server
{
  "type": "audio_chunk",
  "data": "base64_encoded_audio",
  "sequence": 1,
  "is_final": false
}

{
  "type": "session_start",
  "session_id": "sess_123",
  "user_id": "user_456"
}

# Server to Client
{
  "type": "transcription",
  "text": "partial transcription...",
  "is_final": false
}

{
  "type": "ai_response",
  "text": "AI generated response",
  "audio_url": "https://api.example.com/audio/response.mp3"
}
```

#### Implementation
```python
@router.websocket("/ws/voice")
async def voice_websocket(
    websocket: WebSocket,
    token: str = Query(...),
    session_id: str = Query(...)
):
    # Authenticate user
    user = await authenticate_websocket_token(token)
    if not user:
        await websocket.close(code=4001, reason="Unauthorized")
        return
    
    await websocket.accept()
    
    try:
        # Initialize streaming pipeline
        pipeline = EnhancedAsyncPipeline(
            websocket=websocket,
            user_id=user.id,
            session_id=session_id
        )
        
        # Handle incoming messages
        async for message in websocket.iter_json():
            await pipeline.process_message(message)
            
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected for user {user.id}")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        await websocket.close(code=1011, reason="Internal error")
    finally:
        # Cleanup resources
        await pipeline.cleanup()
```

## Security Features

### Authentication
- **JWT Token Validation**: Secure endpoint access
- **WebSocket Authentication**: Token-based WebSocket security
- **User Authorization**: Verify user permissions
- **Session Validation**: Ensure valid therapy sessions

### Input Validation
```python
class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4000)
    voice: str = Field(default="alloy", regex="^(alloy|echo|fable|onyx|nova|shimmer)$")
    format: str = Field(default="mp3", regex="^(mp3|wav|ogg)$")
    speed: float = Field(default=1.0, ge=0.25, le=4.0)

class TranscriptionRequest(BaseModel):
    language: str = Field(default="en", regex="^[a-z]{2}$")
    model: str = Field(default="whisper-1")
```

### Rate Limiting
```python
@router.post("/tts")
@limiter.limit("10/minute")
async def generate_tts(request: Request, ...):
    # TTS endpoint with rate limiting
    pass

@router.post("/transcribe")
@limiter.limit("5/minute")
async def transcribe_audio(request: Request, ...):
    # Transcription endpoint with rate limiting
    pass
```

## Error Handling

### HTTP Errors
```python
# Custom exception handlers
@router.exception_handler(VoiceServiceError)
async def voice_service_error_handler(request: Request, exc: VoiceServiceError):
    return JSONResponse(
        status_code=500,
        content={"detail": f"Voice service error: {exc.message}"}
    )

@router.exception_handler(TranscriptionError)
async def transcription_error_handler(request: Request, exc: TranscriptionError):
    return JSONResponse(
        status_code=400,
        content={"detail": f"Transcription failed: {exc.message}"}
    )
```

### WebSocket Error Handling
```python
async def handle_websocket_error(websocket: WebSocket, error: Exception):
    error_message = {
        "type": "error",
        "message": str(error),
        "code": getattr(error, 'code', 'UNKNOWN_ERROR'),
        "recoverable": getattr(error, 'recoverable', False)
    }
    
    try:
        await websocket.send_json(error_message)
    except:
        # Connection already closed
        pass
```

## Streaming Pipeline Integration

### Enhanced Async Pipeline
```python
class EnhancedAsyncPipeline:
    def __init__(self, websocket: WebSocket, user_id: str, session_id: str):
        self.websocket = websocket
        self.user_id = user_id
        self.session_id = session_id
        self.audio_buffer = AudioBuffer()
        self.transcription_queue = asyncio.Queue()
        
    async def process_audio_chunk(self, audio_data: bytes):
        # Add to buffer
        self.audio_buffer.add_chunk(audio_data)
        
        # Process if buffer ready
        if self.audio_buffer.is_ready():
            audio_segment = self.audio_buffer.get_segment()
            await self.transcribe_segment(audio_segment)
    
    async def transcribe_segment(self, audio_segment: bytes):
        # Send for transcription
        transcript = await transcription_service.transcribe_chunk(audio_segment)
        
        # Send partial result to client
        await self.websocket.send_json({
            "type": "transcription",
            "text": transcript.text,
            "is_final": transcript.is_final
        })
        
        # Generate AI response if final
        if transcript.is_final:
            await self.generate_ai_response(transcript.text)
```

## Performance Optimization

### Audio Processing
- **Chunk Processing**: Handle audio in manageable chunks
- **Buffer Management**: Efficient audio buffer handling
- **Compression**: Optimize audio compression for streaming
- **Format Conversion**: Efficient format conversion

### Memory Management
- **Resource Cleanup**: Automatic cleanup of temporary files
- **Memory Limits**: Monitor and limit memory usage
- **Connection Limits**: Manage concurrent WebSocket connections
- **Buffer Limits**: Prevent memory overflow from large audio files

## Monitoring and Logging

### Request Logging
```python
@router.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    response = await call_next(request)
    
    process_time = time.time() - start_time
    logger.info(
        f"Voice API: {request.method} {request.url.path} "
        f"- {response.status_code} - {process_time:.3f}s"
    )
    
    return response
```

### WebSocket Monitoring
```python
class WebSocketMetrics:
    def __init__(self):
        self.active_connections = 0
        self.total_messages = 0
        self.average_latency = 0.0
    
    async def log_connection(self, user_id: str):
        self.active_connections += 1
        logger.info(f"WebSocket connected: {user_id}, total: {self.active_connections}")
    
    async def log_disconnection(self, user_id: str):
        self.active_connections -= 1
        logger.info(f"WebSocket disconnected: {user_id}, total: {self.active_connections}")
```

## Dependencies
- `fastapi`: Web framework
- `websockets`: WebSocket support
- `python-multipart`: File upload support
- Voice and transcription services
- Authentication dependencies
- Database session management

## Related Files
- `app/services/voice_service.py` - TTS implementation
- `app/services/transcription_service.py` - Speech-to-text
- `app/services/streaming_pipeline.py` - Real-time streaming
- `app/core/security.py` - Authentication utilities
- `app/models/session.py` - Session data models