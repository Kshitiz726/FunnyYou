import 'package:flutter/material.dart';

/// A scenario the user's face gets placed into.
///
/// Artwork resolves in three steps: an AI preview generated from the user's own
/// photo, then the scenario's own poster frame at
/// `assets/video_templates/<id>.jpg`, then the
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

  /// The poster frame lifted from this scenario's own clip, so the tile
  /// always shows the real scene the video will play.
  String get assetPath => 'assets/video_templates/$id.jpg';

  /// The fixed clip shown before paying: this scenario's own footage with the
  /// face blacked out and a padlock over it. Built by tools/lock_previews.py.
  ///
  /// Identical for every user, so showing it costs nothing and never queues a
  /// render. Generated art only ever happens after the paywall.
  String get lockedPreviewPath => 'assets/locked_previews/$id.mp4';

  @override
  bool operator ==(Object other) =>
      other is VideoTemplate && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum TemplateCategory {
  everyday('Everyday', Icons.emoji_emotions_rounded),
  entertainment('Entertainment', Icons.music_note_rounded),
  sports('Sports', Icons.sports_soccer_rounded),
  action('Action', Icons.bolt_rounded);

  const TemplateCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

abstract final class TemplateCatalog {
  /// The scenarios the client supplied, one clip each.
  ///
  /// This is the whole catalogue, not a sample of it. Every entry here has a
  /// real 10s portrait clip behind it; nothing is listed that cannot be made.
  /// The forty invented scenarios this replaced had no footage at all, so the
  /// picker was mostly "Soon" badges on scenes that did not exist.
  static const List<VideoTemplate> all = [
    VideoTemplate(
      id: 'gym',
      title: 'Gym Legend',
      icon: Icons.fitness_center_rounded,
      category: TemplateCategory.sports,
      tagline: 'The whole gym stops to watch',
      prompt:
          'The person as an older gym-goer in a cardigan deadlifting a heavily '
          'loaded barbell, young bodybuilders staring in disbelief behind them',
      gradient: [Color(0xFF334155), Color(0xFF0F172A)],
    ),
    VideoTemplate(
      id: 'karaoke',
      title: 'Karaoke Night',
      icon: Icons.mic_external_on_rounded,
      category: TemplateCategory.entertainment,
      tagline: 'Singing their heart out',
      prompt:
          'The person on a small bar stage under neon karaoke signs, belting '
          'into a microphone with the crowd cheering behind them',
      gradient: [Color(0xFF7F1D1D), Color(0xFF1E1B4B)],
    ),
    VideoTemplate(
      id: 'nurse',
      title: 'The Great Escape',
      icon: Icons.rocket_launch_rounded,
      category: TemplateCategory.action,
      tagline: 'Rocket powered wheelchair',
      prompt:
          'The person in a wheelchair fitted with roaring rocket thrusters, '
          'blasting out of a care home door past a startled nurse',
      gradient: [Color(0xFFB45309), Color(0xFF7C2D12)],
    ),
    VideoTemplate(
      id: 'skating',
      title: 'Skate Park',
      icon: Icons.skateboarding_rounded,
      category: TemplateCategory.sports,
      tagline: 'Still got it',
      prompt:
          'The person skateboarding down a concrete ramp at golden hour, flat '
          'cap on, a crowd of young skaters applauding',
      gradient: [Color(0xFFC2410C), Color(0xFF713F12)],
    ),
    VideoTemplate(
      id: 'hello',
      title: 'Hello?!',
      icon: Icons.phone_in_talk_rounded,
      category: TemplateCategory.everyday,
      tagline: 'Winning the fight with the phone',
      prompt:
          'The person sitting in a living room shouting into a smartphone held '
          'out at full stretch, squinting at it, then grinning in triumph',
      gradient: [Color(0xFF78350F), Color(0xFF292524)],
    ),
  ];

  static List<VideoTemplate> byCategory(TemplateCategory category) =>
      all.where((t) => t.category == category).toList(growable: false);

  static VideoTemplate byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);

  /// Order the home screen leads with. Five scenarios, so this is the whole
  /// catalogue; it stays a separate list because the *order* is the editorial
  /// decision and [all] is grouped by category.
  static List<VideoTemplate> get featured => const [
        'gym',
        'nurse',
        'karaoke',
        'skating',
        'hello',
      ].map(byId).toList(growable: false);

  /// How many scenarios get a thumbnail generated with the user's own face.
  ///
  /// The client's model, in his words: "Only the photo thumbnails for the
  /// person would be made with their face on it ... those 4 photos." Four,
  /// matching the four tiles the quick pick shows straight after the selfie.
  ///
  /// The video previews are deliberately NOT in this count. Those are fixed
  /// clips shipped with the app, identical for everyone, so they cost nothing
  /// to show and never wait on a render.
  static const int facePreviewCount = 4;

  /// The scenarios worth spending a face swap on.
  static List<VideoTemplate> get previewSet =>
      featured.take(facePreviewCount).toList(growable: false);

  /// The scenarios to put in front of someone who has just taken their selfie.
  ///
  /// Ordered by what the renderer can actually produce. [renderable] is the
  /// set the backend reports; null means it has not answered yet, or does not
  /// gate on templates at all, and then every scenario is fair game.
  ///
  /// Renderability has to lead. Ranking purely by "has a face preview" once
  /// put four scenarios on screen that the pod had no clip for — four tiles,
  /// four "Soon" badges, nothing to tap. Every scenario now ships with a clip,
  /// but the backend is still the authority on what it can actually render.
  ///
  /// Within each tier the preview set comes first, so a tile shows the user's
  /// own face wherever we have one.
  static List<VideoTemplate> shortlist({
    Set<String>? renderable,
    int count = 4,
  }) {
    final previewIds = previewSet.map((t) => t.id).toSet();
    bool ready(VideoTemplate t) =>
        renderable == null || renderable.contains(t.id);

    final ranked = [...previewSet, ...all];
    final seen = <String>{};
    final tiers = <List<VideoTemplate>>[[], [], [], []];

    for (final t in ranked) {
      if (!seen.add(t.id)) continue;
      final tier = switch ((ready(t), previewIds.contains(t.id))) {
        (true, true) => 0,
        (true, false) => 1,
        (false, true) => 2,
        (false, false) => 3,
      };
      tiers[tier].add(t);
    }

    return [for (final tier in tiers) ...tier].take(count).toList(
          growable: false,
        );
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
