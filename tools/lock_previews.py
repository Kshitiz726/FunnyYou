"""Turn a scenario's clip into the locked preview the app shows before you pay.

The client's ask, in his words: "show the preview of the video without their
face ... blacked out with a locked icon over the face". He offered to do it by
hand in After Effects. This does it from the footage instead, so all of them
are done in one pass, every scenario gets an identical treatment, and it can be
re-run for free whenever a clip changes or a scenario is added.

The face is found with the same detector the render box uses (InsightFace
buffalo_l), so a face this agrees is there is a face the pipeline would also
have swapped.

Three things matter more than the detection itself:

* **A miss must not flash.** A single frame where the detector fails would
  uncover the face for 1/24th of a second, which is exactly long enough to see.
  So gaps are filled by interpolating between the detections on either side,
  and the box is only ever dropped if the face is missing for a long run.
* **The box must not jitter.** Raw per-frame boxes wobble by several pixels
  even on a still head. A rolling mean over [_SMOOTH] frames settles it.
* **It must cover more than the detector claims.** The returned box is tight to
  the features; hair, chin and ears sit outside it. [_PAD] grows it so the
  person genuinely cannot be identified.

Usage:
    python tools/lock_previews.py                  # every clip
    python tools/lock_previews.py gym karaoke      # just these
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

# Where the client's source clips live, and where the app expects the result.
SRC = Path.home() / "Downloads" / "funny_you"
DST = Path(__file__).resolve().parent.parent / "assets" / "locked_previews"
CACHE = Path(__file__).resolve().parent / ".detections"

# Grow the detector's box by this fraction of its size, per side. The box is
# tight to the eyes/nose/mouth; hair and chin fall outside it.
_PAD = 0.52

# Frames of rolling mean. ~0.4s at 24fps: enough to kill the wobble, short
# enough that the box still keeps up with a head that actually moves.
_SMOOTH = 9

# Longer than this with no face and we accept there is no face to cover
# (the subject turned away, or left frame) rather than parking a black box
# over empty scenery.
_MAX_GAP = 36

# Downscale for bundling. The app shows these in a phone-width card, so the
# source 464x688 is already more than needed and the file size is what matters.
_WIDTH = 360

# Encoding goes through ffmpeg rather than OpenCV's writer.
#
# OpenCV gives no bitrate control, and its H.264 default produced 6 MB for a
# 10 second clip -- worse than its own MPEG-4, and ~30 MB of app bundle across
# five scenarios. ffmpeg at CRF 28 lands the same clips around 300 KB.
#
# mp4v is not an option regardless of size: it is MPEG-4 Part 2, which iOS
# will not reliably decode, so the preview would never play there.
_CRF = "28"
_PRESET = "slow"      # one-off build step, so trade time for size


def _ffmpeg() -> str:
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def _detector():
    from insightface.app import FaceAnalysis

    app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection"])
    app.prepare(ctx_id=-1, det_size=(640, 640))
    return app


def _detect(app, frames: list[np.ndarray]) -> list[tuple[float, ...] | None]:
    """The largest face per frame, or None where nothing was found."""
    boxes: list[tuple[float, ...] | None] = []
    for i, frame in enumerate(frames):
        faces = app.get(frame)
        if not faces:
            boxes.append(None)
        else:
            # Largest by area: these clips have bystanders, and the subject is
            # always the closest person to camera.
            face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
            boxes.append(tuple(float(v) for v in face.bbox))
        if i % 40 == 0:
            print(f"    frame {i}/{len(frames)}", flush=True)
    return boxes


def _fill_gaps(boxes: list[tuple[float, ...] | None]) -> list[tuple[float, ...] | None]:
    """Interpolate short runs of misses; leave long ones uncovered."""
    out = list(boxes)
    n = len(out)
    i = 0
    while i < n:
        if out[i] is not None:
            i += 1
            continue
        start = i
        while i < n and out[i] is None:
            i += 1
        end = i                       # first index after the gap
        before = out[start - 1] if start > 0 else None
        after = out[end] if end < n else None
        length = end - start

        if length > _MAX_GAP:
            continue                  # genuinely no face here
        if before is None and after is None:
            continue
        if before is None:
            for k in range(start, end):
                out[k] = after
        elif after is None:
            for k in range(start, end):
                out[k] = before
        else:
            for k in range(start, end):
                t = (k - start + 1) / (length + 1)
                out[k] = tuple(b + (a - b) * t for b, a in zip(before, after))
    return out


def _smooth(boxes: list[tuple[float, ...] | None]) -> list[tuple[float, ...] | None]:
    """Rolling mean over the frames that have a box, so it stops shaking."""
    out: list[tuple[float, ...] | None] = []
    half = _SMOOTH // 2
    for i, box in enumerate(boxes):
        if box is None:
            out.append(None)
            continue
        window = [b for b in boxes[max(0, i - half): i + half + 1] if b is not None]
        out.append(tuple(float(np.mean([w[j] for w in window])) for j in range(4)))
    return out


# The lock is drawn to the size of the covered box, but never larger than this
# fraction of the frame height. Without the cap a close-up (hello) produced a
# padlock filling half the screen: technically correct, visually daft.
#
# A cap rather than a ratio, so the badge comes out roughly the same size in
# every clip. Scaling it down proportionally instead would have left it tiny
# in the clips where the face is small and far away.
_LOCK_MAX_OF_FRAME = 0.17


def _draw_lock(frame: np.ndarray, cx: int, cy: int, size: int) -> None:
    """A padlock, centred on the covered face, drawn rather than loaded.

    Keeping it as geometry means there is no asset to ship or keep in sync,
    and it scales exactly with whatever the face size turns out to be.
    """
    body_w, body_h = int(size * 0.52), int(size * 0.42)
    x0, y0 = cx - body_w // 2, cy - body_h // 4
    r = max(2, size // 22)

    # shackle
    shackle_r = int(body_w * 0.32)
    cv2.ellipse(frame, (cx, y0), (shackle_r, shackle_r),
                0, 180, 360, (255, 255, 255), max(2, size // 16), cv2.LINE_AA)
    # body
    cv2.rectangle(frame, (x0, y0), (x0 + body_w, y0 + body_h),
                  (255, 255, 255), -1, cv2.LINE_AA)
    # keyhole, punched back out in the box colour
    cv2.circle(frame, (cx, y0 + body_h // 2), max(2, body_w // 9), (18, 18, 18), -1, cv2.LINE_AA)
    _ = r


def _cover(frame: np.ndarray, box: tuple[float, ...]) -> None:
    x1, y1, x2, y2 = box
    w, h = x2 - x1, y2 - y1
    x1 -= w * _PAD; x2 += w * _PAD
    y1 -= h * _PAD; y2 += h * _PAD

    H, W = frame.shape[:2]
    x1, y1 = max(0, int(x1)), max(0, int(y1))
    x2, y2 = min(W, int(x2)), min(H, int(y2))
    if x2 <= x1 or y2 <= y1:
        return

    # Rounded black panel. An ellipse reads as "blurred out"; a hard rectangle
    # reads as deliberate, which is what a lock needs to look like.
    cv2.rectangle(frame, (x1, y1), (x2, y2), (18, 18, 18), -1, cv2.LINE_AA)
    lock = min(min(x2 - x1, y2 - y1), int(H * _LOCK_MAX_OF_FRAME))
    _draw_lock(frame, (x1 + x2) // 2, (y1 + y2) // 2, max(16, lock))


def build(stem: str, app) -> None:
    src = SRC / f"{stem}.mp4"
    if not src.exists():
        print(f"  !! {src} missing, skipped")
        return

    cap = cv2.VideoCapture(str(src))
    fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    if not frames:
        print(f"  !! {stem}: no frames")
        return

    # Detection is the slow part (CPU inference, minutes per clip) and it does
    # not change when the drawing does. Cache it so tuning the look is instant.
    cache = CACHE / f"{stem}.json"
    if cache.exists():
        raw = [tuple(b) if b else None for b in json.loads(cache.read_text())]
        print(f"  {stem}: {len(frames)} frames, reusing cached detection")
    else:
        print(f"  {stem}: {len(frames)} frames, detecting")
        raw = _detect(app(), frames)
        CACHE.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps([list(b) if b else None for b in raw]))
    boxes = _smooth(_fill_gaps(raw))
    found = sum(b is not None for b in boxes)
    print(f"  {stem}: face covered on {found}/{len(frames)} frames")

    h, w = frames[0].shape[:2]
    out_w = _WIDTH
    out_h = int(round(h * out_w / w)) // 2 * 2

    DST.mkdir(parents=True, exist_ok=True)
    out = DST / f"{stem}.mp4"

    proc = subprocess.Popen(
        [
            _ffmpeg(), "-y", "-loglevel", "error",
            "-f", "rawvideo", "-pix_fmt", "bgr24",
            "-s", f"{out_w}x{out_h}", "-r", f"{fps}",
            "-i", "-",
            "-an",                                  # silent: the app mutes it anyway
            "-c:v", "libx264", "-preset", _PRESET, "-crf", _CRF,
            "-pix_fmt", "yuv420p",                  # required by mobile decoders
            "-movflags", "+faststart",              # first frame without the whole file
            str(out),
        ],
        stdin=subprocess.PIPE,
    )
    assert proc.stdin is not None
    for frame, box in zip(frames, boxes):
        if box is not None:
            _cover(frame, box)
        small = cv2.resize(frame, (out_w, out_h), interpolation=cv2.INTER_AREA)
        proc.stdin.write(small.tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        print(f"  !! {stem}: ffmpeg failed")
        return

    kb = out.stat().st_size / 1024
    print(f"  {stem}: wrote {out.name}  {out_w}x{out_h}  {kb:.0f} KB")


def main() -> int:
    wanted = sys.argv[1:] or [p.stem for p in sorted(SRC.glob("*.mp4"))]
    if not wanted:
        print(f"No clips in {SRC}")
        return 1
    # Built on first use: a run that is entirely cached never pays for it.
    holder: list = []

    def app():
        if not holder:
            print("Loading the detector (same one the render box uses)")
            holder.append(_detector())
        return holder[0]

    for stem in wanted:
        build(stem, app)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
