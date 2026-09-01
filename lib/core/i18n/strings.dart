import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

/// The two languages the app ships in.
///
/// Danish is not a nice-to-have here — the audience is Danish, and a boomer who
/// hits an English screen mid-flow simply stops. Every user-facing string in the
/// app goes through [S].
enum AppLang {
  en('English', 'EN'),
  da('Dansk', 'DA');

  const AppLang(this.label, this.short);

  /// Always written in its *own* language, so the choice is readable to
  /// someone who cannot read the other one.
  final String label;
  final String short;

  static AppLang fromCode(String? code) =>
      code == da.name ? AppLang.da : AppLang.en;

  Locale get locale => Locale(name);
}

/// Every string the user can see, in both languages.
///
/// One getter per string with the two variants side by side. It reads like a
/// translation table, and a new string cannot be added in one language only —
/// there is nowhere to put it.
class S {
  const S(this.lang);

  final AppLang lang;

  bool get _da => lang == AppLang.da;

  /// Uses a plain `watch` rather than `select`: these strings are read from
  /// inside sliver item builders, and provider forbids `select` there.
  static S of(BuildContext context) =>
      S(Provider.of<AppState>(context).lang);

  // ── Shell / navigation ────────────────────────────────────────────────
  String get tabCreate => _da ? 'Lav' : 'Create';
  String get tabVideos => _da ? 'Mine videoer' : 'My videos';
  String get tabMe => _da ? 'Mig' : 'Me';

  // ── Home ──────────────────────────────────────────────────────────────
  String get goodMorning => _da ? 'Godmorgen' : 'Good morning';
  String get goodAfternoon => _da ? 'God eftermiddag' : 'Good afternoon';
  String get goodEvening => _da ? 'God aften' : 'Good evening';
  String get readyForCloseUp =>
      _da ? 'Klar til dit nærbillede?' : 'Ready for your close-up?';

  String get heroTitle => _da
      ? 'Ét billede.\nUendelig sjov.'
      : 'One photo.\nEndless fun.';
  String get heroBody => _da
      ? 'Vælg et scenarie, så laver vi videoen med dit ansigt i.'
      : 'Pick a scenario and we make the video with your face in it.';
  String get makeAVideo => _da ? 'Lav en video' : 'Make a video';
  String get changeMyPhoto => _da ? 'Skift mit billede' : 'Change my photo';

  String get quickScenarios => _da ? 'Scenarier' : 'Scenarios';
  String get quickMyVideos => _da ? 'Videoer' : 'Videos';
  String get quickLanguage => _da ? 'Sprog' : 'Language';

  String get chooseYourStyle => _da ? 'Vælg din stil' : 'Choose your style';
  String get viewAll => _da ? 'Se alle' : 'View all';
  String get discovery => _da ? 'Opdag' : 'Discovery';
  String scenarioCount(int n) => _da ? '$n scenarier' : '$n scenarios';
  String get categoryAll => _da ? 'Alle' : 'All';

  String get noVideosLeft => _da ? 'Ingen videoer tilbage' : 'No videos left';
  String videosLeft(int n) => _da ? '$n tilbage' : '$n left';

  String get addingYourFace =>
      _da ? 'Sætter dit ansigt på…' : 'Adding your face…';
  String get thisIsYou => _da ? 'DIG' : 'YOU';
  String get makingYourPreviews =>
      _da ? 'Vi laver dine forhåndsvisninger' : 'Making your previews';
  String previewProgress(int done, int total) =>
      _da ? '$done af $total klar' : '$done of $total ready';
  String get previewsReady => _da
      ? 'Dine forhåndsvisninger er klar'
      : 'Your previews are ready';

  // ── Template picker ───────────────────────────────────────────────────
  String get pickYourFavourite =>
      _da ? 'Vælg din favorit' : 'Pick your favourite';
  String funScenarios(int n) => _da ? '$n sjove scenarier' : '$n fun scenarios';
  String toChooseFrom(int n) =>
      _da ? '$n at vælge imellem' : '$n to choose from';
  String get surpriseMe => _da ? 'Overrask mig' : 'Surprise me';
  String turnMeInto(String what) =>
      _da ? 'Gør mig til $what' : 'Turn me into a $what';
  String get comingSoon => _da ? 'Snart' : 'Soon';
  String get closeSheet => _da ? 'Luk' : 'Close';
  String get comingSoonBody =>
      _da ? 'Dette scenarie er på vej' : 'This scenario is coming soon';
  String get unlock => _da ? 'Lås op' : 'Unlock';
  String get premium => _da ? 'Premium' : 'Premium';

