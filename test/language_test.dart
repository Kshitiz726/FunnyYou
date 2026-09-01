import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/core/i18n/strings.dart';
import 'package:funny_you/core/i18n/template_strings.dart';
import 'package:funny_you/data/templates.dart';
import 'package:funny_you/features/home/home_shell.dart';
import 'package:funny_you/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every scenario and category has a Danish name', () {
    const da = S(AppLang.da);
    const en = S(AppLang.en);

    final ids = TemplateCatalog.all.map((t) => t.id).toSet();

    expect(
      ids.difference(danishTitleIds),
      isEmpty,
      reason: 'these scenarios would show an English name in Danish',
    );
    expect(ids.difference(danishTaglineIds), isEmpty);
    expect(danishCategories, TemplateCategory.values.toSet());

    for (final t in TemplateCatalog.all) {
      expect(t.titleIn(en), t.title, reason: '${t.id} English title changed');
      expect(t.titleIn(da), isNotEmpty);
    }
  });

  testWidgets('switching language re-renders the app in Danish',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'face_photo_path': '',
    });
    final state = await AppState.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();

    // English by default, whatever the phone's own locale is.
    expect(find.text('Make a video'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);

    await state.setLang(AppLang.da);
    await tester.pump();

    expect(find.text('Lav en video'), findsOneWidget);
    expect(find.text('Lav'), findsOneWidget);
    expect(find.text('Make a video'), findsNothing);
  });

  testWidgets('the language choice survives a restart', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'da'});
    final state = await AppState.load();

    expect(state.lang, AppLang.da);
  });
}
