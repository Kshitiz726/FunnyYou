"""Onboard template clips: point this at a directory and walk away.

    python backend/tools/add_template.py path/to/new_clips --url http://127.0.0.1:8188

For every video it finds, this copies the clip into backend/templates/, uploads
it to ComfyUI, runs a pose probe on the first frame, derives the SAM seed points
from the resulting facial landmarks, and writes the `<id>.points.json` sidecar.

That sidecar is the gate: `TemplateLibrary.available(require_points=True)` only
offers clips that have one, so a clip lands in the app as renderable the moment
this finishes -- and stays marked "Soon" if the probe could not find a face,
which is the honest outcome rather than a render that silently targets the
background.

The template id comes from the filename, and it has to match an id in
lib/data/templates.dart or the app has no card to show it on.
"""
from __future__ import annotations

import argparse
import json
import shutil
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

from derive_points import derive, probe_graph

VIDEO_SUFFIXES = {".mp4", ".webm", ".mov", ".mkv"}
TEMPLATE_DIR = Path("backend/templates")
CATALOG = Path("lib/data/templates.dart")


def _api(url: str, path: str) -> dict:
    with urllib.request.urlopen(f"{url}{path}") as response:
        return json.load(response)


def _queue(url: str, graph: dict) -> str:
    request = urllib.request.Request(
        f"{url}/prompt",
        data=json.dumps({"prompt": graph}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request) as response:
        body = json.load(response)
    if body.get("node_errors"):
        raise RuntimeError(f"ComfyUI rejected the probe: {body['node_errors']}")
    return body["prompt_id"]


def _upload(url: str, clip: Path) -> None:
    """Push the clip into ComfyUI's *input* folder -- VHS_LoadVideo reads only
    from there, never from output."""
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="image"; filename="{clip.name}"\r\n'.encode(),
        b"Content-Type: application/octet-stream\r\n\r\n",
        clip.read_bytes(),
        f"\r\n--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n',
        f"--{boundary}--\r\n".encode(),
    ])
    request = urllib.request.Request(
        f"{url}/upload/image", data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    urllib.request.urlopen(request).read()


def _await(url: str, prompt_id: str, timeout: float = 300.0) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        history = _api(url, f"/history/{prompt_id}")
        entry = history.get(prompt_id)
        if entry:
            status = (entry.get("status") or {}).get("status_str")
            if status == "error":
                raise RuntimeError(f"pose probe failed: {entry.get('status')}")
            if entry.get("status", {}).get("completed"):
                return entry
        time.sleep(2)
    raise TimeoutError("pose probe did not finish in time")


def _read_kps(url: str, entry: dict) -> dict:
    """SavePoseKpsAsJsonFile reports no outputs, so find the file it wrote."""
    for output in (entry.get("outputs") or {}).values():
        for item in output.get("json") or output.get("text") or []:
            if isinstance(item, dict) and item.get("filename"):
                query = urllib.parse.urlencode({
                    "filename": item["filename"], "type": item.get("type", "output"),
                    "subfolder": item.get("subfolder", "")})
                with urllib.request.urlopen(f"{url}/view?{query}") as response:
                    return json.load(response)
    raise RuntimeError("the probe produced no keypoint file")


def catalog_ids() -> set[str]:
    if not CATALOG.is_file():
        return set()
    import re
    return set(re.findall(r"id:\s*'([^']+)'", CATALOG.read_text(encoding="utf-8")))


def onboard(clip: Path, url: str, width: int, height: int, kps_dir: Path | None) -> str:
    template_id = clip.stem
    TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
    destination = TEMPLATE_DIR / f"{template_id}{clip.suffix.lower()}"
    if clip.resolve() != destination.resolve():
        shutil.copy2(clip, destination)

    _upload(url, destination)
    prefix = f"kps_{template_id}"
    entry = _await(url, _queue(url, probe_graph(destination.name, width, height, prefix)))
    raw = _read_kps(url, entry)
    frame = raw[0] if isinstance(raw, list) else raw
    if kps_dir:
        kps_dir.mkdir(parents=True, exist_ok=True)
        (kps_dir / f"{template_id}.kps.json").write_text(json.dumps(raw)[:2_000_000], encoding="utf-8")

    points = derive(frame)
    sidecar = TEMPLATE_DIR / f"{template_id}.points.json"
    sidecar.write_text(json.dumps(points, indent=2), encoding="utf-8")
    return template_id


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", help="a video file, or a directory of them")
    parser.add_argument("--url", default="http://127.0.0.1:8188")
    parser.add_argument("--width", type=int, default=720)
    parser.add_argument("--height", type=int, default=1248)
    parser.add_argument("--kps-dir", type=Path, help="also keep the raw keypoints, for debugging")
    args = parser.parse_args()

    source = Path(args.source)
    clips = ([source] if source.is_file()
             else sorted(p for p in source.iterdir() if p.suffix.lower() in VIDEO_SUFFIXES))
    if not clips:
        raise SystemExit(f"no video files found in {source}")

    known = catalog_ids()
    done, failed = [], []
    for clip in clips:
        try:
            template_id = onboard(clip, args.url, args.width, args.height, args.kps_dir)
        except Exception as exc:                       # one bad clip must not stop the batch
            failed.append((clip.name, str(exc)))
            print(f"  FAILED {clip.name}: {exc}")
            continue
        done.append(template_id)
        note = "" if template_id in known else "  <-- no card in lib/data/templates.dart yet"
        print(f"  ok  {template_id}{note}")

    print(f"\n{len(done)} template(s) ready, {len(failed)} failed")
    if done:
        print("Restart the backend (or just re-request /health) and they appear as renderable.")


if __name__ == "__main__":
    main()