  // ── Onboarding ────────────────────────────────────────────────────────
  String get welcomeTo => _da ? 'Velkommen til' : 'Welcome to';
  String get welcomeBody => _da
      ? 'Lav en sjov video ud af ét billede af dig selv —\ni fire nemme trin.'
      : 'Turn one photo of yourself into a funny video —\nin four easy steps.';
  String get skip => _da ? 'Spring over' : 'Skip';
  String get next => _da ? 'Næste' : 'Next';
  String get getStarted => _da ? 'Kom i gang' : 'Get Started';
  String stepOfFour(int step) =>
      _da ? 'TRIN $step AF 4' : 'STEP $step OF 4';

  String get step1Title => _da ? 'Tag ét billede' : 'Take one photo';
  String get step1Body => _da
      ? 'Ret kameraet mod dit ansigt og tryk på den store hvide knap. '
          'Mere skal der ikke til.'
      : 'Point the camera at your face and tap the big white button. '
          'That is all we need.';
  String get step2Title => _da ? 'Vælg din favorit' : 'Pick your favourite';
  String get step2Body => _da
      ? 'Superhelt, astronaut, rockstjerne, kok — vælg mellem 40 sjove '
          'scenarier, så klarer vi resten.'
      : 'Superhero, astronaut, rock star, chef — choose from 40 fun '
          'scenarios and we do the rest.';
  String get step3Title => _da ? 'Vi laver din video' : 'We make your video';
  String get step3Body => _da
      ? 'Læn dig tilbage i cirka to minutter, mens vi sætter dig ind i '
          'scenen. Du må gerne lade skærmen være tændt.'
      : 'Sit back for about two minutes while we put you into the scene. '
          'You can keep the screen open.';
  String get step4Title =>
      _da ? 'Se, gem og del' : 'Watch, save and share';
  String get step4Body => _da
      ? 'Gem videoen på din telefon, eller send den direkte til familie og '
          'venner. Og lav så en til!'
      : 'Save your video to your phone or send it straight to family and '
          'friends. Then make another!';

  String stepTitle(int step) => switch (step) {
        1 => step1Title,
        2 => step2Title,
        3 => step3Title,
        _ => step4Title,
      };
  String stepBody(int step) => switch (step) {
        1 => step1Body,
        2 => step2Body,
        3 => step3Body,
        _ => step4Body,
      };

  String get labelPhoto => _da ? 'Billede' : 'Photo';
  String get labelScenario => _da ? 'Scenarie' : 'Scenario';
  String get labelVideo => _da ? 'Video' : 'Video';
  String get labelShare => _da ? 'Del' : 'Share';

  // ── Photo capture ─────────────────────────────────────────────────────
  String get photoIntroBody => _da
      ? 'For at lave en sjov video med dig i skal vi vide, hvordan du ser ud.'
      : 'To make a funny video with you in it, we need to know what you '
          'look like.';
  String get photoIntroBody2 => _da
      ? 'Ét tydeligt billede af dit ansigt er alt, hvad der skal til.'
      : 'One clear photo of your face is all it takes.';
  String get openSettings => _da ? 'Åbn Indstillinger' : 'Open Settings';
  String get useAPhotoIHave =>
      _da ? 'Brug et billede, jeg har' : 'Use a photo I have';
  String get takeAPicture => _da ? 'Tag et billede' : 'Take a picture';
  String get tipLightTitle => _da ? 'Find godt lys' : 'Find good light';
  String get tipLightBody =>
      _da ? 'Stil dig gerne ved et vindue.' : 'Face a window if you can.';
  String get tipStraightTitle =>
      _da ? 'Kig lige frem' : 'Look straight ahead';
  String get tipStraightBody => _da
      ? 'Hold hele ansigtet inde i cirklen.'
      : 'Keep your whole face in the circle.';
  String get tipNoHatsTitle =>
      _da ? 'Ingen hat eller solbriller' : 'No hats or sunglasses';
  String get tipNoHatsBody => _da
      ? 'Vi skal kunne se dine øjne tydeligt.'
      : 'We need to see your eyes clearly.';
  String get permissionExplainer => _da
      ? 'Når du trykker på knappen, spørger telefonen, om appen må bruge '
          'kameraet. Tryk på “Tillad”.'
      : 'When you tap the button, your phone will ask if this app can use '
          'the camera. Please tap “Allow”.';
  String get permissionDenied => _da
      ? 'Adgang til kameraet er slået fra. Åbn Indstillinger, og slå det til.'
      : 'Camera access is turned off. Open Settings, then switch it on.';
  String get faceInCircle => _da
      ? 'Hold ansigtet inde i cirklen'
      : 'Put your face inside the circle';
  String get photosLabel => _da ? 'Billeder' : 'Photos';
  String get happyWithPhoto =>
      _da ? 'Er du glad for billedet?' : 'Happy with this photo?';
  String get retake => _da ? 'Tag igen' : 'Retake';
  String get continueLabel => _da ? 'Fortsæt' : 'Continue';
  String get cameraUnavailable => _da
      ? 'Kameraet er ikke tilgængeligt.'
      : 'The camera is not available.';
  String get chooseAPhotoInstead =>
      _da ? 'Vælg et billede i stedet' : 'Choose a photo instead';
  String get couldNotTakePhoto => _da
      ? 'Billedet kunne ikke tages.'
      : 'Could not take the photo.';

