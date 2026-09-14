# Funny You — developer notes

How to run it is in [README.md](README.md). This is everything else.

## Running against a backend

When the GPU pod is up, pass its URL at build time and the same binary does
real renders:

```bash
flutter run -d iphone \
  --dart-define=API_BASE_URL=https://<your-pod>-8000.proxy.runpod.net \
  --dart-define=API_KEY=<key>
```

Only scenarios with a template clip *and* click points on the server can
actually be rendered; the app asks `/v1/health` at launch and marks the rest
"Soon" rather than letting you spend a credit to find out. See
[backend/README.md](backend/README.md).

For a backend on your own machine instead, run the dev stack — it serves the
real API against local stand-ins for ComfyUI and Gemini, so no GPU or key is
needed:

```bash
cd backend && pip install -r requirements-dev.txt && python -m devstack.run
```

```bash
flutter run --dart-define=USE_LOCAL_BACKEND=true
```

`USE_LOCAL_BACKEND` is opt-in on purpose. Mocks fabricate a convincing flow,
and while developing the pipeline that reads as "it works" when nothing was
rendered — so a debug build talks to localhost only when asked, and a missing
backend then shows an honest connection error.

## What is not in this repo

The scenario clips (`backend/templates/*.mp4`) and their costume reference
stills are not committed — tens of MB of binary that git is the wrong place
for, and the `.hybrid` reference is a photograph of a real person's face. They
live on the render pod. The `.points.json` sidecars beside them *are*
committed, because those are authored rather than generated.

Nothing on the no-backend path needs any of it. A clone runs on mocks with an
empty `backend/templates/`.

## Other platforms

Android and Windows exist so the flow can be exercised without a Mac:

```bash
flutter run -d android
flutter run -d windows
```

> **Android emulator camera.** A fresh AVD ships with `hw.camera.front = none`
> and a synthetic green test scene on the back camera, which makes a selfie app
> look broken. Point it at your real webcam:
>
> ```bash
> emulator -avd <name> -camera-back webcam0 -camera-front webcam0
> ```
>
> `emulator -webcam-list` shows what is available.

Checks:

```bash
flutter analyze   # clean
flutter test      # 15 tests
cd backend && pytest -q   # 42 tests
```

---

## The flow

Exactly the journey in the flow diagram:

| # | Screen | File |
|---|--------|------|
| 1 | Welcome: one question, one big Yes | `features/onboarding/welcome_screen.dart` |
| 2 | Why we need a photo + how to take a good one | `features/capture/photo_intro_screen.dart` |
| 3 | The camera permission alert, on its own slide | same file, slide two |
| 4 | Native camera alert | triggered by the button on slide two |
| 5 | Camera with face guide, then review + quality check | `features/capture/capture_screen.dart` |
| 6 | "You look great", and a warning that an ad is next | `features/capture/photo_ready_screen.dart` |
| 7 | The ad that pays for the render | `features/ads/ad_break_screen.dart` |
| 8 | Choose your scenario: six tiles + More scenarios | `features/templates/quick_pick_screen.dart` |
| 9 | All 40 scenarios, by category | `features/templates/template_picker_screen.dart` |
| 10 | Generating: progress ring, stage checklist, ETA | `features/generating/generating_screen.dart` |
| 11 | Your video is ready: play, share, save, make another | `features/result/result_screen.dart` |
| 12 | Home (after the first video) | `features/home/home_screen.dart` |

The welcome screen shows **once**, on first launch. The four step product tour
that used to follow it now lives behind *Me > See how it works again*
(`features/onboarding/how_it_works_screen.dart`).

Ordering of the gates (selfie, ad, scenario, render) lives in exactly one
place: `app/creation_flow.dart`. The first run goes through the same function,
so the two cannot drift apart.

**Faces only ever come from the camera.** There is no photo-library route
anywhere in the app, and `image_picker` is not a dependency. Whatever face goes
in comes out in the render, and nothing about a picture from someone's camera
roll says it is a picture of them.

