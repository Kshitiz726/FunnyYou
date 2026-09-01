# Funny You — AI funny-video app

A native iOS app built with Flutter. Turn one photo of yourself into a funny
video across 40 scenarios.

Everything is written for iOS first — Cupertino page transitions, SF Pro
typography, portrait-only, native permission priming — and compiles to a real
`.app`/`.ipa` via Xcode. Android and Windows targets exist only so the flow can
be exercised without a Mac.

---

## Running it

**On Windows, right now** (design review; camera falls back to the photo
picker):

```bash
flutter run -d windows
```

Or on an Android device/emulator, where the camera, gallery, voice input and
"save to gallery" all work for real:

```bash
flutter run -d android
```

**On iOS** (needs a Mac with Xcode):

```bash
cd ios && pod install && cd ..
flutter run -d ios
```

Then in Xcode set your team under *Runner → Signing & Capabilities*. Deployment
target is iOS 14.0.

**With a working backend**, no GPU and no API key needed — the dev stack runs
the real API against local stand-ins for ComfyUI and Gemini:

```bash
cd backend && pip install -r requirements-dev.txt && python -m devstack.run
```

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Previews now fill the grid with real generated JPEGs and "Make video" produces a
real playable MP4. See [backend/README.md](backend/README.md).

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
| 1 | Welcome + 4 animated steps, Next / Skip | `features/onboarding/welcome_screen.dart` |
| 2 | Why we need a photo + permission priming | `features/capture/photo_intro_screen.dart` |
| 3 | Native iOS camera alert | triggered from the screen above |
| 4 | Camera with face guide → review, Retake / Continue | `features/capture/capture_screen.dart` |
| 5 | Pick your favourite — hero preview + all 40 scenarios | `features/templates/template_picker_screen.dart` |
| 6 | Paywall — three one-time packs, StoreKit-ready | `features/paywall/paywall_screen.dart` |
| 7 | Generating — progress ring, stage checklist, ETA | `features/generating/generating_screen.dart` |
| 8 | Your video is ready — play, share, save, make another | `features/result/result_screen.dart` |
| 9 | Home (after the first video) | `features/home/home_screen.dart` |

The welcome screen shows **once**, on first launch. Ordering of the gates
(photo → payment → render) lives in one place: `app/creation_flow.dart`.

"Make another" pops back to the home screen, which is the `ui_inspo` layout:
greeting, *What's your next creation?*, prompt composer with **Camera / Add
image / Voice**, *Choose your style* rail, and a *Discovery* grid filtered by
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
