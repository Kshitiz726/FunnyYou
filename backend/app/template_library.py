"""The template clips a character swap renders into.

Character swap does not invent a scene: it takes a pre-made clip of someone
performing the scenario and replaces the performer with the customer. So a
render needs the customer's photo *and* the scenario's video, and the video is
chosen by `template_id`.

Files live in `TEMPLATE_DIR` named after the template id — `astronaut.mp4`,
`superhero.mp4`. That convention is the whole index; there is no manifest to
drift out of sync with what is actually on disk.

Missing files are a normal state, not an error. The 40 clips arrive over time,
so `get()` returns None and the caller fails that one render with a clear
message rather than the service refusing to start.

A clip may sit beside a `<id>.points.json` sidecar holding the click points
that tell the Wan Animate graph which person in the frame to replace. Those
coordinates are specific to one clip's framing, so they cannot be shared: run
a clip with another clip's points and the segmenter locks onto the wrong
subject — a bystander, or the background — and the render comes back wrong
rather than failing. Graphs that need points therefore treat a clip without a
sidecar as not renderable at all.

A clip may also sit beside a `<id>.ref.png` costume reference: the scenario's
character, in costume, with a stand-in face. Wan Animate reads its reference
image as "this is what the character looks like" -- clothing included -- so
handing it the customer's bare selfie renders them in the shirt they were
photographed in rather than the costume. The render swaps the customer's face
onto this still first and uses the result as the reference, which is what keeps
the coat, the hat and the scene intact.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

# Ordered by preference: the pipeline wants a real video, but an animated
# format is still usable and worth accepting rather than silently ignoring.
_EXTENSIONS = (".mp4", ".webm", ".mov", ".mkv")


@dataclass(frozen=True)
class TemplateClip:
    template_id: str
    path: Path
    points: dict | None = None
    """Click points for this clip, or None if no sidecar was authored."""

    reference: Path | None = None
    """Costume reference still, or None if the clip has no `<id>.ref.png`."""

    hybrid: Path | None = None
    """A pre-approved, ready-made costume reference (`<id>.hybrid.png`).

    When present it is handed to Wan as-is and the generator is skipped. The
    generated hybrid varies run to run -- the same face and still can produce a
    good head swap or a stranger's face -- so a reference that has been looked
    at and approved is worth more than one rebuilt each time. Note this is one
    person's likeness: it belongs to a single-customer setup, not a shared one.
    """

    @property
    def filename(self) -> str:
        return self.path.name

    def read(self) -> bytes:
        return self.path.read_bytes()


class TemplateLibrary:
    def __init__(self, directory: str | Path) -> None:
        self._dir = Path(directory)

    @property
    def directory(self) -> Path:
        return self._dir

    def get(self, template_id: str | None) -> TemplateClip | None:
        if not template_id:
            return None
        # Reject anything that could climb out of the directory — template_id
        # arrives from the client, and it is used to build a filesystem path.
        if "/" in template_id or "\\" in template_id or ".." in template_id:
            log.warning("Rejected suspicious template_id: %r", template_id)
            return None

        for extension in _EXTENSIONS:
            candidate = self._dir / f"{template_id}{extension}"
            if candidate.is_file():
                return TemplateClip(
                    template_id=template_id,
                    path=candidate,
                    points=self.points(template_id),
                    reference=self.reference(template_id),
                    hybrid=self.hybrid(template_id),
                )
        return None

    def points(self, template_id: str) -> dict | None:
        """The clip's click points, or None if it has no sidecar.

        A malformed sidecar reads as absent rather than raising: the effect is
        that the scenario stops being offered, which is the same safe outcome
        as never having authored it.
        """
        sidecar = self._dir / f"{template_id}.points.json"
        if not sidecar.is_file():
            return None
        try:
            data = json.loads(sidecar.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("Ignoring unreadable points file %s: %s", sidecar, exc)
            return None
        if not isinstance(data, dict) or not data.get("positive"):
            log.warning("%s has no 'positive' points — ignoring", sidecar)
            return None
        return data

    def reference(self, template_id: str) -> Path | None:
        """The clip's costume reference still, or None if it has none.

        Absent is a normal state: a clip without one still renders, it just
        dresses the customer in their own clothes. Callers decide whether that
        is acceptable for the graph they are running.
        """
        for extension in (".ref.png", ".ref.jpg"):
            candidate = self._dir / f"{template_id}{extension}"
            if candidate.is_file():
                return candidate
        return None

    def hybrid(self, template_id: str) -> Path | None:
        """A pre-approved costume reference for this clip, if one was saved."""
        for extension in (".hybrid.png", ".hybrid.jpg"):
            candidate = self._dir / f"{template_id}{extension}"
            if candidate.is_file():
                return candidate
        return None

    def available(self, *, require_points: bool = False) -> list[str]:
        """Template ids that actually have a clip on disk, sorted.

        With `require_points`, only clips that also carry a points sidecar —
        the ones a Wan Animate graph can aim correctly.
        """
        if not self._dir.is_dir():
            return []
        found = {
            path.stem
            for path in self._dir.iterdir()
            if path.is_file() and path.suffix.lower() in _EXTENSIONS
        }
        if require_points:
            found = {t for t in found if self.points(t) is not None}
        return sorted(found)

    def missing_reason(self, template_id: str | None) -> str:
        """A message that says what to do, not just what went wrong."""
        if not template_id:
            return (
                "This render needs a template clip, but no template was chosen. "
                "Pick a style before generating."
            )
        have = self.available()
        if template_id in have and self.points(template_id) is None:
            return (
                f"'{template_id}' has a clip but no click points. Add "
                f"{template_id}.points.json next to {template_id}.mp4 — without "
                "it the renderer cannot tell which person in the shot to "
                "replace."
            )
        return (
            f"No template clip for '{template_id}'. Put {template_id}.mp4 in "
            f"{self._dir}. "
            + (f"Available: {', '.join(have)}." if have else "None are installed yet.")
        )
