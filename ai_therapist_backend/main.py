import functions_framework
from app.main import app
import os

# Set production environment for Firebase
os.environ["APP_ENV"] = "production"

@functions_framework.http
def api(request):
    """
    HTTP Cloud Function entry point that works with FastAPI.
    This adapts our FastAPI app to Firebase Functions.
    """
    # Create a WSGI app wrapper around the FastAPI app
    return functions_framework.create_app(target=app, source=request)

# For local development, we can still run this file directly
if __name__ == "__main__":
    import uvicorn
    # Use local environment when running directly
    os.environ["APP_ENV"] = "local"
    # Use PORT environment variable or default to 8080 for Cloud Run compatibility
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run("app.main:app", host="0.0.0.0", port=port, reload=True)