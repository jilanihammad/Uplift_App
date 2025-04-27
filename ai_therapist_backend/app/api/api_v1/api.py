from fastapi import APIRouter

from app.api.endpoints import ai, voice

api_router = APIRouter()
api_router.include_router(ai.router, prefix="/llm", tags=["ai"])
api_router.include_router(voice.router, prefix="/voice", tags=["voice"])

# Add your routes here, for example:
# @api_router.get("/")
# async def root():
#     return {"message": "Welcome to AI Therapist API"}

# Include any other routers if you have them
# from .endpoints import users, auth, chat
# api_router.include_router(users.router, prefix="/users", tags=["users"])
# api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
# api_router.include_router(chat.router, prefix="/chat", tags=["chat"])