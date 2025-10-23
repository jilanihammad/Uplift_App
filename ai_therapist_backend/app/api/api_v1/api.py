from fastapi import APIRouter

from app.api.endpoints import ai, anchors, mood_entries, profile, session_summaries, voice

api_router = APIRouter()
api_router.include_router(ai.router, prefix="/llm", tags=["ai"])
api_router.include_router(voice.router, prefix="/voice", tags=["voice"])
api_router.include_router(profile.router, prefix="/profile", tags=["profile"])
api_router.include_router(anchors.router, prefix="/anchors", tags=["anchors"])
api_router.include_router(session_summaries.router, prefix="/session_summaries", tags=["session_summaries"])
api_router.include_router(mood_entries.router, prefix="/mood_entries", tags=["mood_entries"])

# Add your routes here, for example:
# @api_router.get("/")
# async def root():
#     return {"message": "Welcome to AI Therapist API"}

# Include any other routers if you have them
# from .endpoints import users, auth, chat
# api_router.include_router(users.router, prefix="/users", tags=["users"])
# api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
# api_router.include_router(chat.router, prefix="/chat", tags=["chat"])
