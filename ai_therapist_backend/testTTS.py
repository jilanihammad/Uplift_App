"""Manual smoke test for Gemini TTS.

Run with a Google API key that has Gemini access:

    python testLLM.py --api-key YOUR_KEY --text "Hello from Gemini"

This will call the LLMManager helper and write test.wav if successful.
"""

from __future__ import annotations

import argparse
import asyncio
import os
from pathlib import Path

from app.services.llm_manager import LLMManager


async def synthesize(text: str, voice: str, model: str, output: Path) -> None:
    os.environ.setdefault("GOOGLE_TTS_MODEL", model)

    manager = LLMManager()
    audio_bytes, _, _ = await manager._google_generate_tts_bytes(
        text,
        voice=voice,
        response_format="wav",
    )
    output.write_bytes(audio_bytes)


def main() -> None:
    parser = argparse.ArgumentParser(description="Gemini TTS smoke test")
    parser.add_argument("--api-key", required=True, help="Google Gemini API key")
    parser.add_argument(
        "--text", default="Hello from Gemini", help="Text to synthesize"
    )
    parser.add_argument("--voice", default="kore", help="Voice to use")
    parser.add_argument(
        "--model",
        default="gemini-2.5-flash-preview-tts",
        help="Gemini TTS model ID",
    )
    parser.add_argument(
        "--output", default="test.wav", help="Output WAV file path"
    )
    args = parser.parse_args()

    os.environ["GOOGLE_API_KEY"] = args.api_key

    output_path = Path(args.output)
    print(f"Synthesizing '{args.text}' with voice {args.voice} -> {output_path}")
    asyncio.run(synthesize(args.text, args.voice, args.model, output_path))
    print(f"Saved audio to {output_path.resolve()}")


if __name__ == "__main__":
    main()
