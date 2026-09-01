Hey, here's how to run it on your iPhone.

You need a Mac with Xcode installed, and your normal Apple ID. No paid Apple
account needed.

Open Terminal and paste this:

```bash
git clone https://github.com/Kshitiz726/FunnyYou.git
cd FunnyYou
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

Xcode will open. On the left click Runner at the top, go to the Signing &
Capabilities tab, and pick your name in the Team dropdown. If it's empty, add
your Apple ID under Xcode > Settings > Accounts first.

Now plug your iPhone in, pick it from the dropdown at the top, and hit play.
First build takes a few minutes.

The app won't open yet, iOS blocks it. On your phone go to Settings > General
> VPN & Device Management, tap your Apple ID, tap Trust. Then open it.

That's it. One heads up: the video at the end isn't actually made yet, that
part runs on a GPU server that's currently off. Everything else is real, the
app just tells you there's no video instead of faking one.
