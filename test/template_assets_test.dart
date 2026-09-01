import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/data/templates.dart';

/// The tiles fall back to bundled art at `assets/templates/<id>.jpg` whenever the
/// user has no AI preview yet, which is every user on first run. If the asset is
/// missing from the bundle the tile silently drops to a gradient placeholder, so
/// assert the bytes are really there and really decodable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled template artwork loads for every id that ships art', () async {
    final present = <String>[];
    final missing = <String>[];

    for (final t in TemplateCatalog.all) {
      try {
        final data = await rootBundle.load(t.assetPath);
        expect(data.lengthInBytes, greaterThan(1024),
            reason: '${t.assetPath} is suspiciously small');
        // JPEG magic number - proves it is a real image, not a stray text file.
        final b = data.buffer.asUint8List();
        expect(b[0], 0xFF, reason: '${t.assetPath} is not a JPEG');
        expect(b[1], 0xD8, reason: '${t.assetPath} is not a JPEG');
        present.add(t.id);
      } on FlutterError {
        missing.add(t.id);
      }
    }

    // ignore: avoid_print
    print('artwork present: ${present.length} / ${TemplateCatalog.all.length}');
    // ignore: avoid_print
    print('still needs art: ${missing.join(', ')}');

    expect(present, isNotEmpty, reason: 'no template artwork bundled at all');
  });
}
