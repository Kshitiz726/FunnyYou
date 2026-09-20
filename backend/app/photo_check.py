"""Does this selfie stand a chance of rendering well?

The app already reads exposure and focus off the pixels on the phone, which is
instant and works with no signal. What it cannot do there is find the face and
say which way it is pointing: that needs landmarks, and on the phone that means
ML Kit, a large native dependency and an iOS pod that raises the minimum iOS
version. The render box is already running InsightFace for the face swap, with
the detector and the 3D landmark model sat on disk, so the honest place to
answer "are you looking at the camera" is here.

Everything this returns is **advice**. A person is always allowed to keep the
photo they took. The only thing worth being firm about is a photo with no face
in it, because that one cannot produce a video at all.

The analyser is CPU-only on purpose. It is small, it runs in about a second,
and the GPU's memory is the scarce thing on this box -- see `comfy_client`.
"""

from __future__ import annotations

import logging
import math
import threading
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

# Beyond these the face is turned far enough that the swap starts to lose the
# customer's likeness. Tuned wide: the point is to catch someone in profile,
# not to nag a person whose head is slightly off square.
_MAX_YAW_DEG = 22.0
_MAX_PITCH_DEG = 22.0
_MAX_ROLL_DEG = 25.0

# The face's longest side as a fraction of the frame's shortest side. Under
# this there are too few pixels of face to swap cleanly.
_MIN_FACE_SHARE = 0.22

# Mirrors of the phone-side thresholds in `lib/features/capture/photo_quality.dart`.
# They are repeated rather than shared because the two run on different pixels:
# the phone reads a 96px thumbnail of the whole frame, this reads the full image.
_DARK_BELOW = 62.0
_BRIGHT_ABOVE = 218.0
_BLUR_BELOW = 3.6

# The pack ReActor already uses, so nothing new is ever downloaded.
_MODEL = "buffalo_l"


@dataclass(frozen=True)
class PhotoReport:
    """What the box made of a selfie."""

    face_count: int = 0
    # Degrees, None when the pose model did not run.
    yaw: float | None = None
    pitch: float | None = None
    roll: float | None = None
    brightness: float | None = None
    sharpness: float | None = None
    face_share: float | None = None
    issues: list[str] = field(default_factory=list)

    @property
    def usable(self) -> bool:
        """Whether a render is worth attempting at all."""
        return "no_face" not in self.issues

    def to_json(self) -> dict:
        return {
            "faceCount": self.face_count,
            "yaw": _round(self.yaw),
            "pitch": _round(self.pitch),
            "roll": _round(self.roll),
            "brightness": _round(self.brightness),
            "sharpness": _round(self.sharpness),
            "faceShare": _round(self.face_share),
            "issues": self.issues,
            "usable": self.usable,
        }


def _round(value: float | None) -> float | None:
    return None if value is None else round(float(value), 2)


class PhotoChecker:
    """Lazily-loaded InsightFace analyser.

    Loading costs a few hundred megabytes of host RAM and a couple of seconds,
    so it happens on the first selfie rather than at import. If it cannot load
    -- wrong pod, missing models, no onnxruntime -- every check falls back to
    the exposure and focus reading, which needs nothing but numpy. A photo
    check is not worth failing a request over.
    """

    def __init__(self, model_root: str | None = None, det_size: int = 640) -> None:
        self._model_root = model_root
        self._det_size = det_size
        self._app = None
        self._tried = False
        self._lock = threading.Lock()

    # -- model ------------------------------------------------------------
    @property
    def available(self) -> bool:
        return self._load() is not None

    def _load(self):
        if self._tried:
            return self._app
        with self._lock:
            if self._tried:
                return self._app
            self._tried = True
            if not self._model_root:
                log.info(
                    "Photo check: no InsightFace models found, reporting "
                    "exposure and focus only"
                )
                return None
            try:
                from insightface.app import FaceAnalysis

                analyser = FaceAnalysis(
                    name=_MODEL,
                    root=self._model_root,
                    providers=["CPUExecutionProvider"],
                    # Detection puts a box round the face, the 3D landmarks
                    # give the pose. Recognition and gender/age are the rest
                    # of the pack and would be several hundred megabytes of
                    # RAM loaded to answer a question nobody asked.
                    allowed_modules=["detection", "landmark_3d_68"],
                )
                analyser.prepare(ctx_id=-1, det_size=(self._det_size, self._det_size))
                self._app = analyser
                log.info("Photo check: InsightFace ready (CPU)")
            except Exception as exc:  # noqa: BLE001 - never break a request
                log.warning("Photo check: running without face detection (%r)", exc)
                self._app = None
            return self._app

    def warm(self) -> bool:
        """Load the models now, so the first person to take a selfie does not.

        Loading costs several seconds the first time. Paid on demand, that
        lands on somebody's very first photo -- long enough that the app gives
        up waiting and tells them the check "needs a connection", which is
        both wrong and the worst possible first impression of the feature.
        """
        return self._load() is not None

    # -- checking ---------------------------------------------------------
    def inspect(self, image: bytes) -> PhotoReport:
        """Read a JPEG or PNG and report what is wrong with it."""
        pixels = _decode(image)
        if pixels is None:
            # Undecodable is our problem, not the photographer's: say nothing.
            return PhotoReport()

        brightness, sharpness = _exposure_and_focus(pixels)
        issues: list[str] = []
        if brightness < _DARK_BELOW:
            issues.append("too_dark")
        elif brightness > _BRIGHT_ABOVE:
            issues.append("too_bright")
        if sharpness < _BLUR_BELOW:
            issues.append("blurry")

        analyser = self._load()
        if analyser is None:
            return PhotoReport(
                brightness=brightness, sharpness=sharpness, issues=issues
            )

        faces = _detect(analyser, pixels)
        if not faces:
            # Put this first: it is the one finding that means "this cannot
            # work", and the app shows the first issue it is given.
            return PhotoReport(
                brightness=brightness,
                sharpness=sharpness,
                issues=["no_face", *issues],
            )

        if len(faces) > 1:
            issues.insert(0, "many_faces")

        face = _largest(faces)
        yaw, pitch, roll = _pose(face)
        share = _face_share(face, pixels.shape)

        if share is not None and share < _MIN_FACE_SHARE:
            issues.insert(0, "too_far")
        if yaw is not None and abs(yaw) > _MAX_YAW_DEG:
            issues.insert(0, "turned")
        elif pitch is not None and abs(pitch) > _MAX_PITCH_DEG:
            issues.insert(0, "chin")
        elif roll is not None and abs(roll) > _MAX_ROLL_DEG:
            issues.insert(0, "tilted")

        return PhotoReport(
            face_count=len(faces),
            yaw=yaw,
            pitch=pitch,
            roll=roll,
            brightness=brightness,
            sharpness=sharpness,
            face_share=share,
            issues=issues,
        )


