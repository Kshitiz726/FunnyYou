import 'dart:async';

import 'package:flutter/foundation.dart';

/// The user-facing stages of a render. Kept deliberately plain-spoken — the
/// audience is not technical.
enum GenerationStage {
  uploading('Getting your photo ready'),
  matchingFace('Finding your face'),
  buildingScene('Building the scene'),
  rendering('Making your video'),
  finishing('Adding the finishing touches'),
  done('All done!');

  const GenerationStage(this.label);

  final String label;
}

@immutable
class GenerationProgress {
  const GenerationProgress({
    required this.stage,
    required this.value,
    this.detail,
    this.estimatedRemaining,
    this.videoPath,
  });

  final GenerationStage stage;

  /// Overall completion, 0..1.
  final double value;

  /// Exactly what the renderer is doing right now, in its own numbers —
  /// "Pass 1/2 · Rendering 3/8 · 37%". A Wan render spends its first quarter
  /// loading models and segmenting, where there is no fraction to report, so
  /// this is the only thing that moves during those minutes.
  final String? detail;
  final Duration? estimatedRemaining;

  /// Local path of the finished file. Only set on the final
  /// [GenerationStage.done] event.
  final String? videoPath;
}

class GenerationRequest {
  const GenerationRequest({
    required this.facePhotoPath,
    required this.prompt,
    this.templateId,
  });

  final String facePhotoPath;
  final String prompt;
  final String? templateId;
}

class GenerationResult {
  const GenerationResult({required this.videoPath, this.thumbnailPath});

  final String videoPath;
  final String? thumbnailPath;
}

class GenerationException implements Exception {
  const GenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Contract the UI codes against. Swapping the mock for a real backend is a
/// one-line change in `ServiceLocator` — no screen needs to know.
abstract interface class GenerationService {
  Stream<GenerationProgress> generate(GenerationRequest request);

  Future<void> cancel();
}

/// Local stand-in that plays through every stage so the full flow is testable
/// on a Windows desktop build with no backend attached.
class MockGenerationService implements GenerationService {
  MockGenerationService({this.totalDuration = const Duration(seconds: 16)});

  final Duration totalDuration;
  bool _cancelled = false;

  static const _stageWeights = <GenerationStage, double>{
    GenerationStage.uploading: 0.10,
    GenerationStage.matchingFace: 0.18,
    GenerationStage.buildingScene: 0.24,
    GenerationStage.rendering: 0.36,
    GenerationStage.finishing: 0.12,
  };

  @override
  Stream<GenerationProgress> generate(GenerationRequest request) async* {
    _cancelled = false;
    const tick = Duration(milliseconds: 90);
    final steps = totalDuration.inMilliseconds ~/ tick.inMilliseconds;

    var elapsed = 0.0;
    for (var i = 0; i <= steps; i++) {
      if (_cancelled) {
        throw const GenerationException('Cancelled');
      }
      await Future<void>.delayed(tick);
      elapsed = i / steps;

      yield GenerationProgress(
        stage: _stageFor(elapsed),
        value: elapsed,
        estimatedRemaining: Duration(
          milliseconds:
              ((1 - elapsed) * totalDuration.inMilliseconds).round(),
        ),
      );
    }

    yield const GenerationProgress(
      stage: GenerationStage.done,
      value: 1,
      estimatedRemaining: Duration.zero,
    );
  }

  GenerationStage _stageFor(double progress) {
    var cursor = 0.0;
    for (final entry in _stageWeights.entries) {
      cursor += entry.value;
      if (progress <= cursor) return entry.key;
    }
    return GenerationStage.finishing;
  }

  @override
  Future<void> cancel() async => _cancelled = true;
}
