import 'dart:async';

/// Shows the rewarded ad that pays for one video.
///
/// The flow is: selfie, ad, pick a scenario, render. Watching the ad through
/// to the end is what buys the render, so [show] returning true is the signal
/// to grant a credit.
///
/// **No ad network is wired up yet.** Doing that needs an AdMob account, an
/// app id and a rewarded ad unit id, all of which belong to whoever ships the
/// app, plus the `google_mobile_ads` package and per-platform setup. Until
/// those exist, [MockAdService] fills the slot with a house placeholder so the
/// rest of the flow is real and testable. Swapping in the real thing is one
/// line in `ServiceLocator` and nothing above this file changes.
abstract interface class AdService {
  /// Whether an ad can be shown at all. False sends the flow straight through
  /// rather than stranding the user on a screen with nothing to play.
  bool get available;

  /// How long the placement holds the screen.
  Duration get duration;

  /// Play the ad. Resolves true once it has been watched through, false if the
  /// user backed out or it failed to load.
  Future<bool> show();
}

/// House placeholder, used until a real network is connected.
///
/// It is honest about what it is: the screen says "this is where the ad will
/// play" rather than imitating an advert. Nobody should be able to look at a
/// build and think the money side is hooked up when it is not.
class MockAdService implements AdService {
  const MockAdService();

  @override
  bool get available => true;

  @override
  Duration get duration => const Duration(seconds: 5);

  @override
  Future<bool> show() async => true;
}
