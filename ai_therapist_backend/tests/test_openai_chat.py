import openai
import asyncio

async def test_chat_completion():
    openai.api_key = "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"

    try:
        response = await openai.ChatCompletion.acreate(
            model="meta-llama/llama-4-scout-17b-16e-instruct",
            messages=[{"role": "user", "content": "Hello, how are you?"}]
        )
        print("Response:", response.choices[0].message.content)
    except Exception as e:
        print("Error:", str(e))

if __name__ == "__main__":
    asyncio.run(test_chat_completion())