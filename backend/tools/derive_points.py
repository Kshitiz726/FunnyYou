"""Derive SAM seed points for a new template from its own pose keypoints.

The whole point of this file is that adding a template should not mean sitting in
the ComfyUI graph clicking on someone's face. Drop `<id>.mp4` in backend/templates,
run this, and you get `<id>.points.json` shaped like the ones authored by hand.

The rules encoded here were learned the expensive way (see the notes in
pirate.points.json): the mask has to swallow the template character's *entire*
head including all facial hair, because anything left outside is a boundary Wan
has to blend into -- and it will happily grow a beard on a clean-shaven reference
to make that blend work. It must equally stay off the hat and the coat, or the
costume gets re-imagined.
"""
from __future__ import annotations

import argparse
import json
import time
import urllib.request
from pathlib import Path

# DWPose emits the 68-point facial landmark set. These are the only indices we
# need, and naming them beats decoding magic numbers at the call site.
JAW_LINE = range(0, 17)
CHIN = 8
BROW_L, BROW_R = 17, 26
NOSE_TIP = 30


def _post(url: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{url}/prompt",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    return json.load(urllib.request.urlopen(req))


def probe_graph(video: str, width: int, height: int, prefix: str) -> dict:
    """A four-node graph: one frame in, one keypoint file out. Runs in ~5s."""
    return {
        "1": {"class_type": "VHS_LoadVideo", "inputs": {
            "video": video, "force_rate": 16, "custom_width": 0, "custom_height": 0,
            "frame_load_cap": 1, "skip_first_frames": 0, "select_every_nth": 1,
            "format": "AnimateDiff"}},
        "2": {"class_type": "ImageScale", "inputs": {
            "image": ["1", 0], "width": width, "height": height,
            "upscale_method": "lanczos", "crop": "center"}},
        "3": {"class_type": "DWPreprocessor", "inputs": {
            "image": ["2", 0], "detect_hand": "disable", "detect_body": "enable",
            "detect_face": "enable", "resolution": max(width, height),
            "bbox_detector": "yolox_l.onnx",
            "pose_estimator": "dw-ll_ucoco_384_bs5.torchscript.pt",
            "scale_stick_for_xinsr_cn": "disable"}},
        "4": {"class_type": "SavePoseKpsAsJsonFile", "inputs": {
            "pose_kps": ["3", 1], "filename_prefix": prefix}},
    }


def _canvas(frame: dict) -> tuple[float, float]:
    return float(frame.get("canvas_width") or 1), float(frame.get("canvas_height") or 1)


def _face_points(frame: dict) -> list[tuple[float, float]]:
    people = frame.get("people") or []
    if not people:
        raise SystemExit("no person found in the first frame -- is the subject visible?")
    face = people[0].get("face_keypoints_2d") or []
    if len(face) < 68 * 3:
        raise SystemExit("no facial landmarks -- the face is too small or turned away")
    return [(face[i * 3], face[i * 3 + 1]) for i in range(68)]


def derive(frame: dict) -> dict:
    """Turn 68 facial landmarks into the positive/negative seeds SAM needs."""
    cw, ch = _canvas(frame)
    pts = _face_points(frame)
    is_norm = max(x for x, _ in pts) <= 1.5          # DWPose may hand back 0..1
    scale_x, scale_y = (cw, ch) if is_norm else (1.0, 1.0)
    pts = [(x * scale_x, y * scale_y) for x, y in pts]

    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    left, right, top, bottom = min(xs), max(xs), min(ys), max(ys)
    face_w, face_h = right - left, bottom - top
    cx = (left + right) / 2
    chin_x, chin_y = pts[CHIN]
    brow_y = min(pts[BROW_L][1], pts[BROW_R][1])

    positive = [
        pts[NOSE_TIP],                                   # face
        (cx, brow_y - face_h * 0.45),                    # hair above the brow
        (cx - face_w * 0.42, (brow_y + chin_y) / 2),     # cheek / side hair
        (chin_x, chin_y - face_h * 0.10),                # jaw
        (chin_x, chin_y + face_h * 0.14),                # beard: below the chin
    ]
    # Everything the mask must NOT touch. The two just below the chin are what
    # keep the collar and coat as the template filmed them.
    negative = [
        (cx, chin_y + face_h * 0.95),                    # chest
        (cx - face_w * 1.3, chin_y + face_h * 1.2),      # coat, left
        (cx + face_w * 1.3, chin_y + face_h * 1.2),      # coat, right
        (cx, chin_y + face_h * 1.9),                     # lower body
        (cw * 0.06, ch * 0.05),                          # background corners
        (cw * 0.94, ch * 0.05),
        (cx, brow_y - face_h * 1.05),                    # hat / above the head
    ]
    clamp = lambda v, hi: max(0.0, min(float(v), hi))
    to_norm = lambda p: {"x": round(clamp(p[0], cw) / cw, 4),
                         "y": round(clamp(p[1], ch) / ch, 4)}
    return {
        "_comment": (
            "Auto-derived by backend/tools/derive_points.py from the template's own pose "
            "keypoints. Positives cover face, hair and the whole beard; negatives hold the "
            "hat, collar, coat and background out. Normalised 0..1. Check it with "
            "--preview before trusting it on a 13-minute render."),
        "positive": [to_norm(p) for p in positive],
        "negative": [to_norm(p) for p in negative],
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("template", help="template id, e.g. 'pirate' (expects <id>.mp4 in ComfyUI input)")
    ap.add_argument("--url", default="http://127.0.0.1:8188")
    ap.add_argument("--width", type=int, default=720)
    ap.add_argument("--height", type=int, default=1248)
    ap.add_argument("--kps", help="read a previously saved keypoint json instead of probing")
    ap.add_argument("--out", help="where to write the points file")
    args = ap.parse_args()

    if args.kps:
        raw = json.loads(Path(args.kps).read_text(encoding="utf-8"))
    else:
        prefix = f"kps_{args.template}"
        _post(args.url, {"prompt": probe_graph(f"{args.template}.mp4", args.width, args.height, prefix)})
        raise SystemExit("queued the pose probe; re-run with --kps <saved json> once it lands")

    frame = raw[0] if isinstance(raw, list) else raw
    points = derive(frame)
    out = Path(args.out or f"backend/templates/{args.template}.points.json")
    out.write_text(json.dumps(points, indent=2), encoding="utf-8")
    print(f"wrote {out}: {len(points['positive'])} positive, {len(points['negative'])} negative")


if __name__ == "__main__":
    main()
