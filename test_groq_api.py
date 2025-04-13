import requests
import json
import os
from dotenv import load_dotenv

# Load API key from environment
load_dotenv()
api_key = os.getenv("GROQ_API_KEY", "")
model = os.getenv("GROQ_LLM_MODEL_ID", "meta-llama/llama-4-scout-17b-16e-instruct")
url = os.getenv("GROQ_API_BASE_URL", "https://api.groq.com/openai/v1") + "/chat/completions"

# Check if API key exists
if not api_key:
    print("Error: GROQ_API_KEY not found in environment variables or .env file")
    exit(1)

# Request headers
headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {api_key}"
}

# Request payload
payload = {
    "model": model,
    "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello, how are you? Please respond in one brief sentence."}
    ],
    "temperature": 0.7,
    "max_tokens": 100
}

# Make the API request
print("Sending request to Groq API...")
print(f"Using model: {model}")
print(f"API key: {api_key[:5]}...")

try:
    response = requests.post(url, headers=headers, json=payload, timeout=30)

    # Print the response
    print(f"Status code: {response.status_code}")
    if response.status_code == 200:
        result = response.json()
        content = result["choices"][0]["message"]["content"]
        print("\nResponse content:")
        print(content)
        
        # Print additional information
        print("\nModel used:", result.get("model"))
        print("Usage:")
        print(f"  Prompt tokens: {result['usage']['prompt_tokens']}")
        print(f"  Completion tokens: {result['usage']['completion_tokens']}")
        print(f"  Total tokens: {result['usage']['total_tokens']}")
    else:
        print("\nError response:")
        print(response.text)
except Exception as e:
    print(f"\nRequest failed: {str(e)}") 