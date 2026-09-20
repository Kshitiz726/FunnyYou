"""Make an uploaded photo mean the same thing to everything downstream.

A phone camera very often writes the sensor's own landscape pixels and an EXIF
tag saying "turn this 90 degrees to display it". Anything that shows the image
honours that tag -- Flutter does, the browser does -- so the photo *looks*
upright to the person who took it.

Nothing that reads pixels honours it. InsightFace sees a face lying on its
side and reports no face at all; ReActor finds nothing to swap and hands back
the untouched stock still, so the preview tiles look like the feature never
ran. The whole selfie check and the whole preview grid fail silently, on a
photo the user can see is fine.

So the rotation is baked into the pixels once, at the door, and every reader
after that gets the same picture the person thought they took.
"""

from __future__ import annotations

import io
import logging

log = logging.getLogger(__name__)

# EXIF tag 0x0112. 1 means "already the right way up"; 0 means absent.
_ORIENTATION = 0x0112
_UPRIGHT = (0, 1)

# Only used when a photo actually has to be re-encoded. High enough that a
# rotation costs nothing anybody can see.
_QUALITY = 95


def upright(data: bytes) -> bytes:
    """Return [data] with any EXIF rotation applied to the pixels.

    Returns the original bytes untouched when there is nothing to do, which is
    the common case -- re-encoding every upload to fix the few that need it
    would throw away quality for no reason.

    Never raises. A photo we cannot read is a photo we pass along unchanged;
    the callers downstream are all able to say something useful about a file
    they cannot decode, and none of them is improved by an exception here.
    """
    try:
        from PIL import Image, ImageOps

        with Image.open(io.BytesIO(data)) as image:
            orientation = image.getexif().get(_ORIENTATION, 1)
            if orientation in _UPRIGHT:
                return data

            rotated = ImageOps.exif_transpose(image)
            if rotated is None:
                return data

            buffer = io.BytesIO()
            rotated.convert("RGB").save(buffer, format="JPEG", quality=_QUALITY)
            log.info(
                "Straightened an upload: EXIF orientation %s, %s -> %s",
                orientation,
                image.size,
                rotated.size,
            )
            return buffer.getvalue()
    except Exception as exc:  # noqa: BLE001 - an upload must never 500 here
        log.warning("Could not straighten an upload, using it as it came: %r", exc)
        return data
