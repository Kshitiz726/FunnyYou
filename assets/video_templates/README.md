# Scenario poster frames

One JPG per scenario, named after the template id, lifted from that scenario's
own clip:

    assets/video_templates/gym.jpg
    assets/video_templates/karaoke.jpg
    assets/video_templates/nurse.jpg
    …

Ids are the `id:` values in `lib/data/templates.dart`.

These are poster frames, not separate artwork. The tile should show the real
scene the video is going to play, so pulling a frame out of the clip is both
less work and more honest than commissioning a still that does not match.

`tools/lock_previews.py` reads the same source clips, so if you add a scenario
you want both: a poster frame here and a locked clip in `assets/locked_previews/`.

Guidelines:

- Portrait, matching the clip (the supplied ones are 464x688).
- Pick the frame that reads as the joke, not the first frame. A clip usually
  opens on a neutral shot.
- The face should sit in the upper third. The picker overlays the user's own
  photo there as a preview bubble.
- Keep files under ~200 KB each; these ship in the app bundle.

Until a file exists the app renders a designed gradient and icon placeholder,
so the UI is complete either way.

## Where the source clips live

The client supplies these. They are not in the repo (too large, and they are
his), and currently sit in `~/Downloads/funny_you/`. `tools/lock_previews.py`
reads from there; change `SRC` in that file if they move.
