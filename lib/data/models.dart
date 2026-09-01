import 'package:flutter/foundation.dart';

/// How the user described the video they want.
enum CreationSource { template, prompt, voice }

/// A finished (or in-flight) video the user made.
@immutable
class Creation {
  const Creation({
    required this.id,
    required this.templateId,
    required this.title,
    required this.createdAt,
    required this.source,
    this.videoPath,
    this.thumbnailPath,
    this.prompt,
  });

  final String id;
  final String templateId;
  final String title;
  final DateTime createdAt;
  final CreationSource source;

  /// Local file path of the rendered video. Null while still generating.
  final String? videoPath;
  final String? thumbnailPath;
  final String? prompt;

  Creation copyWith({String? videoPath, String? thumbnailPath}) => Creation(
        id: id,
        templateId: templateId,
        title: title,
        createdAt: createdAt,
        source: source,
        videoPath: videoPath ?? this.videoPath,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        prompt: prompt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'source': source.name,
        'videoPath': videoPath,
        'thumbnailPath': thumbnailPath,
        'prompt': prompt,
      };

  static Creation fromJson(Map<String, dynamic> json) => Creation(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        source: CreationSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => CreationSource.template,
        ),
        videoPath: json['videoPath'] as String?,
        thumbnailPath: json['thumbnailPath'] as String?,
        prompt: json['prompt'] as String?,
      );
}

/// A single purchasable plan shown on the paywall.
@immutable
class PricingPlan {
  const PricingPlan({
    required this.productId,
    required this.title,
    required this.priceLabel,
    required this.videoCount,
    this.subtitle,
    this.badge,
    this.perVideoLabel,
    this.isBestValue = false,
  });

  /// Must match the product identifier configured in App Store Connect.
  final String productId;
  final String title;
  final String priceLabel;
  final int videoCount;
  final String? subtitle;
  final String? badge;
  final String? perVideoLabel;
  final bool isBestValue;
}
