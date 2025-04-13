import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

@pytest.mark.parametrize("message", [
    "Hello, how are you?",
    "I feel anxious about my upcoming exams.",
    "Can you help me with stress management?"
])
def test_groq_llm_response(message):
    """Test the Groq LLM response for various user inputs."""
    response = client.post("/api/v1/ai/response", json={"message": message})
    assert response.status_code == 200
    assert "response" in response.json()
    print(f"Input: {message}\nResponse: {response.json()['response']}")

@pytest.mark.parametrize("text", [
    "This is a test for voice synthesis.",
    "Can you convert this text to speech?",
    "Hello, this is a voice test."
])
def test_groq_voice_model(text):
    """Test the Groq voice model for text-to-speech conversion."""
    response = client.post("/api/v1/voice/synthesize", json={"text": text})
    assert response.status_code == 200
    assert "audio_url" in response.json()
    print(f"Input: {text}\nAudio URL: {response.json()['audio_url']}")