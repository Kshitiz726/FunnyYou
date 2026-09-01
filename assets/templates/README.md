# Template reference artwork

Drop a JPG here named after the template id and the app picks it up
automatically — no code change needed.

    assets/templates/superhero.jpg
    assets/templates/astronaut.jpg
    assets/templates/chef.jpg
    …

Ids are the `id:` values in `lib/data/templates.dart` (40 of them).

Guidelines:

- Portrait crop, 3:4 or 4:5, at least 900 px wide.
- The face should sit in the upper third — the picker overlays the user's own
  photo there as a preview bubble.
- Keep files under ~200 KB each; the catalogue ships in the app bundle.

Until a file exists, the app renders a designed gradient + emoji placeholder,
so the UI is complete either way.
