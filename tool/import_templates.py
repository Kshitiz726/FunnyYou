"""Import template artwork into assets/templates/ at the spec the app needs.

    python tool/import_templates.py "C:/Users/Kshitiz/Downloads/Template"

Source art is square; the tiles are 3:4 with BoxFit.cover and the picker drops
the user's photo bubble over the upper third, so each image is cropped
face-aware: horizontally centred on the face, with the face sitting ~32% down.
Output is 900x1200 JPEG under 200KB, named after the template id.
"""
import sys, pathlib, re
import cv2, numpy as np
from PIL import Image
import insightface

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / "assets" / "templates"
OUT_W, OUT_H = 900, 1200
MAX_KB = 200
FACE_Y = 0.32          # where the face centre should land, top-down
FACE_W_TARGET = 0.15   # face width as a share of tile width
MAX_ZOOM = 1.5         # never crop tighter than this, keeps the scene readable

# Source filenames are inconsistent; map them onto real template ids.
ALIASES = {
    "astranaut": "astronaut",
    "superman": "superhero",
    "guitarist": "rock_guitarist",
    "police": "police_officer",
    "fire_fighter": "firefighter",
    "knightt": "knight",
    "ninjaa": "ninja",
    "piratee": "pirate",
    "santa_clause": "santa",
    "golferr": "golfer",
    "private_jet": "jet_traveler",
    "yacht": "yacht_owner",
    "basketball": "basketball_player",
}


def normalise(stem):
    """Source filenames use spaces, dashes and stray letters; ids use snake_case."""
    return re.sub(r"[^a-z0-9]+", "_", stem.lower()).strip("_")


def app_ids():
    src = (ROOT / "lib" / "data" / "templates.dart").read_text(encoding="utf-8")
    return set(re.findall(r"id:\s*'([a-z_]+)'", src))


def crop_for_tile(img_bgr, app):
    h, w = img_bgr.shape[:2]
    faces = app.get(img_bgr)
    if faces:
        f = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
        x1, y1, x2, y2 = f.bbox
        fx, fy, fw = (x1 + x2) / 2, (y1 + y2) / 2, (x2 - x1)
        crop_w = fw / FACE_W_TARGET
    else:
        fx, fy = w / 2, h * 0.38
        crop_w = w

    # respect the aspect ratio and the zoom clamp
    crop_w = min(crop_w, w, h * (OUT_W / OUT_H))
    crop_w = max(crop_w, w / MAX_ZOOM * 0.75, h * (OUT_W / OUT_H) / MAX_ZOOM)
    crop_h = crop_w * (OUT_H / OUT_W)
    if crop_h > h:
        crop_h = h
        crop_w = crop_h * (OUT_W / OUT_H)

    x = int(round(min(max(fx - crop_w / 2, 0), w - crop_w)))
    y = int(round(min(max(fy - FACE_Y * crop_h, 0), h - crop_h)))
    return img_bgr[y:y + int(crop_h), x:x + int(crop_w)], bool(faces)


def save_under_limit(pil, path):
    for q in range(88, 39, -4):
        pil.save(path, "JPEG", quality=q, optimize=True, progressive=True)
        if path.stat().st_size <= MAX_KB * 1024:
            return q, path.stat().st_size // 1024
    return q, path.stat().st_size // 1024


def main():
    src_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    DEST.mkdir(parents=True, exist_ok=True)
    ids = app_ids()

    app = insightface.app.FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
    app.prepare(ctx_id=-1, det_size=(640, 640))

    written, skipped = [], []
    for f in sorted(src_dir.glob("*.jpg")) + sorted(src_dir.glob("*.png")):
        stem = normalise(f.stem)
        tid = ALIASES.get(stem, stem)
        if tid not in ids:
            skipped.append((f.name, tid))
            continue
        img = cv2.imdecode(np.fromfile(str(f), dtype=np.uint8), cv2.IMREAD_COLOR)
        crop, found = crop_for_tile(img, app)
        pil = Image.fromarray(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)).resize(
            (OUT_W, OUT_H), Image.LANCZOS)
        out = DEST / f"{tid}.jpg"
        q, kb = save_under_limit(pil, out)
        written.append(tid)
        print(f"  {f.name:22s} -> {tid+'.jpg':24s} q{q} {kb}KB {'' if found else '(no face, centre crop)'}")

    print(f"\nwrote {len(written)} / {len(ids)} templates")
    if skipped:
        print("unmatched source files:")
        for n, t in skipped:
            print(f"  {n}  (looked for id '{t}')")
    missing = sorted(ids - set(written))
    print(f"\nstill missing artwork ({len(missing)}):")
    print("  " + ", ".join(missing))


if __name__ == "__main__":
    main()
