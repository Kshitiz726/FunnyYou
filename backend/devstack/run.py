"""Boot the whole stack locally: fake ComfyUI, fake Gemini, and the real API.

    python -m devstack.run

Everything in `app/` runs exactly as it would in production — same HTTP calls,
same websocket, same workflow binding. Only the two things that need a GPU or a
paid key are stood in for.

Point either half at the real service by exporting the corresponding variable
before starting; the stack leaves it alone if it is already set:

    GEMINI_API_KEY=<real key>   with GEMINI_BASE_URL unset -> real previews
    COMFY_URL=http://<pod>:8188                            -> real renders
"""

from __future__ import annotations

import asyncio
import os
import socket

import uvicorn

FAKE_COMFY_PORT = 8188
FAKE_GEMINI_PORT = 8199
API_PORT = 8000


def _lan_ip() -> str:
    """The address a phone on the same wifi can reach this machine on."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


def _configure() -> tuple[str, str]:
    """Route each half at a real vendor if it is configured, else at a fake.

    Returns the human-readable description of what each half ended up on.
    """
    pollinations = bool(os.environ.get("POLLINATIONS_API_KEY"))

    # ── previews ──────────────────────────────────────────────────────────
    if os.environ.get("PREVIEW_PROVIDER") == "pollinations" or (
        pollinations and not os.environ.get("GEMINI_API_KEY")
    ):
        os.environ["PREVIEW_PROVIDER"] = "pollinations"
        previews = f"REAL Pollinations ({os.environ.get('POLLINATIONS_IMAGE_MODEL', 'nanobanana')})"
    elif os.environ.get("GEMINI_API_KEY") and not os.environ.get("GEMINI_BASE_URL"):
        os.environ["PREVIEW_PROVIDER"] = "gemini"
        previews = "REAL Gemini (free tier)"
    else:
        os.environ["PREVIEW_PROVIDER"] = "gemini"
        os.environ.setdefault("GEMINI_API_KEY", "devstack-local-key")
        os.environ["GEMINI_BASE_URL"] = f"http://127.0.0.1:{FAKE_GEMINI_PORT}"
        previews = "fake (real jpeg, no quota used)"

    # ── video ─────────────────────────────────────────────────────────────
    if os.environ.get("VIDEO_PROVIDER") == "pollinations" or (
        pollinations and not os.environ.get("COMFY_URL")
    ):
        os.environ["VIDEO_PROVIDER"] = "pollinations"
        video = f"REAL Pollinations ({os.environ.get('POLLINATIONS_VIDEO_MODEL', 'wan-fast')})"
    elif os.environ.get("COMFY_URL"):
        os.environ["VIDEO_PROVIDER"] = "comfy"
        video = f"REAL ComfyUI at {os.environ['COMFY_URL']}"
    else:
        os.environ["VIDEO_PROVIDER"] = "comfy"
        os.environ["COMFY_URL"] = f"http://127.0.0.1:{FAKE_COMFY_PORT}"
        video = "fake (real playable mp4, no GPU)"

    os.environ.setdefault("OUTPUT_DIR", "./data/outputs")
    os.environ.setdefault("COMFY_WORKFLOW", "wan22_animate.json")
    return previews, video


async def _serve(target: str, port: int, name: str) -> None:
    config = uvicorn.Config(target, host="0.0.0.0", port=port, log_level="warning")
    await uvicorn.Server(config).serve()
    raise RuntimeError(f"{name} exited")


async def main() -> None:
    previews, video = _configure()

    # Read after _configure so app.config sees the final environment.
    ip = _lan_ip()
    os.environ.setdefault("PUBLIC_BASE_URL", f"http://{ip}:{API_PORT}")

    servers = [_serve("app.main:app", API_PORT, "API")]
    if "fake" in video:
        servers.append(_serve("devstack.fake_comfy:app", FAKE_COMFY_PORT, "ComfyUI"))
    if "fake" in previews:
        servers.append(_serve("devstack.fake_gemini:app", FAKE_GEMINI_PORT, "Gemini"))

    print("\n  Funny You dev stack")
    print(f"    API       http://{ip}:{API_PORT}   /v1/health")
    print(f"    previews  {previews}")
    print(f"    video     {video}")
    if "fake" in previews or "fake" in video:
        print("\n    Swap a fake for the real thing - no code change:")
        if "fake" in previews:
            print("      GEMINI_API_KEY=...        free, no card, ~500 img/day")
        if "fake" in video:
            print("      POLLINATIONS_API_KEY=...  hosted wan/seedance/veo")
            print("      COMFY_URL=http://<pod>:8188   your own GPU")
    print("\n  Run the app against it:\n")
    print("    flutter run \\")
    print("      --dart-define=API_BASE_URL=http://10.0.2.2:8000      # Android emulator")
    print(f"      # a real phone on this wifi uses http://{ip}:{API_PORT}\n")

    await asyncio.gather(*servers)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
