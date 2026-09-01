# Funny You

Take one photo of yourself, pick a scenario, and get a funny video with your
face in it.

It's an iPhone app. Here's how to get it running on your phone.

## What you need first

Three things on a Mac:

1. **Xcode**, free from the App Store. It's big, start the download now.
2. **Flutter**, one command in Terminal (skip it if you already have it):
   ```bash
   brew install --cask flutter
   ```
3. **An Apple ID**. Just your normal one. You do NOT need to pay Apple $99.

That's it. No servers, no API keys, no accounts to make.

## Step 1: grab the code

Open Terminal and paste this whole block. It downloads everything and gets it
ready. Takes a couple of minutes.

```bash
git clone https://github.com/Kshitiz726/FunnyYou.git
cd FunnyYou
flutter pub get
cd ios && pod install && cd ..
```

## Step 2: open it in Xcode

Paste this:

```bash
open ios/Runner.xcworkspace
```

Careful here. Open `Runner.xcworkspace`, the white icon. There's a similar file
called `Runner.xcodeproj` (blue icon) and it will not work. The command above
opens the right one, so just paste it.

## Step 3: tell Xcode who you are

You only ever do this once.

1. In the list on the left, click **Runner** at the very top.
2. Click the **Signing & Capabilities** tab.
3. Tick **Automatically manage signing**.
4. In the **Team** dropdown, pick your name. If it's empty, go to
   **Xcode > Settings > Accounts**, hit the **+**, sign in with your Apple ID,
   then come back and pick it.

If you see a red error about the bundle identifier already being taken, change
the **Bundle Identifier** box to something nobody else would use, like
`com.yourname.funnyyou`. Then it's happy.

## Step 4: run it

Plug your iPhone into the Mac with a cable. Unlock the phone. If it asks
"Trust This Computer?", tap Trust.

At the top of Xcode there's a dropdown showing a device name. Click it and pick
your iPhone. Then hit the **play button** (the triangle, top left).

Wait a bit. First build is slow, like 5 minutes. After that it's quick.

### One last thing, the first time only

The app installs but iOS won't let it open yet, because Apple doesn't know you.
On your **phone**:

**Settings > General > VPN & Device Management > tap your Apple ID > Trust**

Now open the app. Done.

## Don't have a cable handy?

You can run it on the fake iPhone built into Xcode instead. No signing, no
phone, nothing to trust. Just paste:

```bash
flutter run
```

Only catch: the fake iPhone has no camera, so instead of taking a selfie it
asks you to pick a photo from the library.

## What actually works right now

Everything you can tap: the intro, taking your photo, all 40 scenarios, the
pricing screen, the loading screen, the finished video screen.

The video itself is not really made yet. That part runs on a rented graphics
card, and when that's switched off the app walks through all the steps and then
tells you straight up there's no video, instead of faking one. So you're
looking at the real app, just without the render.

## Turning the real videos on

When the GPU server is running, you launch it with the address instead of
pressing play in Xcode. Paste this (swap in the real address and key):

```bash
flutter run -d iphone \
  --dart-define=API_BASE_URL=https://your-pod-8000.proxy.runpod.net \
  --dart-define=API_KEY=your-key
```

Has to be Terminal, not the play button, because the play button doesn't know
about those two settings.

Only the scenarios that are finished on the server can actually be made. The
app checks when it opens and puts "Soon" on the rest, so you can't waste money
on one that isn't ready.

## Stuff that might trip you up

- **The app stops opening after a week.** Normal. Free Apple IDs expire builds
  after 7 days. Plug the phone in, hit play again, back to normal.
- **Needs iOS 14 or newer.** Any iPhone from the last several years is fine.
- **You can't email the app to someone.** Free account only runs it on phones
  plugged into your own Mac. Sending builds around needs the paid Apple
  account.
- **`pod install` fails?** Run `sudo gem install cocoapods` and try again.
- **Want to see it without a Mac?** `flutter run -d android` works too.

## For developers

Everything about how it's built, the screens, the backend, the folder layout,
is in [DEVELOPING.md](DEVELOPING.md).
