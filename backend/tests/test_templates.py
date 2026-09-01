"""The template clip library — what a character swap renders into.

A missing clip must fail the render with an actionable message rather than
crashing the service or, worse, silently rendering the workflow's authored
placeholder video for a paying customer.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from app.template_library import TemplateLibrary


@pytest.fixture
def library(tmp_path: Path) -> TemplateLibrary:
    (tmp_path / "astronaut.mp4").write_bytes(b"fake mp4")
    (tmp_path / "superhero.webm").write_bytes(b"fake webm")
    (tmp_path / "notes.txt").write_text("not a clip")
    return TemplateLibrary(tmp_path)


def test_finds_a_clip_by_template_id(library: TemplateLibrary) -> None:
    clip = library.get("astronaut")
    assert clip is not None
    assert clip.filename == "astronaut.mp4"
    assert clip.read() == b"fake mp4"


def test_accepts_other_video_containers(library: TemplateLibrary) -> None:
    clip = library.get("superhero")
    assert clip is not None and clip.filename == "superhero.webm"


def test_missing_template_returns_none_not_an_error(library: TemplateLibrary) -> None:
    assert library.get("wizard") is None
    assert library.get(None) is None


def test_available_lists_only_real_clips(library: TemplateLibrary) -> None:
    assert library.available() == ["astronaut", "superhero"]


def test_missing_reason_says_what_to_do(library: TemplateLibrary) -> None:
    message = library.missing_reason("wizard")
    assert "wizard.mp4" in message
    assert "astronaut" in message  # tells you what you do have


@pytest.mark.parametrize(
    "evil", ["../secrets", r"..\secrets", "a/b", r"a\b", "../../etc/passwd"]
)
def test_template_id_cannot_escape_the_directory(
    library: TemplateLibrary, evil: str
) -> None:
    """template_id arrives from the client and becomes a filesystem path."""
    assert library.get(evil) is None


def test_absent_directory_is_not_a_crash(tmp_path: Path) -> None:
    library = TemplateLibrary(tmp_path / "nope")
    assert library.available() == []
    assert library.get("astronaut") is None
