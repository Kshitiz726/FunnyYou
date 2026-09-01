import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/app/app.dart';
import 'package:funny_you/data/templates.dart';
import 'package:funny_you/features/home/home_shell.dart';
import 'package:funny_you/features/onboarding/welcome_screen.dart';
import 'package:funny_you/features/paywall/paywall_screen.dart';
import 'package:funny_you/features/templates/template_picker_screen.dart';
import 'package:funny_you/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _state(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return AppState.load();
}

/// The default 800x600 test surface is nothing like a phone; pin it to an
/// iPhone 15 logical size so layout assertions mean something.
void _useIPhoneViewport(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1179, 2556)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('first launch shows the welcome flow', (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(FunnyYouApp(state: await _state({})));
    await tester.pump();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Funny You!'), findsOneWidget);
  });

  testWidgets('welcome pages advance through all four steps', (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(FunnyYouApp(state: await _state({})));
    await tester.pump();

    for (final title in [
      'Take one photo',
      'Pick your favourite',
      'We make your video',
      'Watch, save and share',
    ]) {
      await tester.tap(find.text('Next'));
      // Not pumpAndSettle: the ambient backdrop and step animations loop
      // forever by design, so settling would never complete.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // findsAtLeast, not findsOne: some step copy is echoed inside the
      // phone mockup it describes.
      expect(find.text(title), findsAtLeastNWidgets(1));
    }

    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('a returning user lands on the home screen', (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(
      FunnyYouApp(state: await _state({'onboarding_complete': true})),
    );
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('finishing onboarding hands off to home, then the paywall',
      (tester) async {
    _useIPhoneViewport(tester);
    await tester.pumpWidget(
      FunnyYouApp(
        // A face photo already on file, so the flow goes straight to the
        // scenario picker.
        state: await _state({'face_photo_path': 'C:/tmp/face.jpg'}),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(TemplatePickerScreen), findsOneWidget);

    await tester.tap(find.textContaining('Turn me into'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The root has been swapped for the home screen underneath, and the
    // paywall is stacked on top — a regression here means the hand-off lost
    // its navigator.
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
  });

  test('the catalogue holds 40 templates across every category', () {
    expect(TemplateCatalog.all, hasLength(40));

    final ids = TemplateCatalog.all.map((t) => t.id).toSet();
    expect(ids, hasLength(40), reason: 'template ids must be unique');

    for (final category in TemplateCategory.values) {
      expect(
        TemplateCatalog.byCategory(category),
        isNotEmpty,
        reason: '${category.label} should not be empty',
      );
    }

    // Every template needs a prompt for the render backend.
    for (final template in TemplateCatalog.all) {
      expect(template.prompt.trim(), isNotEmpty);
      expect(template.gradient, hasLength(2));
    }
  });

  test('credits gate generation', () async {
    final state = await _state({});
    expect(state.canGenerate, isFalse);

    await state.addCredits(2);
    expect(state.credits, 2);
    expect(await state.consumeCredit(), isTrue);
    expect(state.credits, 1);
  });

  test('draft prompt merges template and custom text', () async {
    final state = await _state({});
    state.selectTemplate(TemplateCatalog.byId('chef'));
    state.setCustomPrompt('wearing a silly hat');

    expect(state.draftPrompt, contains('master chef'));
    expect(state.draftPrompt, endsWith('wearing a silly hat'));
  });

  test('previews are generated only for tiles visible without scrolling', () {
    final set = TemplateCatalog.previewSet;

    // Every preview is a GPU face swap (~20s). The two home-screen sections
    // overlap, so the visible tiles cost 5 generations rather than 40 - an 8x
    // saving that has to survive anyone reordering the catalogue.
    expect(set, hasLength(5));
    expect(set.map((t) => t.id).toSet(), hasLength(set.length),
        reason: 'a duplicate would be paid for twice');

    for (final template in TemplateCatalog.featured.take(
        TemplateCatalog.styleRailPreviewCount)) {
      expect(set, contains(template), reason: 'style rail tile has no preview');
    }
    for (final template
        in TemplateCatalog.all.take(TemplateCatalog.discoveryPreviewCount)) {
      expect(set, contains(template), reason: 'discovery tile has no preview');
    }
  });

  test('the catalogue beyond the free previews is locked until purchase', () async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.load();

    // Free: the four visible tiles are real art, everything else is padlocked.
    expect(state.isTemplateLocked('superhero'), isFalse);
    expect(state.isTemplateLocked('chef'), isTrue);

    await state.addCredits(5);
    expect(state.isTemplateLocked('chef'), isFalse);

    // Spending the last credit must not take the catalogue back off a customer.
    await state.consumeCredit();
    await state.consumeCredit();
    await state.consumeCredit();
    await state.consumeCredit();
    await state.consumeCredit();
    expect(state.credits, 0);
    expect(state.isTemplateLocked('chef'), isFalse,
        reason: 're-locking a paying user reads as a bug');
  });
}
