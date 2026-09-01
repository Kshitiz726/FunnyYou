import 'package:flutter/material.dart';

/// A scenario the user's face gets placed into.
///
/// Artwork resolves in three steps: an AI preview generated from the user's own
/// photo, then bundled reference art at `assets/templates/<id>.jpg`, then the
/// scenario [icon] on its gradient. The catalogue grows without a code change.
@immutable
class VideoTemplate {
  const VideoTemplate({
    required this.id,
    required this.title,
    required this.icon,
    required this.category,
    required this.prompt,
    required this.gradient,
    this.tagline,
    this.isPremium = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final TemplateCategory category;

  /// Sent to the video-generation backend alongside the user's face.
  final String prompt;
  final List<Color> gradient;
  final String? tagline;
  final bool isPremium;

  String get assetPath => 'assets/templates/$id.jpg';

  @override
  bool operator ==(Object other) =>
      other is VideoTemplate && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum TemplateCategory {
  heroes('Heroes & Action', Icons.shield_rounded),
  entertainment('Entertainment', Icons.music_note_rounded),
  professions('Professions', Icons.work_rounded),
  fantasy('Royalty & Fantasy', Icons.auto_awesome_rounded),
  sports('Sports', Icons.sports_soccer_rounded),
  lifestyle('Travel & Lifestyle', Icons.beach_access_rounded);

  const TemplateCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

abstract final class TemplateCatalog {
  /// The full catalogue — 40 scenarios across six categories.
  static const List<VideoTemplate> all = [
    // ── Heroes & Action ──────────────────────────────────────────────────
    VideoTemplate(
      id: 'astronaut',
      title: 'Astronaut',
      icon: Icons.rocket_launch_rounded,
      category: TemplateCategory.heroes,
      tagline: 'Floating above the Earth',
      prompt:
          'Portrait of the person as a NASA astronaut in a white spacesuit, '
          'helmet visor up, floating in orbit with Earth glowing behind them, '
          'cinematic lighting',
      gradient: [Color(0xFF1E3A8A), Color(0xFF5B21B6)],
    ),
    VideoTemplate(
      id: 'superhero',
      title: 'Superhero',
      icon: Icons.bolt_rounded,
      category: TemplateCategory.heroes,
      tagline: 'Flying over the city',
      prompt:
          'The person as a classic superhero in a red cape and blue suit, '
          'flying above a sunlit city skyline, heroic pose, dynamic motion blur',
      gradient: [Color(0xFF2563EB), Color(0xFFDC2626)],
    ),
    VideoTemplate(
      id: 'comic_hero',
      title: 'Comic Book Hero',
      icon: Icons.auto_stories_rounded,
      category: TemplateCategory.heroes,
      tagline: 'Straight off the page',
      prompt:
          'The person drawn as a vintage comic book hero, bold ink outlines, '
          'halftone dots, POW action panel background',
      gradient: [Color(0xFFF97316), Color(0xFFDB2777)],
    ),
    VideoTemplate(
      id: 'knight',
      title: 'Medieval Knight',
      icon: Icons.shield_rounded,
      category: TemplateCategory.heroes,
      tagline: 'Armour and honour',
      prompt:
          'The person as a medieval knight in polished steel armour holding a '
          'sword, castle courtyard at golden hour',
      gradient: [Color(0xFF57534E), Color(0xFF92400E)],
    ),
    VideoTemplate(
      id: 'ninja',
      title: 'Ninja',
      icon: Icons.nightlight_rounded,
      category: TemplateCategory.heroes,
      tagline: 'Silent and swift',
      prompt:
          'The person as a ninja in dark robes on a moonlit rooftop in feudal '
          'Japan, mist, dramatic rim light',
      gradient: [Color(0xFF0F172A), Color(0xFF475569)],
    ),
    VideoTemplate(
      id: 'pirate',
      title: 'Pirate Captain',
      icon: Icons.sailing_rounded,
      category: TemplateCategory.heroes,
      tagline: 'Captain of the seas',
      // Verbatim from the workflow embedded in pirate_hq_nopolish.mp4 -- the
      // render this scenario is tuned to reproduce. Wan runs at cfg 1.0, so
      // the negative prompt is inert and this string is the only text that
      // reaches the model; rewording it changes the result.
      prompt:
          'A young man in a tricorn hat and a weathered pirate coat steering a '
          'ship wheel on a sailing ship at sea, cinematic, photorealistic',
      gradient: [Color(0xFF7C2D12), Color(0xFF164E63)],
    ),
    VideoTemplate(
      id: 'wizard',
      title: 'Wizard',
      icon: Icons.auto_fix_high_rounded,
      category: TemplateCategory.heroes,
      tagline: 'Casting a spell',
      prompt:
          'The person as a grand wizard with a long robe and glowing staff, '
          'magical sparks swirling in an ancient library',
      gradient: [Color(0xFF4C1D95), Color(0xFF0EA5E9)],
    ),
    VideoTemplate(
      id: 'detective',
      title: 'Detective',
      icon: Icons.person_search_rounded,
      category: TemplateCategory.heroes,
      tagline: 'On the case',
      prompt:
          'The person as a 1940s film-noir detective in a trench coat and '
          'fedora, rainy street, neon reflections',
      gradient: [Color(0xFF1F2937), Color(0xFF6D28D9)],
    ),

    // ── Entertainment ────────────────────────────────────────────────────
    VideoTemplate(
      id: 'rock_guitarist',
      title: 'Rock Guitarist',
      icon: Icons.music_note_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Headlining the show',
      prompt:
          'The person as a rock star playing electric guitar on a huge stage, '
          'spotlights and crowd, energetic',
      gradient: [Color(0xFF831843), Color(0xFFF59E0B)],
    ),
    VideoTemplate(
      id: 'pop_singer',
      title: 'Pop Singer',
      icon: Icons.mic_external_on_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Sold-out arena',
      prompt:
          'The person as a pop superstar singing into a microphone, sparkling '
          'outfit, arena lights and confetti',
      gradient: [Color(0xFFDB2777), Color(0xFF7C3AED)],
    ),
    VideoTemplate(
      id: 'dj',
      title: 'DJ',
      icon: Icons.headphones_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Dropping the beat',
      prompt:
          'The person as a festival DJ behind a glowing mixing deck, hands in '
          'the air, laser lights and smoke',
      gradient: [Color(0xFF0EA5E9), Color(0xFF7C3AED)],
    ),
    VideoTemplate(
      id: 'pianist',
      title: 'Concert Pianist',
      icon: Icons.piano_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'A grand performance',
      prompt:
          'The person playing a grand piano on a concert hall stage in formal '
          'evening wear, warm spotlight',
      gradient: [Color(0xFF1E293B), Color(0xFFB45309)],
    ),
    VideoTemplate(
      id: 'movie_star',
      title: 'Movie Star',
      icon: Icons.movie_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Red carpet ready',
      prompt:
          'The person as a glamorous movie star on the red carpet, camera '
          'flashes, elegant outfit, film premiere',
      gradient: [Color(0xFFB91C1C), Color(0xFFFBBF24)],
    ),
    VideoTemplate(
      id: 'ballroom_dancer',
      title: 'Ballroom Dancer',
      icon: Icons.music_video_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Gliding across the floor',
      prompt:
          'The person as an elegant ballroom dancer mid-spin in a grand hall '
          'with chandeliers, flowing costume',
      gradient: [Color(0xFF9D174D), Color(0xFF6366F1)],
    ),
    VideoTemplate(
      id: 'disco_dancer',
      title: 'Disco Dancer',
      icon: Icons.nightlife_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Saturday night fever',
      prompt:
          'The person as a 1970s disco dancer in a white suit under a mirror '
          'ball, glowing dance floor',
      gradient: [Color(0xFF7C3AED), Color(0xFFF59E0B)],
    ),
    VideoTemplate(
      id: 'cowboy',
      title: 'Cowboy',
      icon: Icons.landscape_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Wild West sunset',
      prompt:
          'The person as a cowboy in a hat and leather duster on horseback in '
          'a desert canyon at sunset',
      gradient: [Color(0xFFB45309), Color(0xFFDC2626)],
    ),

    // ── Professions ──────────────────────────────────────────────────────
    VideoTemplate(
      id: 'chef',
      title: 'Chef',
      icon: Icons.restaurant_rounded,
      category: TemplateCategory.professions,
      tagline: 'Michelin moment',
      prompt:
          'The person as a master chef in whites and a toque plating a dish in '
          'a professional kitchen, warm light',
      gradient: [Color(0xFFEA580C), Color(0xFF16A34A)],
    ),
    VideoTemplate(
      id: 'firefighter',
      title: 'Firefighter',
      icon: Icons.local_fire_department_rounded,
      category: TemplateCategory.professions,
      tagline: 'Hero on duty',
      prompt:
          'The person as a firefighter in full turnout gear and helmet in front '
          'of a fire engine, heroic',
      gradient: [Color(0xFFDC2626), Color(0xFF1F2937)],
    ),
    VideoTemplate(
      id: 'police_officer',
      title: 'Police Officer',
      icon: Icons.local_police_rounded,
      category: TemplateCategory.professions,
      tagline: 'Keeping the peace',
      prompt:
          'The person as a police officer in uniform with a cap, city street '
          'background, confident stance',
      gradient: [Color(0xFF1E40AF), Color(0xFF0F172A)],
    ),
    VideoTemplate(
      id: 'doctor',
      title: 'Doctor',
      icon: Icons.medical_services_rounded,
      category: TemplateCategory.professions,
      tagline: 'On the ward',
      prompt:
          'The person as a doctor in a white coat with a stethoscope in a '
          'bright modern hospital, friendly smile',
      gradient: [Color(0xFF0EA5E9), Color(0xFF14B8A6)],
    ),
    VideoTemplate(
      id: 'pilot',
      title: 'Airline Pilot',
      icon: Icons.flight_rounded,
      category: TemplateCategory.professions,
      tagline: 'Cleared for takeoff',
      prompt:
          'The person as an airline captain in uniform in the cockpit of a jet, '
          'sunrise through the windscreen',
      gradient: [Color(0xFF1D4ED8), Color(0xFF38BDF8)],
    ),
    VideoTemplate(
      id: 'space_commander',
      title: 'Space Commander',
      icon: Icons.satellite_alt_rounded,
      category: TemplateCategory.professions,
      tagline: 'Bridge of the starship',
      prompt:
          'The person as a starship commander in a futuristic uniform on a '
          'glowing bridge, holographic displays',
      gradient: [Color(0xFF312E81), Color(0xFF06B6D4)],
    ),
    VideoTemplate(
      id: 'scientist',
      title: 'Scientist',
      icon: Icons.science_rounded,
      category: TemplateCategory.professions,
      tagline: 'Big discovery',
      prompt:
          'The person as a scientist in a lab coat and safety glasses beside '
          'glowing beakers in a research lab',
      gradient: [Color(0xFF15803D), Color(0xFF0891B2)],
    ),
    VideoTemplate(
      id: 'teacher',
      title: 'Teacher',
      icon: Icons.school_rounded,
      category: TemplateCategory.professions,
      tagline: 'Front of the class',
      prompt:
          'The person as a beloved teacher in front of a chalkboard in a warm '
          'classroom, holding a book',
      gradient: [Color(0xFFB45309), Color(0xFF4338CA)],
    ),

    // ── Royalty & Fantasy ────────────────────────────────────────────────
    VideoTemplate(
      id: 'king',
      title: 'King',
      icon: Icons.workspace_premium_rounded,
      category: TemplateCategory.fantasy,
      tagline: 'On the throne',
      prompt:
          'The person as a king in a golden crown and ermine robe seated on an '
          'ornate throne, royal hall',
      gradient: [Color(0xFF7C2D12), Color(0xFFFBBF24)],
    ),
    VideoTemplate(
      id: 'queen',
      title: 'Queen',
      icon: Icons.diamond_rounded,
      category: TemplateCategory.fantasy,
      tagline: 'Long may you reign',
      prompt:
          'The person as a queen in a jewelled crown and royal gown in a palace '
          'ballroom, regal lighting',
      gradient: [Color(0xFF9D174D), Color(0xFFFBBF24)],
    ),
    VideoTemplate(
      id: 'elf',
      title: 'Elf',
      icon: Icons.forest_rounded,
      category: TemplateCategory.fantasy,
      tagline: 'Guardian of the forest',
      prompt:
          'The person as a woodland elf with pointed ears and a leaf-green '
          'cloak in an enchanted forest, soft god rays',
      gradient: [Color(0xFF166534), Color(0xFF65A30D)],
    ),
    VideoTemplate(
      id: 'fairy',
      title: 'Fairy',
      icon: Icons.auto_awesome_rounded,
      category: TemplateCategory.fantasy,
      tagline: 'A sprinkle of magic',
      prompt:
          'The person as a glowing fairy with translucent wings hovering in a '
          'flower meadow at dusk, fireflies',
      gradient: [Color(0xFFDB2777), Color(0xFF22D3EE)],
    ),

    // ── Sports ───────────────────────────────────────────────────────────
    VideoTemplate(
      id: 'footballer',
      title: 'Football Star',
      icon: Icons.sports_soccer_rounded,
      category: TemplateCategory.sports,
      tagline: 'Scoring the winner',
      prompt:
          'The person as a football star celebrating a goal in a packed '
          'stadium, team kit, floodlights',
      gradient: [Color(0xFF15803D), Color(0xFF0EA5E9)],
    ),
    VideoTemplate(
      id: 'basketball_player',
      title: 'Basketball Player',
      icon: Icons.sports_basketball_rounded,
      category: TemplateCategory.sports,
      tagline: 'Slam dunk',
      prompt:
          'The person as a basketball player mid slam-dunk in an arena, jersey, '
          'dramatic low angle',
      gradient: [Color(0xFFC2410C), Color(0xFF1E293B)],
    ),
    VideoTemplate(
      id: 'tennis_champion',
      title: 'Tennis Champion',
      icon: Icons.sports_tennis_rounded,
      category: TemplateCategory.sports,
      tagline: 'Match point',
      prompt:
          'The person as a tennis champion serving on centre court, whites, '
          'trophy nearby, bright daylight',
      gradient: [Color(0xFF65A30D), Color(0xFF0284C7)],
    ),
    VideoTemplate(
      id: 'golfer',
      title: 'Professional Golfer',
      icon: Icons.sports_golf_rounded,
      category: TemplateCategory.sports,
      tagline: 'Perfect swing',
      prompt:
          'The person as a pro golfer mid-swing on a manicured green, rolling '
          'hills, clear blue sky',
      gradient: [Color(0xFF16A34A), Color(0xFF7DD3FC)],
    ),
    VideoTemplate(
      id: 'race_driver',
      title: 'Formula Race Driver',
      icon: Icons.sports_motorsports_rounded,
      category: TemplateCategory.sports,
      tagline: 'Podium finish',
      prompt:
          'The person as a Formula 1 driver in a racing suit and helmet beside '
          'a race car on the grid, motion energy',
      gradient: [Color(0xFFDC2626), Color(0xFF1F2937)],
    ),
    VideoTemplate(
      id: 'boxer',
      title: 'Boxing Champion',
      icon: Icons.sports_mma_rounded,
      category: TemplateCategory.sports,
      tagline: 'Belt raised high',
      prompt:
          'The person as a boxing champion raising a championship belt in the '
          'ring, spotlight, crowd in the dark',
      gradient: [Color(0xFF7F1D1D), Color(0xFFF59E0B)],
    ),

    // ── Travel & Lifestyle ───────────────────────────────────────────────
    VideoTemplate(
      id: 'tropical_traveler',
      title: 'Tropical Traveller',
      icon: Icons.beach_access_rounded,
      category: TemplateCategory.lifestyle,
      tagline: 'Island time',
      prompt:
          'The person in a colourful floral shirt on a tropical beach with palm '
          'trees and turquoise water, golden hour',
      gradient: [Color(0xFF0891B2), Color(0xFFFB923C)],
    ),
    VideoTemplate(
      id: 'yacht_owner',
      title: 'Luxury Yacht Owner',
      icon: Icons.directions_boat_rounded,
      category: TemplateCategory.lifestyle,
      tagline: 'Anchored in paradise',
      prompt:
          'The person relaxing on the deck of a luxury yacht in the '
          'Mediterranean, sunglasses, sparkling sea',
      gradient: [Color(0xFF0369A1), Color(0xFF7DD3FC)],
    ),
    VideoTemplate(
      id: 'jet_traveler',
      title: 'Private Jet Traveller',
      icon: Icons.airplane_ticket_rounded,
      category: TemplateCategory.lifestyle,
      tagline: 'Wheels up',
      prompt:
          'The person stepping off a private jet in stylish clothes, sunny '
          'tarmac, luxury travel vibe',
      gradient: [Color(0xFF334155), Color(0xFFFBBF24)],
    ),
    VideoTemplate(
      id: 'millionaire',
      title: 'Millionaire',
      icon: Icons.paid_rounded,
      category: TemplateCategory.lifestyle,
      tagline: 'Living the dream',
      prompt:
          'The person as a millionaire in a tailored suit in a penthouse with a '
          'city skyline view, opulent',
      gradient: [Color(0xFF1E293B), Color(0xFFD97706)],
      isPremium: true,
    ),
    VideoTemplate(
      id: 'santa',
      title: 'Santa Claus',
      icon: Icons.card_giftcard_rounded,
      category: TemplateCategory.lifestyle,
      tagline: 'Ho ho ho!',
      prompt:
          'The person as Santa Claus in a red suit and white beard beside a '
          'decorated Christmas tree, snowy window',
      gradient: [Color(0xFFB91C1C), Color(0xFF15803D)],
    ),
    VideoTemplate(
      id: 'dog_walker',
      title: 'Dog Walker',
      icon: Icons.pets_rounded,
      category: TemplateCategory.lifestyle,
      tagline: 'Happy chaos',
      prompt:
          'The person walking six excited dogs through a sunny park, leads '
          'tangled, joyful and funny',
      gradient: [Color(0xFF65A30D), Color(0xFFFACC15)],
    ),
  ];

  static List<VideoTemplate> byCategory(TemplateCategory category) =>
      all.where((t) => t.category == category).toList(growable: false);

  static VideoTemplate byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);

  /// Hand-picked hero scenarios surfaced on the home screen.
  static List<VideoTemplate> get featured => const [
        'superhero',
        'astronaut',
        'rock_guitarist',
        'king',
        'race_driver',
        'tropical_traveler',
      ].map(byId).toList(growable: false);

  /// How many tiles of each home-screen section get a generated preview.
  ///
  /// Every preview is a paid API call, so this is deliberately the *visible*
  /// count — the tiles a user sees before scrolling — not the whole catalogue.
  /// Generating all 40 costs roughly 10x this for art most people never see.
  static const int styleRailPreviewCount = 5;
  static const int discoveryPreviewCount = 2;

  /// The scenarios worth spending a generation on, deduplicated.
  ///
  /// The two sections overlap (Discovery opens on the same hero scenarios), so
  /// this is usually smaller than the two counts added together — which is the
  /// point: pay once for a tile that appears twice.
  static List<VideoTemplate> get previewSet {
    final seen = <String>{};
    return [
      ...featured.take(styleRailPreviewCount),
      ...all.take(discoveryPreviewCount),
    ].where((t) => seen.add(t.id)).toList(growable: false);
  }

  /// Whether this scenario shows real generated art to a user who has not paid.
  static bool isFreePreview(String templateId) =>
      previewSet.any((t) => t.id == templateId);

  static List<VideoTemplate> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.category.label.toLowerCase().contains(q) ||
            (t.tagline?.toLowerCase().contains(q) ?? false))
        .toList(growable: false);
  }
}