**The paywall is still there** (`features/paywall/paywall_screen.dart`),
reached from *Me*, for buying credits in packs. Credits skip the ad.

"Make another" pops back to the home screen, which is the `ui_inspo` layout:
greeting, *What's your next creation?*, prompt composer with **Camera / Voice**, *Choose your style* rail, and a *Discovery* grid filtered by
category.

---

## The 40 scenarios

`lib/data/templates.dart` — one const list, six categories:

| Category | Count |
|---|---|
| Heroes & Action | 8 |
| Entertainment | 8 |
| Professions | 8 |
| Royalty & Fantasy | 4 |
| Sports | 6 |
| Travel & Lifestyle | 6 |

Each carries a title, emoji, tagline, gradient, and the **prompt** sent to the
render backend.

### Where the tile artwork comes from

Three fallbacks, in order:

1. **An AI preview of the actual user**, generated free on Gemini right after
   they take their photo. This is the default once a backend is connected.
2. Bundled reference art — drop a JPG into `assets/templates/<id>.jpg` and it
   appears automatically, no code change. See `assets/templates/README.md`.
3. The scenario icon on its gradient, with the user's photo inset.

So the picker works with no backend and no assets, and gets better as you add
each.

---

## The backend

Real, in [backend/](backend/). Two services:

| | What | Provider | Cost |
|---|---|---|---|
| **Previews** | Stills of the user in all 40 styles | `gemini` | free, no card, ~500/day — key must be from a *new AI Studio project* |
| **Render** | The 5-second clip | `comfy` (own GPU) or `pollinations` (hosted `wan`) | GPU rental or metered credit |

The split is the point: free previews sell the paid render, and the GPU only
ever spins up after the paywall.

Which vendor runs each half is two env vars — `PREVIEW_PROVIDER` and
`VIDEO_PROVIDER`. Nothing above `backend/app/providers/` knows the difference,
so moving to RunPod later is configuration, not a rewrite.

Stills are genuinely free. **Video is not** — there is no free image-to-video
API, and the anonymous tiers that claim otherwise cap out at roughly one
generation per hour. The measurements behind that are in
[backend/README.md](backend/README.md).

Connect the app by defining the URL at build time — with nothing defined it
runs entirely on mocks:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=API_KEY=<your key>
```

Setup, hosting options and honest costs: **[backend/DEPLOYMENT.md](backend/DEPLOYMENT.md)**.

### Still mocked

**Payments.** Implement `PurchaseService` with `in_app_purchase`. The product
ids the paywall expects, all **consumables** in App Store Connect:

```
com.funnyyou.video.single   39 kr    1 video
com.funnyyou.video.pack5   129 kr    5 videos   (best value)
com.funnyyou.video.pack15  299 kr   15 videos
```

The paywall UI never imports a payment SDK, so nothing there changes.

**Bundle id** — currently `com.funnyyou.funnyYou`. Change it in Xcode.

---

## Layout

```
lib/
  main.dart                  entry point, portrait lock
  app/
    app.dart                 root, decides first-run vs returning
    creation_flow.dart       photo → paywall → render, in one place
  core/
    theme/app_theme.dart     colours, type scale, spacing, shadows
    widgets/                 buttons, aurora backdrop, entrance animations
  data/
    templates.dart           the 40 scenarios
    models.dart              Creation, PricingPlan
  services/                  generation, purchases, permissions, locator
  state/app_state.dart       persisted state (photo, credits, library)
  features/                  one folder per screen
```

Design decisions worth knowing:

- **No webviews, no HTML.** Every pixel is a Flutter widget compiled to native.
- **No image assets required.** Backdrops, phone mockups, face guides and
  progress rings are all `CustomPainter` — nothing to download, sharp at every
  scale, no bundle weight.
- **Built for older users.** Body copy never below 15 pt, tap targets never
  below 52 pt, plain-spoken microcopy ("Finding your face", not "Processing"),
  and system text scaling is honoured up to 1.35×.
- **State is a single `ChangeNotifier`.** The app is small enough that a heavier
  state library would cost more than it returns.