# -- pixel helpers --------------------------------------------------------


def _decode(image: bytes):
    """Bytes to an RGB numpy array, or None."""
    try:
        import io

        import numpy as np
        from PIL import Image

        with Image.open(io.BytesIO(image)) as handle:
            return np.asarray(handle.convert("RGB"))
    except Exception as exc:  # noqa: BLE001
        log.warning("Photo check: could not decode the upload (%r)", exc)
        return None


def _exposure_and_focus(pixels) -> tuple[float, float]:
    """Mean luma, and the mean absolute Laplacian, on a small grey copy.

    Downscaled to the same 96px the phone uses so the two readings mean the
    same thing and cannot disagree about the same photo.
    """
    import numpy as np

    luma = (
        0.299 * pixels[:, :, 0] + 0.587 * pixels[:, :, 1] + 0.114 * pixels[:, :, 2]
    ).astype("float32")

    height, width = luma.shape
    step = max(1, min(height, width) // 96)
    small = luma[::step, ::step]

    brightness = float(small.mean()) if small.size else 0.0
    if small.shape[0] < 3 or small.shape[1] < 3:
        return brightness, float("inf")

    middle = small[1:-1, 1:-1]
    response = (
        small[1:-1, :-2]
        + small[1:-1, 2:]
        + small[:-2, 1:-1]
        + small[2:, 1:-1]
        - 4 * middle
    )
    return brightness, float(np.abs(response).mean())


def _detect(analyser, pixels):
    """InsightFace wants BGR. Never let a detector failure fail the request."""
    try:
        return analyser.get(pixels[:, :, ::-1]) or []
    except Exception as exc:  # noqa: BLE001
        log.warning("Photo check: detection failed (%r)", exc)
        return []


def _largest(faces):
    def area(face) -> float:
        left, top, right, bottom = face.bbox
        return max(0.0, right - left) * max(0.0, bottom - top)

    return max(faces, key=area)


def _pose(face) -> tuple[float | None, float | None, float | None]:
    """Yaw, pitch and roll in degrees.

    `buffalo_l` carries the 3D landmark model, which gives a pose directly.
    When that model is missing InsightFace leaves `pose` unset, so fall back
    to the angle of the line between the eyes -- that still catches a head
    tilted far enough to matter, which is the most common of the three.
    """
    pose = getattr(face, "pose", None)
    if pose is not None and len(pose) == 3:
        pitch, yaw, roll = (float(v) for v in pose)
        return yaw, pitch, roll

    landmarks = getattr(face, "kps", None)
    if landmarks is None or len(landmarks) < 2:
        return None, None, None
    (lx, ly), (rx, ry) = landmarks[0][:2], landmarks[1][:2]
    roll = math.degrees(math.atan2(float(ry - ly), float(rx - lx)))
    return None, None, roll


def _face_share(face, shape) -> float | None:
    height, width = shape[0], shape[1]
    reference = min(height, width)
    if reference <= 0:
        return None
    left, top, right, bottom = (float(v) for v in face.bbox)
    return max(right - left, bottom - top) / reference


def find_models(configured: str = "") -> str | None:
    """The first place that actually holds the model pack, or None.

    Handed a root it does not have, InsightFace helpfully *downloads* 280 MB
    rather than failing -- onto a volume with a 60 GB quota, in the middle of
    somebody's first selfie. So the directory is confirmed before the library
    is ever told about it, and finding nothing turns the face half of the
    check off rather than reaching for the network.

    InsightFace expects `<root>/models/<name>`, so the root is the folder
    *above* `models`.
    """
    candidates = [
        configured,
        # Where ComfyUI's ReActor keeps them on the pod.
        "/workspace/ComfyUI/models/insightface",
        str(Path.home() / ".insightface"),
    ]
    for candidate in candidates:
        if candidate and (Path(candidate) / "models" / _MODEL).is_dir():
            return candidate
    return None


def build_checker(settings) -> PhotoChecker:
    """Point the analyser at the models ComfyUI already downloaded."""
    return PhotoChecker(
        model_root=find_models(getattr(settings, "insightface_root", "") or "")
    )
