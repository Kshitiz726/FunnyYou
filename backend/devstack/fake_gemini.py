"""A stand-in for Gemini's generateContent image endpoint.

Speaks the exact request and response shape of the real API, so
`app/preview_service.py` runs unmodified against it — same auth header, same
`inline_data` face upload, same `candidates[].content.parts[].inlineData`
response. Point the stack at it with GEMINI_BASE_URL.

This exists so the preview path can be proven end to end without burning free
quota, and so the app is demoable before anyone has a key. It is not an AI: it
composites the real uploaded face onto a scenario card.
"""

from __future__ import annotations

import asyncio
import base64
import random
import re

from fastapi import FastAPI, Header, HTTPException, Request

from .media import preview_jpeg, scenario_label

app = FastAPI(title="Fake Gemini")

# Nonzero so the app's progressive batch fill is actually visible; the real API
# takes 3-8s per image and a fake that returns instantly hides pacing bugs.
LATENCY_S = (0.4, 1.2)

# Set >0 to exercise the partial-failure path — the free tier really does
# rate-limit mid-batch, and generate_batch is built to survive it.
FAILURE_RATE = 0.0


def _scenario(prompt: str) -> str:
    """Recover a short label from the instruction the service sends."""
    match = re.search(r"in this scene: (.+?)\. Keep their face", prompt, re.S)
    return scenario_label(match.group(1) if match else prompt)


@app.get("/health")
async def health() -> dict:
    return {"ok": True, "service": "fake-gemini"}


@app.post("/models/{model}:generateContent")
async def generate(
    model: str,
    request: Request,
    x_goog_api_key: str | None = Header(default=None),
) -> dict:
    if not x_goog_api_key:
        raise HTTPException(status_code=401, detail="Missing x-goog-api-key")

    body = await request.json()
    parts = body.get("contents", [{}])[0].get("parts", [])

    prompt = next((p["text"] for p in parts if "text" in p), "")
    blob = next((p["inline_data"] for p in parts if "inline_data" in p), None)
    if blob is None:
        raise HTTPException(status_code=400, detail="No inline_data image supplied")

    await asyncio.sleep(random.uniform(*LATENCY_S))

    if FAILURE_RATE and random.random() < FAILURE_RATE:
        raise HTTPException(status_code=429, detail="Quota exceeded (simulated)")

    face = base64.b64decode(blob["data"])
    image = preview_jpeg(face, _scenario(prompt))

    return {
        "candidates": [
            {
                "content": {
                    "role": "model",
                    "parts": [
                        {
                            "inlineData": {
                                "mimeType": "image/jpeg",
                                "data": base64.b64encode(image).decode(),
                            }
                        }
                    ],
                },
                "finishReason": "STOP",
            }
        ],
        "modelVersion": model,
    }
