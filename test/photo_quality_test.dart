import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/features/capture/photo_quality.dart';

/// Renders [paint] to a [size]x[size] PNG, the way a camera would hand us one.
Future<Uint8List> _png(double size, void Function(Canvas, Size) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas, Size(size, size));
  final image = await recorder
      .endRecording()
      .toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Uint8List> _flat(Color color) =>
    _png(512, (canvas, size) => canvas.drawRect(
          Offset.zero & size,
          Paint()..color = color,
        ));

/// Mid-grey overall, but with hard edges everywhere: bright enough and sharp
/// enough, which is what a usable selfie looks like to this check.
Future<Uint8List> _checkerboard() => _png(512, (canvas, size) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      final black = Paint()..color = Colors.black;
      const cells = 8;
      final cell = size.width / cells;
      for (var y = 0; y < cells; y++) {
        for (var x = 0; x < cells; x++) {
          if ((x + y).isEven) continue;
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            black,
          );
        }
      }
    });

void main() {
  // toImage needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a well exposed, sharp photo raises nothing', () async {
    expect(await PhotoQuality.inspectBytes(await _checkerboard()), isNull);
  });

  test('an under-exposed photo is called dark', () async {
    expect(
      await PhotoQuality.inspectBytes(await _flat(const Color(0xFF101010))),
      PhotoIssue.tooDark,
    );
  });

  test('a blown out photo is called bright', () async {
    expect(
      await PhotoQuality.inspectBytes(await _flat(const Color(0xFFFAFAFA))),
      PhotoIssue.tooBright,
    );
  });

  test('a flat, detail-free photo is called blurry', () async {
    // Mid-grey: the exposure is fine, so the only thing left to fail on is
    // that there is no detail anywhere in the frame.
    expect(
      await PhotoQuality.inspectBytes(await _flat(const Color(0xFF808080))),
      PhotoIssue.blurry,
    );
  });

  test('something that is not an image is not an issue', () async {
    // Refusing a photo because *we* could not read it would block the user
    // over our own failure.
    expect(
      await PhotoQuality.inspectBytes(Uint8List.fromList([1, 2, 3, 4])),
      isNull,
    );
  });
}
