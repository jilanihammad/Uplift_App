# Main Application Entry Point

## Overview
The `main.py` file serves as the FastAPI application entry point for the AI Therapist backend. It configures the web server, initializes database connections, sets up middleware, and registers all API endpoints.

## Key Components

### FastAPI Application Setup
- **Application Instance**: Main FastAPI app with metadata configuration
- **CORS Configuration**: Cross-origin resource sharing setup for frontend communication
- **Static Files**: Serves audio files and other static assets
- **Route Registration**: Includes all API endpoints and routers

### `init_db()` Function
- **Purpose**: Initialize database connections and create tables
- **Responsibilities**:
  - SQLAlchemy engine setup
  - Database table creation
  - Connection pool configuration
  - Migration status verification

## Application Configuration

### Server Settings
```python
app = FastAPI(
    title="AI Therapist Backend",
    description="Backend API for AI-powered therapy chatbot",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)
```

### Middleware Stack
- **CORS Middleware**: Enable cross-origin requests from Flutter frontend
- **Security Middleware**: Add security headers and protection
- **Rate Limiting**: Request throttling for API protection
- **Logging Middleware**: Request/response logging for monitoring

### Static File Serving
- **Audio Files**: Serve generated TTS audio files
- **Upload Directory**: Handle file uploads and temporary storage
- **CDN Integration**: Optimize static file delivery

## Database Initialization

### Connection Setup
- **PostgreSQL**: Primary database for production
- **SQLite**: Development and testing database
- **Connection Pooling**: Efficient database connection management
- **Migration Support**: Alembic integration for schema changes

### Table Creation
```python
async def init_db():
    engine = create_async_engine(DATABASE_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
```

## Route Configuration

### API Endpoints
- **AI Routes**: `/api/v1/ai/*` - AI conversation endpoints
- **Voice Routes**: `/api/v1/voice/*` - TTS and transcription
- **User Routes**: `/api/v1/users/*` - User management
- **Session Routes**: `/api/v1/sessions/*` - Therapy session handling

### Health Checks
- **Health Endpoint**: `/health` - Application health monitoring
- **Database Health**: Database connectivity verification
- **Service Status**: External service availability checks

## Environment Configuration

### Development Mode
```python
if settings.ENVIRONMENT == "development":
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
```

### Production Mode
- **Restricted CORS**: Limited origin access
- **HTTPS Enforcement**: Secure connection requirements
- **Security Headers**: Additional protection headers
- **Monitoring Integration**: Performance and error tracking

## Error Handling

### Global Exception Handler
```python
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Global exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )
```

### Custom Error Responses
- **ValidationError**: Input validation failures
- **AuthenticationError**: Authentication issues
- **DatabaseError**: Database operation failures
- **ExternalServiceError**: Third-party service failures

## WebSocket Support

### Real-time Communication
- **Chat WebSockets**: Real-time therapy conversation
- **Voice Streaming**: Live audio stream processing
- **Status Updates**: Real-time session status
- **Connection Management**: Handle client disconnections

### WebSocket Security
- **Authentication**: Token-based WebSocket auth
- **Rate Limiting**: WebSocket message throttling
- **Connection Limits**: Prevent connection abuse
- **Message Validation**: Input sanitization

## Monitoring and Logging

### Request Logging
- **Access Logs**: HTTP request/response logging
- **Error Logs**: Exception and error tracking
- **Performance Logs**: Response time monitoring
- **Audit Logs**: Security and data access tracking

### Health Monitoring
- **Application Health**: Service availability status
- **Database Health**: Connection and query performance
- **External Dependencies**: Third-party service monitoring
- **Resource Usage**: Memory and CPU monitoring

## Security Features

### Authentication
- **JWT Tokens**: Secure user authentication
- **Token Validation**: Request authentication middleware
- **Session Management**: User session handling
- **Password Security**: Secure password hashing

### Data Protection
- **Input Validation**: Request data sanitization
- **SQL Injection Prevention**: Parameterized queries
- **XSS Protection**: Cross-site scripting prevention
- **CSRF Protection**: Cross-site request forgery prevention

## Startup Events

### Application Startup
```python
@app.on_event("startup")
async def startup_event():
    await init_db()
    logger.info("Application started successfully")
```

### Shutdown Events
```python
@app.on_event("shutdown")
async def shutdown_event():
    # Cleanup resources
    logger.info("Application shutdown complete")
```

## Dependencies
- `fastapi`: Web framework
- `sqlalchemy`: Database ORM
- `alembic`: Database migrations
- `uvicorn`: ASGI server
- `python-multipart`: File upload support
- `python-jose`: JWT token handling

## Deployment Configuration

### Docker Support
- **Containerization**: Docker image configuration
- **Environment Variables**: Configuration via env vars
- **Health Checks**: Container health monitoring
- **Resource Limits**: Memory and CPU constraints

### Cloud Deployment
- **Google Cloud Run**: Serverless container deployment
- **Azure Container Instances**: Alternative cloud deployment
- **AWS ECS**: Container orchestration
- **Kubernetes**: Scalable deployment option

## Usage
The application starts automatically when deployed. For local development:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Related Files
- `app/core/config.py` - Application configuration
- `app/db/session.py` - Database session management
- `app/api/api_v1/api.py` - API router configuration
- `app/core/security.py` - Security utilities
- `app/core/logger.py` - Logging configuration