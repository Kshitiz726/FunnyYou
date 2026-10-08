import '../../data/templates.dart';
import 'strings.dart';

/// Danish names for the catalogue.
///
/// Kept out of `templates.dart` so the catalogue stays a plain list of
/// scenarios — adding a language means adding a table here, not touching
/// every entry.
const _daTitles = <String, String>{
  'gym': 'Fitnesslegende',
  'karaoke': 'Karaokeaften',
  'nurse': 'Den store flugt',
  'skating': 'Skaterparken',
  'hello': 'Hallo?!',
};

const _daTaglines = <String, String>{
  'gym': 'Hele centret stopper op',
  'karaoke': 'Synger af hjertens lyst',
  'nurse': 'Raketdrevet kørestol',
  'skating': 'Kan det stadig',
  'hello': 'Vinder kampen mod telefonen',
};

const _daCategories = <TemplateCategory, String>{
  TemplateCategory.everyday: 'Hverdag',
  TemplateCategory.entertainment: 'Underholdning',
  TemplateCategory.sports: 'Sport',
  TemplateCategory.action: 'Action',
};

/// Ids that have a Danish name and tagline.
///
/// Exposed so a test can prove the tables cover the whole catalogue — some
/// Danish names are legitimately identical to the English ones ("Astronaut",
/// "Ninja"), so comparing the two strings cannot detect a missing entry.
Set<String> get danishTitleIds => _daTitles.keys.toSet();
Set<String> get danishTaglineIds => _daTaglines.keys.toSet();
Set<TemplateCategory> get danishCategories => _daCategories.keys.toSet();

extension TemplateL10n on VideoTemplate {
  /// Falls back to the English name rather than showing an id — a missing
  /// translation should look untranslated, never broken.
  String titleIn(S s) =>
      s.lang == AppLang.da ? (_daTitles[id] ?? title) : title;

  String? taglineIn(S s) =>
      s.lang == AppLang.da ? (_daTaglines[id] ?? tagline) : tagline;
}

extension CategoryL10n on TemplateCategory {
  String labelIn(S s) =>
      s.lang == AppLang.da ? (_daCategories[this] ?? label) : label;
}
