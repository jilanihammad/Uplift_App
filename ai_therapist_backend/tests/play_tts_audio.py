import asyncio
import websockets
import json
import base64

# Set your WebSocket endpoint here
WS_URL = "wss://ai-therapist-backend-385290373302.us-central1.run.app/voice/ws/tts"

# The TTS request payload
TTS_REQUEST = {
    "text": "Hello, this is a real-time TTS streaming test.",
    "voice": "sage",
    "params": {
        "response_format": "opus",
        "bitrate": "24k",
        "mono": True
    }
}

OUTPUT_FILE = "output.opus"

async def main():
    audio_data = b""
    async with websockets.connect(WS_URL) as ws:
        # Send the TTS request
        await ws.send(json.dumps(TTS_REQUEST))
        print("Sent TTS request. Receiving audio chunks...")

        while True:
            msg = await ws.recv()
            data = json.loads(msg)
            if data["type"] == "audio_chunk":
                audio_data += base64.b64decode(data["data"])
                print(f"Received chunk {data['sequence']}")
            elif data["type"] == "done":
                print("Streaming done.")
                break
            elif data["type"] == "error":
                print("Error from server:", data["detail"])
                return

    # Save the audio to a file
    with open(OUTPUT_FILE, "wb") as f:
        f.write(audio_data)
    print(f"Saved audio to {OUTPUT_FILE}")

    # Optionally, play the audio (requires VLC installed and in PATH)
    try:
        import subprocess
        print("Playing audio with VLC...")
        subprocess.run(["vlc", "--play-and-exit", OUTPUT_FILE])
    except Exception as e:
        print("Could not play audio automatically. Please open", OUTPUT_FILE, "with your favorite player.")

if __name__ == "__main__":
    asyncio.run(main())