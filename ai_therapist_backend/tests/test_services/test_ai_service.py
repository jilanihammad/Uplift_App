import pytest
from unittest.mock import patch, MagicMock
from app.services.ai_service import AIService

@pytest.fixture
def ai_service():
    with patch("app.services.ai_service.encryption_service", MagicMock()) as mock_enc:
        mock_enc.encrypt.return_value = "encrypted_data"
        mock_enc.decrypt.return_value = "decrypted_data"
        yield AIService()

@pytest.mark.asyncio
@patch("app.services.ai_service.requests.post")
async def test_generate_response(mock_post, ai_service):
    # Mock response from DeepSeek API
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "choices": [
            {
                "message": {
                    "content": "This is a test response"
                }
            }
        ]
    }
    mock_post.return_value = mock_response
    
    # Test data
    message = "How are you feeling today?"
    context = [
        {"role": "user", "content": "Hello"},
        {"role": "assistant", "content": "Hi there! How can I help you today?"}
    ]
    user_info = {"name": "Test User"}
    
    # Call the method
    response = await ai_service.generate_response(message, context, user_info)
    
    # Assertions
    assert response == "This is a test response"
    assert mock_post.called
    
    # Check that the API was called with the right parameters
    called_args = mock_post.call_args[1]
    
    # If data is passed as a JSON string, convert it to a dictionary first
    import json
    if isinstance(called_args["data"], str):
        data = json.loads(called_args["data"])
    else:
        data = called_args["data"]
    
    assert "messages" in data
    assert data["messages"][0]["role"] == "system"