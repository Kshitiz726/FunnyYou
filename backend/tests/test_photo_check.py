"""The selfie check, minus the part that needs a GPU box.

InsightFace is not installed on a developer's laptop, so these cover the
behaviour that has to hold whether or not it is: the exposure and focus
reading, the ordering of findings, and -- most of all -- that nothing here
can fail a request or reject somebody's photo because our own machinery
was missing.
"""

from __future__ import annotations

import io

import pytest

from app.photo_check import PhotoChecker, PhotoReport, build_checker, find_models

np = pytest.importorskip("numpy")
Image = pytest.importorskip("PIL.Image")


def _png(fill: int | tuple[int, int, int], size=(240, 320), noise: int = 0) -> bytes:
    pixels = np.full((size[1], size[0], 3), fill, dtype="uint8")
    if noise:
        rng = np.random.default_rng(0)
        pixels = np.clip(
            pixels.astype("int16")
            + rng.integers(-noise, noise, pixels.shape, dtype="int16"),
            0,
            255,
        ).astype("uint8")
    buffer = io.BytesIO()
    Image.fromarray(pixels).save(buffer, format="PNG")
    return buffer.getvalue()


@pytest.fixture
def blind() -> PhotoChecker:
    """A checker that cannot load InsightFace, like a laptop."""
    checker = PhotoChecker()
    checker._tried = True  # noqa: SLF001 - deliberate seam
    checker._app = None  # noqa: SLF001
    return checker


def test_a_dark_frame_reads_as_dark(blind: PhotoChecker) -> None:
    assert "too_dark" in blind.inspect(_png(8)).issues


def test_a_blown_out_frame_reads_as_bright(blind: PhotoChecker) -> None:
    assert "too_bright" in blind.inspect(_png(250)).issues


def test_a_flat_frame_reads_as_soft(blind: PhotoChecker) -> None:
    """No edges anywhere means nothing is in focus."""
    assert "blurry" in blind.inspect(_png(128)).issues


def test_a_noisy_mid_grey_frame_is_left_alone(blind: PhotoChecker) -> None:
    """Well exposed and full of detail: the check has nothing to say."""
    assert blind.inspect(_png(128, noise=60)).issues == []


def test_without_insightface_it_never_claims_there_is_no_face(
    blind: PhotoChecker,
) -> None:
    """The most important line in the file.

    A laptop, a pod with the models missing, a broken onnxruntime -- none of
    them may turn into "we can't find a face in this photo", which is the one
    message that stops somebody proceeding.
    """
    report = blind.inspect(_png(128, noise=60))
    assert "no_face" not in report.issues
    assert report.usable is True
    assert report.yaw is None


def test_bytes_that_are_not_an_image_say_nothing_at_all(
    blind: PhotoChecker,
) -> None:
    """Our failure to decode is not the photographer's problem."""
    report = blind.inspect(b"this is not a picture")
    assert report.issues == []
    assert report.usable is True


def test_a_checker_pointed_at_nothing_still_answers() -> None:
    """No models on disk must degrade, not raise -- and must not download.

    Handed a root it does not have, InsightFace fetches 280 MB rather than
    failing. On the pod that lands on a volume with a 60 GB quota, during
    somebody's first selfie. So a missing pack turns the face half of the
    check off instead.
    """
    checker = PhotoChecker(model_root=None)
    report = checker.inspect(_png(128, noise=60))
    assert isinstance(report, PhotoReport)
    assert report.usable is True
    assert checker.available is False


def test_a_root_without_the_models_is_not_used(tmp_path) -> None:
    """Confirmed on disk before the library is ever told about it.

    Asserted as "not this one" rather than "nothing at all", because the
    search falls through to the usual locations and a machine that has done
    a face swap before legitimately has models in one of them.
    """
    assert find_models(str(tmp_path)) != str(tmp_path)


def test_a_root_with_nothing_anywhere_disables_the_face_half(monkeypatch) -> None:
    monkeypatch.setattr("app.photo_check.Path.is_dir", lambda self: False)
    assert find_models("/anywhere") is None
    assert PhotoChecker(model_root=None).available is False


def test_a_root_holding_the_pack_is_chosen(tmp_path) -> None:
    (tmp_path / "models" / "buffalo_l").mkdir(parents=True)
    assert find_models(str(tmp_path)) == str(tmp_path)


def test_no_face_is_reported_before_the_softer_findings() -> None:
    """The app shows one message, so the first one has to be the real one."""
    report = PhotoReport(issues=["no_face", "blurry"])
    assert report.issues[0] == "no_face"
    assert report.usable is False


def test_the_json_shape_is_what_the_app_reads() -> None:
    body = PhotoReport(
        face_count=1, yaw=31.234, brightness=100.0, issues=["turned"]
    ).to_json()

    assert body["faceCount"] == 1
    assert body["yaw"] == 31.23
    assert body["pitch"] is None
    assert body["issues"] == ["turned"]
    assert body["usable"] is True


def test_the_builder_survives_a_box_with_no_models() -> None:
    class Bare:
        insightface_root = ""

    assert isinstance(build_checker(Bare()), PhotoChecker)


def test_the_builder_uses_a_configured_root_that_exists(tmp_path) -> None:
    (tmp_path / "models" / "buffalo_l").mkdir(parents=True)

    class Configured:
        insightface_root = str(tmp_path)

    assert build_checker(Configured())._model_root == str(tmp_path)  # noqa: SLF001
