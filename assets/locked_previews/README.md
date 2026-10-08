# Locked scenario previews

One MP4 per scenario, named after the template id. These are what the app plays
when somebody taps a scenario, before they pay:

    assets/locked_previews/gym.mp4
    assets/locked_previews/karaoke.mp4
    …

Each is that scenario's own clip with the face blacked out and a padlock drawn
over it.

## Why these are files and not renders

This is the part that matters commercially. The preview is **the same file for
every user**, so showing it costs nothing, needs no GPU, and never queues
behind someone else's render. Browsing is free to offer no matter how many
people do it.

The expensive, personalised work only happens after the paywall. The only
thing generated per user is the four photo thumbnails after the selfie
(`TemplateCatalog.facePreviewCount`).

## Regenerating

    python tools/lock_previews.py              # all of them
    python tools/lock_previews.py gym karaoke  # just these

The script finds the face with the same detector the render box uses
(InsightFace `buffalo_l`), interpolates across frames where detection misses so
the face never flashes uncovered, smooths the box so it does not jitter, and
encodes with ffmpeg at CRF 28.

Expect roughly 150–500 KB per 10 second clip. If one comes out at several MB,
the ffmpeg step has fallen back to OpenCV's writer, which has no bitrate
control; check that `imageio-ffmpeg` is installed.

## If you replace these by hand

The client offered to do this pass in After Effects instead. That is fine, and
the app does not care where the file came from. Keep to:

- H.264 in an MP4 (`yuv420p`). MPEG-4 Part 2 will not reliably play on iOS.
- Portrait, matching the source clip.
- No audio. The app mutes playback anyway.
- Cover enough that the person genuinely cannot be identified, including hair
  and chin, not just the features.
