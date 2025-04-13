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
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)