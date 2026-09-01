"""Describe the customer's facial hair and hair colour, from their photo.

Wan Animate will not reliably carry these across on its own. Left to itself it
renders whatever the *template* character has -- an old pirate's grey hair and
full grey beard -- onto a clean-shaven young customer, because the scene prior
is strong and the reference image is only one conditioning signal among several.

The positive prompt is the lever that does work (the distill LoRA pins cfg to
1.0, which disables the negative prompt entirely, but positive conditioning is
still honoured). So this reads the reference photo and produces a short phrase
to drop into the prompt.

It has to be derived, never hardcoded: "clean-shaven" is right for one customer
and actively wrong for the next. The rule is that the render matches the photo.

Every phrase it returns is stated POSITIVELY. The distill LoRA pins cfg to 1.0,
so there is no negative branch to cancel anything: writing "no beard" simply puts
the token "beard" into the conditioning, and measurably produced a HEAVIER beard
than saying nothing. Describe the skin that is there, never the hair that is not.

Method: locate the face, then compare the moustache, chin and jaw regions
against a clean skin patch from the upper cheeks. Facial hair is darker and
more textured than the skin beside it, and both differences survive changes in
lighting and skin tone better than an absolute threshold would.
"""
from __future__ import annotations

import sys

import cv2
import numpy as np

# How much darker than cheek skin a region must be before it counts as hair.
# Tuned so ordinary shadow under the lip does not read as a moustache.
_DARK_STUBBLE = 0.90
_DARK_LIGHT = 0.82
_DARK_FULL = 0.72


def _median(gray, cx, cy, half_w, half_h):
    """Median intensity of a box centred on a landmark-derived point."""
    a, b = int(cy - half_h), int(cy + half_h)
    c, d = int(cx - half_w), int(cx + half_w)
    a, b = max(a, 0), min(b, gray.shape[0])
    c, d = max(c, 0), min(d, gray.shape[1])
    if b <= a or d <= c:
        return 0.0
    return float(np.median(gray[a:b, c:d]))


def describe(image_path: str) -> dict:
    from insightface.app import FaceAnalysis

    app = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
    app.prepare(ctx_id=-1, det_size=(640, 640))
    img = cv2.imread(image_path)
    if img is None:
        raise SystemExit(f"cannot read {image_path}")
    faces = app.get(img)
    if not faces:
        raise SystemExit("no face found in the reference photo")
    face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))

    # Five landmarks: both eyes, nose tip, both mouth corners. Anchoring to
    # these instead of fractions of the box is what stops the moustache patch
    # sliding onto the lips, which read brighter than skin and made a
    # moustached face score as clean-shaven.
    kps = np.asarray(face.kps, dtype=np.float32)
    eye_l, eye_r, nose, mouth_l, mouth_r = kps
    mouth = (mouth_l + mouth_r) / 2.0
    mouth_w = float(np.linalg.norm(mouth_r - mouth_l))
    eye_span = float(np.linalg.norm(eye_r - eye_l))
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)

    # Bare-skin baseline: the cheek, out to the side and below the eye.
    cheek_x = (eye_l[0] + nose[0]) / 2.0
    cheek_y = (eye_l[1] + nose[1]) / 2.0
    skin = max(_median(gray, cheek_x, cheek_y, eye_span * 0.18, eye_span * 0.16), 1.0)

    # Moustache: the strip between the nose tip and the mouth line.
    mo_y = nose[1] + (mouth[1] - nose[1]) * 0.55
    moustache = _median(gray, mouth[0], mo_y, mouth_w * 0.34, mouth_w * 0.13)

    # Chin: below the mouth by roughly the nose-to-mouth distance.
    drop = max(mouth[1] - nose[1], eye_span * 0.35)
    chin = _median(gray, mouth[0], mouth[1] + drop * 1.15, mouth_w * 0.30, drop * 0.35)

    # Jaw: out to the side at mouth height, where a beard would sit.
    jaw_x = mouth_l[0] - mouth_w * 0.45
    jaw = _median(gray, jaw_x, mouth[1] + drop * 0.55, mouth_w * 0.20, drop * 0.35)

    ratios = {"moustache": moustache / skin, "chin": chin / skin, "jaw": jaw / skin}
    beard_zone = min(ratios["chin"], ratios["jaw"])

    if beard_zone < _DARK_FULL:
        beard = "a full thick beard"
    elif beard_zone < _DARK_LIGHT:
        beard = "a short trimmed beard"
    elif beard_zone < _DARK_STUBBLE:
        beard = "light stubble on the jaw"
    else:
        beard = "smooth bare cheeks and a smooth bare chin"

    if ratios["moustache"] < _DARK_STUBBLE:
        if beard.startswith("clean-shaven"):
            beard = ("a thin moustache, smooth bare cheeks and a smooth "
                     "bare chin")
        elif "stubble" in beard:
            beard = "a thin moustache and light stubble, smooth bare chin"

    # Hair colour, sampled above the brow. The median of that patch is useless
    # because it also catches forehead and background, which dragged genuinely
    # black hair up into "brown"; the darkest 40% of the patch is the hair
    # itself.
    hx, hy = (eye_l[0] + eye_r[0]) / 2.0, eye_l[1] - eye_span * 0.95
    a, b = max(int(hy - eye_span * 0.22), 0), int(hy + eye_span * 0.22)
    c, d = max(int(hx - eye_span * 0.55), 0), int(hx + eye_span * 0.55)
    region = gray[a:b, c:d]
    if region.size:
        flat = np.sort(region.flatten())
        hair_v = float(flat[: max(1, int(len(flat) * 0.4))].mean())
    else:
        hair_v = 255.0
    if hair_v < 85:
        hair = "short black hair"
    elif hair_v < 125:
        hair = "short dark brown hair"
    else:
        hair = "short light brown hair"

    return {"beard": beard, "hair": hair, "ratios": ratios, "skin": skin}


if __name__ == "__main__":
    for path in sys.argv[1:]:
        d = describe(path)
        r = d["ratios"]
        print(f"{path}")
        print(f"  moustache/skin {r['moustache']:.2f}  chin/skin {r['chin']:.2f}  "
              f"jaw/skin {r['jaw']:.2f}")
        print(f"  -> {d['hair']}, {d['beard']}")