  // ── Generating ────────────────────────────────────────────────────────
  String get makingYourVideo =>
      _da ? 'Vi laver din video…' : 'Making your video…';
  String get justAMoment => _da ? 'Et øjeblik…' : 'Just a moment…';
  String get aboutTwoMinutes => _da
      ? 'Det tager normalt\nca. to minutter.'
      : 'This usually takes\nabout 2 minutes.';
  String get keepScreenOpen => _da
      ? 'Du må gerne lade skærmen være åben. Vi siger til, så snart den er klar.'
      : 'You can keep this screen open. We will let you know the moment it '
          'is ready.';
  String get almostThere => _da ? 'Snart klar…' : 'Almost there…';
  String secondsLeft(int s) =>
      _da ? 'Ca. $s sekunder tilbage' : 'About $s seconds left';
  String minutesLeft(int m) =>
      _da ? 'Ca. $m minutter tilbage' : 'About $m minutes left';
  String get stopMakingTitle =>
      _da ? 'Stop videoen?' : 'Stop making your video?';
  String get stopMakingBody => _da
      ? 'Du beholder din video-billet og kan starte forfra, når du vil.'
      : 'You will keep your credit and can start again whenever you like.';
  String get keepGoing => _da ? 'Fortsæt' : 'Keep going';
  String get stop => _da ? 'Stop' : 'Stop';
  String get somethingWentWrong => _da
      ? 'Noget gik galt. Prøv igen.'
      : 'Something went wrong. Please try again.';
  String get creditNotUsed => _da
      ? 'Din video-billet er ikke brugt.'
      : 'Your credit has not been used.';
  String get tryAgain => _da ? 'Prøv igen' : 'Try again';
  String get goBack => _da ? 'Gå tilbage' : 'Go back';

  // ── Result ────────────────────────────────────────────────────────────
  String get readyBadge => _da ? 'KLAR' : 'READY';
  String secondsLong(int n) => _da ? '$n sekunder' : '$n seconds';
  String youAs(String what) => _da ? 'Dig som $what' : 'You as a $what';
  String get videoReady => _da ? 'Din video er klar!' : 'Your video is ready!';
  String get shareVideo => _da ? 'Del video' : 'Share Video';
  String get saveVideo => _da ? 'Gem video' : 'Save Video';
  String get save => _da ? 'Gem' : 'Save';
  String get saved => _da ? 'Gemt' : 'Saved';
  String get makeAnother => _da ? 'Lav en til' : 'Make Another';
  String get savedToPhotos =>
      _da ? 'Gemt i dine billeder.' : 'Saved to your photos.';
  String shareText(String what) => _da
      ? 'Se, hvad jeg har lavet med Funny You — mig som $what'
      : 'Look what I made with Funny You — me as a $what';

  // ── Library ───────────────────────────────────────────────────────────
  String get myVideos => _da ? 'Mine videoer' : 'My videos';
  String get noVideosYet => _da ? 'Ingen videoer endnu' : 'No videos yet';
  String get noVideosYetBody => _da
      ? 'Lav din første sjove video, så dukker den op her.'
      : 'Make your first funny video and it will show up here.';
  String get justNow => _da ? 'Lige nu' : 'Just now';
  String minutesAgo(int n) => _da ? 'for $n min. siden' : '$n min ago';
  String hoursAgo(int n) => _da ? 'for $n t. siden' : '$n h ago';
  String daysAgo(int n) => _da ? 'for $n dage siden' : '$n days ago';

