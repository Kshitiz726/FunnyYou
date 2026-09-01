"""The scenario stills a face swap pastes the customer's face onto.

The app already ships one reference photo per scenario — the artwork on every
tile. A preview is that exact image with the customer's face swapped in, so the
tile they tap and the preview they get are the same picture. Nothing is
invented, which is why a preview costs ~20s of GPU instead of a full diffusion
run, and why it can never wander off-brand.

Files are named after the template id (`astronaut.jpg`), same convention as
`TemplateLibrary`. `STILL_DIR` points at the app's own `assets/templates` by
default, so there is one copy of the artwork, not two that drift apart.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp")


@dataclass(frozen=True)
class TemplateStill:
    template_id: str
    path: Path

    @property
    def filename(self) -> str:
        return self.path.name

    def read(self) -> bytes:
        return self.path.read_bytes()


class StillLibrary:
    def __init__(self, directory: str | Path) -> None:
        self._dir = Path(directory)

    @property
    def directory(self) -> Path:
        return self._dir

    def get(self, template_id: str | None) -> TemplateStill | None:
        if not template_id:
            return None
        # `template_id` arrives from the client and is used to build a path.
        if "/" in template_id or "\\" in template_id or ".." in template_id:
            log.warning("Rejected suspicious template_id: %r", template_id)
            return None

        for extension in _EXTENSIONS:
            candidate = self._dir / f"{template_id}{extension}"
            if candidate.is_file():
                return TemplateStill(template_id=template_id, path=candidate)
        return None

    def available(self) -> list[str]:
        if not self._dir.is_dir():
            return []
        return sorted(
            path.stem
            for path in self._dir.iterdir()
            if path.is_file() and path.suffix.lower() in _EXTENSIONS
        )

    def missing_reason(self, template_id: str | None) -> str:
        if not template_id:
            return "A face-swap preview needs a scenario, but none was given."
        have = self.available()
        return (
            f"No reference still for '{template_id}'. Put {template_id}.jpg in "
            f"{self._dir}. "
            + (f"{len(have)} installed." if have else "None are installed yet.")
        )
