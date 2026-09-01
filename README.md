# Funny You

Take one photo of yourself, pick a scenario, get a funny video of you in it.
An iPhone app built with Flutter.

## Run it on an iPhone

You need a Mac with Xcode and Flutter installed. You do **not** need a paid
Apple Developer account — a free Apple ID works.

**1. Get the code and its packages**

```bash
git clone https://github.com/Kshitiz726/FunnyYou.git
cd FunnyYou
flutter pub get
cd ios && pod install && cd ..
```

**2. Open it in Xcode**

```bash
open ios/Runner.xcworkspace
```

Open the workspace, not the project file.

**3. Sign it (once)**

In the left sidebar click **Runner**, then the **Signing & Capabilities** tab.
Tick *Automatically manage signing* and pick your Apple ID under **Team**. If
you have no team listed, add your Apple ID under Xcode → Settings → Accounts.

If Xcode complains the bundle identifier is taken, change it to something of
your own — `com.yourname.funnyyou` — and it will go through.

**4. Run it**

Plug in your iPhone, pick it from the device menu at the top, press ▶.

The first launch will be blocked by iOS. On the phone go to **Settings →
General → VPN & Device Management**, tap the developer profile, tap **Trust**,
then open the app again. You only do this once.

The Simulator also works and needs no signing at all — but it has no camera, so
the app asks you for a photo from the library instead.

## What you'll see

The whole app: the intro, taking your photo, all 40 scenarios, the paywall, the
progress screen, and the result screen.

The video itself is **not** really made — that part runs on a GPU server, and
without one the app plays through the steps and then tells you there's no video
rather than showing you a fake one. Everything else is real.

## To make real videos

The renders happen on a GPU pod. When it's running, pass its address when you
launch and the same app does real renders:

```bash
flutter run -d iphone \
  --dart-define=API_BASE_URL=https://your-pod-8000.proxy.runpod.net \
  --dart-define=API_KEY=your-key
```

That has to be run from the terminal — pressing ▶ in Xcode skips those two
settings. Only scenarios that are fully built on the server can be rendered;
the app checks at launch and marks the rest "Soon" so you can't waste a credit
on one. Setting the server up is in [backend/README.md](backend/README.md).

## Notes

- Needs iOS 14 or newer.
- A free Apple ID build stops working after 7 days. Just run it again to
  refresh it.
- The scenario video clips aren't in this repo — they're large binary files
  and they live on the render server. Nothing above needs them.
- Android and Windows builds also work (`flutter run -d android`) if you want
  to look at the app without a Mac.

## If you're working on the code

More detail — the screen-by-screen flow, the scenario list, the backend, and
the folder layout — is in [DEVELOPING.md](DEVELOPING.md).