  // ── Profile ───────────────────────────────────────────────────────────
  String get yourPhoto => _da ? 'Dit billede' : 'Your photo';
  String get notAddedYet => _da ? 'Ikke tilføjet endnu' : 'Not added yet';
  String get usedInEveryVideo => _da
      ? 'Bruges i alle de videoer, du laver'
      : 'Used in every video you make';
  String get add => _da ? 'Tilføj' : 'Add';
  String get change => _da ? 'Skift' : 'Change';
  String videosLeftLong(int n) =>
      _da ? '$n videoer tilbage' : '$n videos left';
  String get topUpAnyTime => _da
      ? 'Fyld op når som helst — intet abonnement.'
      : 'Top up any time — no subscription.';
  String get buyMore => _da ? 'Køb flere' : 'Buy more';
  String get seeHowItWorks =>
      _da ? 'Se hvordan det virker igen' : 'See how it works again';
  String get privacyPolicy => _da ? 'Privatlivspolitik' : 'Privacy policy';
  String get termsOfUse => _da ? 'Vilkår for brug' : 'Terms of use';
  String get contactSupport => _da ? 'Kontakt support' : 'Contact support';

  // ── Language switch ───────────────────────────────────────────────────
  String get language => _da ? 'Sprog' : 'Language';
  String get languageBody => _da
      ? 'Vælg det sprog, appen skal tale.'
      : 'Choose the language the app speaks.';

  // ── Paywall ───────────────────────────────────────────────────────────
  String get turnThisIntoAVideo => _da
      ? 'Lav det her om til\nen sjov video!'
      : 'Turn this into\na funny video!';
  String paywallBody(String what) => _da
      ? 'Dig som $what — klar til at se, gemme og dele.'
      : 'You as a $what — ready to watch, save and share.';
  String get restore => _da ? 'Gendan' : 'Restore';
  String get perkQuality => _da
      ? 'Video i høj kvalitet, som du beholder for altid'
      : 'High-quality video you can keep forever';
  String get perkAllScenarios =>
      _da ? 'Alle 40 scenarier låst op' : 'All 40 scenarios unlocked';
  String get perkFast =>
      _da ? 'Klar på cirka to minutter' : 'Ready in about 2 minutes';
  String get perkPrivate => _da
      ? 'Dit billede deles aldrig med nogen'
      : 'Your photo is never shared with anyone';
  String createMyVideo(String price) =>
      _da ? 'Lav min video – $price' : 'Create my video – $price';
  String get securePayment => _da
      ? 'Sikker betaling · Engangskøb, intet abonnement'
      : 'Secure payment · One-time, no subscription';
  String get paymentFailed => _da
      ? 'Betalingen gik ikke igennem. Prøv igen.'
      : 'Payment did not go through. Please try again.';
  String get noPurchaseToRestore => _da
      ? 'Vi kunne ikke finde et tidligere køb at gendanne.'
      : 'We could not find an earlier purchase to restore.';

  // ── Voice input ───────────────────────────────────────────────────────
  String get listening => _da ? 'Vi lytter…' : 'Listening…';
  String get tellUsYourIdea => _da ? 'Fortæl os din idé' : 'Tell us your idea';
  String get voiceHint => _da
      ? 'Sig for eksempel “gør mig til en piratkaptajn på et skib”.'
      : 'Say something like “make me a pirate captain on a ship”.';
  String get wordsAppearHere => _da
      ? 'Dine ord kommer frem her…'
      : 'Your words will appear here…';
  String get useThis => _da ? 'Brug det her' : 'Use this';
  String get couldNotHearYou => _da
      ? 'Vi kunne ikke høre dig. Prøv igen.'
      : 'We could not hear you. Please try again.';
  String get voiceUnavailable => _da
      ? 'Stemmeinput virker ikke på denne telefon.'
      : 'Voice input is not available on this device.';

  String get cameraNotOnDevice => _da
      ? 'Kameraet virker ikke på denne telefon.'
      : 'Camera is not available on this device.';
  String get promptHint => _da
      ? 'Beskriv din idé… “mig som piratkaptajn”'
      : 'Describe your idea… “me as a pirate captain”';
  String get photoUpdated => _da ? 'Billedet er opdateret.' : 'Photo updated.';
  String get renderNotConnected => _da
      ? 'Videoen bliver gemt her, når renderingen er koblet på.'
      : 'Your video will be saved here once rendering is connected.';
  String couldNotSave(String reason) => _da
      ? 'Videoen kunne ikke gemmes: $reason'
      : 'Could not save the video: $reason';

  // ── Misc ──────────────────────────────────────────────────────────────
  String get yourVideo => _da ? 'Din video' : 'Your video';
  String get appVersion => 'Funny You · Version 1.0.0';
}

extension SContext on BuildContext {
  /// `context.s.makeAVideo`
  S get s => S.of(this);
}
