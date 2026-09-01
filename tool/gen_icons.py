"""Regenerate every launcher icon from assets/brand/icon.svg (or a supplied PNG).

    python tool/gen_icons.py                # render from the SVG
    python tool/gen_icons.py client.png     # use a supplied square PNG instead

Writes Android mipmaps (legacy + adaptive) and the full iOS AppIcon set.
"""
import json, sys, pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
BRAND = ROOT / "assets" / "brand"
RED = (225, 29, 40, 255)  # AppColors.primary


def source_1024():
    if len(sys.argv) > 1:
        src = Image.open(sys.argv[1]).convert("RGBA")
        print("source:", sys.argv[1], src.size)
    else:
        import cairosvg
        png = BRAND / "icon_1024.png"
        cairosvg.svg2png(url=str(BRAND / "icon.svg"), write_to=str(png),
                         output_width=1024, output_height=1024)
        src = Image.open(png).convert("RGBA")
        print("source: assets/brand/icon.svg")
    if src.width != src.height:
        raise SystemExit("icon must be square, got %s" % (src.size,))
    return src.resize((1024, 1024), Image.LANCZOS)


def flatten(img):
    """iOS icons must be fully opaque - an alpha channel fails App Store validation."""
    bg = Image.new("RGBA", img.size, RED)
    return Image.alpha_composite(bg, img).convert("RGB")


def main():
    src = source_1024()
    flat = flatten(src)

    for folder, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                       ("xxhdpi", 144), ("xxxhdpi", 192)]:
        d = ROOT / "android/app/src/main/res" / ("mipmap-" + folder)
        d.mkdir(parents=True, exist_ok=True)
        flat.resize((px, px), Image.LANCZOS).save(d / "ic_launcher.png")
    print("android: 5 legacy mipmaps")

    # Adaptive foreground: art must sit inside the middle ~66% safe zone.
    for folder, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                       ("xxhdpi", 324), ("xxxhdpi", 432)]:
        d = ROOT / "android/app/src/main/res" / ("mipmap-" + folder)
        canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        inner = int(px * 0.66)
        canvas.paste(src.resize((inner, inner), Image.LANCZOS),
                     ((px - inner) // 2, (px - inner) // 2))
        canvas.save(d / "ic_launcher_foreground.png")

    v26 = ROOT / "android/app/src/main/res/mipmap-anydpi-v26"
    v26.mkdir(parents=True, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '</adaptive-icon>\n')
    (v26 / "ic_launcher.xml").write_text(xml, encoding="utf-8")
    (v26 / "ic_launcher_round.xml").write_text(xml, encoding="utf-8")

    vals = ROOT / "android/app/src/main/res/values"
    vals.mkdir(parents=True, exist_ok=True)
    (vals / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#E11D28</color>\n</resources>\n',
        encoding="utf-8")
    print("android: adaptive foreground + background colour")

    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    meta = json.loads((ios / "Contents.json").read_text(encoding="utf-8"))
    done = set()
    for img in meta["images"]:
        fn = img.get("filename")
        if not fn or fn in done:
            continue
        px = int(round(float(img["size"].split("x")[0]) * float(img["scale"].rstrip("x"))))
        flat.resize((px, px), Image.LANCZOS).save(ios / fn)
        done.add(fn)
    print("ios: %d icons" % len(done))

    flat.save(BRAND / "icon_1024.png")
    print("done")


if __name__ == "__main__":
    main()
