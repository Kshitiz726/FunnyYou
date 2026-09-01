import '../../data/templates.dart';
import 'strings.dart';

/// Danish names for the catalogue.
///
/// Kept out of `templates.dart` so the catalogue stays a plain list of
/// scenarios — adding a language means adding a table here, not touching all
/// forty entries.
const _daTitles = <String, String>{
  'astronaut': 'Astronaut',
  'superhero': 'Superhelt',
  'comic_hero': 'Tegneseriehelt',
  'knight': 'Middelalderridder',
  'ninja': 'Ninja',
  'pirate': 'Piratkaptajn',
  'wizard': 'Troldmand',
  'detective': 'Detektiv',
  'rock_guitarist': 'Rockguitarist',
  'pop_singer': 'Popsanger',
  'dj': 'DJ',
  'pianist': 'Koncertpianist',
  'movie_star': 'Filmstjerne',
  'ballroom_dancer': 'Standarddanser',
  'disco_dancer': 'Diskodanser',
  'cowboy': 'Cowboy',
  'chef': 'Kok',
  'firefighter': 'Brandmand',
  'police_officer': 'Politibetjent',
  'doctor': 'Læge',
  'pilot': 'Pilot',
  'space_commander': 'Rumkommandør',
  'scientist': 'Forsker',
  'teacher': 'Lærer',
  'king': 'Konge',
  'queen': 'Dronning',
  'elf': 'Elver',
  'fairy': 'Fe',
  'footballer': 'Fodboldstjerne',
  'basketball_player': 'Basketballspiller',
  'tennis_champion': 'Tennismester',
  'golfer': 'Golfspiller',
  'race_driver': 'Racerkører',
  'boxer': 'Boksemester',
  'tropical_traveler': 'Tropisk rejsende',
  'yacht_owner': 'Luksusyachtejer',
  'jet_traveler': 'Privatflyrejsende',
  'millionaire': 'Millionær',
  'santa': 'Julemand',
  'dog_walker': 'Hundelufter',
};

const _daTaglines = <String, String>{
  'astronaut': 'Svævende over Jorden',
  'superhero': 'Flyver over byen',
  'comic_hero': 'Lige ud af tegneserien',
  'knight': 'Rustning og ære',
  'ninja': 'Lydløs og lynhurtig',
  'pirate': 'Havets kaptajn',
  'wizard': 'Kaster en trylleformular',
  'detective': 'På sagen',
  'rock_guitarist': 'Aftenens hovednavn',
  'pop_singer': 'Udsolgt arena',
  'dj': 'Sætter beatet i gang',
  'pianist': 'En storslået optræden',
  'movie_star': 'Klar til den røde løber',
  'ballroom_dancer': 'Glider hen over gulvet',
  'disco_dancer': 'Lørdagsfeber',
  'cowboy': 'Solnedgang i Det Vilde Vesten',
  'chef': 'Michelin-øjeblik',
  'firefighter': 'Helt på vagt',
  'police_officer': 'Holder ro og orden',
  'doctor': 'På afdelingen',
  'pilot': 'Klar til start',
  'space_commander': 'På rumskibets bro',
  'scientist': 'Stor opdagelse',
  'teacher': 'Foran klassen',
  'king': 'På tronen',
  'queen': 'Længe leve dronningen',
  'elf': 'Skovens vogter',
  'fairy': 'Et drys magi',
  'footballer': 'Scorer sejrsmålet',
  'basketball_player': 'Slam dunk',
  'tennis_champion': 'Matchbold',
  'golfer': 'Det perfekte sving',
  'race_driver': 'På podiet',
  'boxer': 'Bæltet i vejret',
  'tropical_traveler': 'Ø-tid',
  'yacht_owner': 'For anker i paradis',
  'jet_traveler': 'Hjulene er oppe',
  'millionaire': 'Lever drømmen',
  'santa': 'Ho ho ho!',
  'dog_walker': 'Glad kaos',
};

const _daCategories = <TemplateCategory, String>{
  TemplateCategory.heroes: 'Helte & action',
  TemplateCategory.entertainment: 'Underholdning',
  TemplateCategory.professions: 'Erhverv',
  TemplateCategory.fantasy: 'Kongelige & fantasi',
  TemplateCategory.sports: 'Sport',
  TemplateCategory.lifestyle: 'Rejser & livsstil',
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
