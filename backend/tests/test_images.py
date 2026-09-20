"""A sideways photo is the failure nobody sees.

The camera writes the sensor's landscape pixels plus an EXIF tag saying to
turn them. Everything that *displays* the photo honours the tag, so it looks
right to the person who took it. Everything that *reads pixels* ignores it, so
the face detector finds no face and the swap has nothing to swap -- and the
preview tiles come back as stock art with no error anywhere.
"""

from __future__ import annotations

import io

import pytest

from app.images import upright

np = pytest.importorskip("numpy")
Image = pytest.importorskip("PIL.Image")

_ORIENTATION = 0x0112


def _jpeg(size=(400, 200), orientation: int | None = None) -> bytes:
    """A landscape image, optionally tagged "turn me upright"."""
    rng = np.random.default_rng(0)
    pixels = rng.integers(0, 255, (size[1], size[0], 3), dtype="uint8")
    image = Image.fromarray(pixels)

    buffer = io.BytesIO()
    if orientation is None:
        image.save(buffer, format="JPEG", quality=95)
    else:
        exif = image.getexif()
        exif[_ORIENTATION] = orientation
        image.save(buffer, format="JPEG", quality=95, exif=exif)
    return buffer.getvalue()


def _size(data: bytes) -> tuple[int, int]:
    with Image.open(io.BytesIO(data)) as image:
        return image.size


def test_a_photo_tagged_sideways_comes_back_upright() -> None:
    """Orientation 6 is the one a phone held in portrait writes."""
    straightened = upright(_jpeg(orientation=6))
    assert _size(straightened) == (200, 400), "the pixels were not turned"


def test_the_rotation_is_baked_into_the_pixels_not_left_in_the_tag() -> None:
    """A tag the next reader also ignores would fix nothing."""
    straightened = upright(_jpeg(orientation=6))
    with Image.open(io.BytesIO(straightened)) as image:
        assert image.getexif().get(_ORIENTATION, 1) in (0, 1)


@pytest.mark.parametrize("orientation", [3, 6, 8])
def test_every_rotating_orientation_is_handled(orientation: int) -> None:
    original = _jpeg(orientation=orientation)
    assert upright(original) != original


def test_an_upright_photo_is_returned_byte_for_byte() -> None:
    """Re-encoding the common case would cost quality to fix nothing."""
    original = _jpeg(orientation=1)
    assert upright(original) is original


def test_a_photo_with_no_exif_at_all_is_left_alone() -> None:
    original = _jpeg()
    assert upright(original) is original


def test_something_that_is_not_an_image_passes_straight_through() -> None:
    """Our inability to read it is not a reason to fail the upload."""
    junk = b"not a picture at all"
    assert upright(junk) is junk


def test_an_empty_body_passes_straight_through() -> None:
    assert upright(b"") is b""
