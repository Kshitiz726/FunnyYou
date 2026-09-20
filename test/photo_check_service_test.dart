import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/features/capture/photo_quality.dart';
import 'package:funny_you/services/photo_check_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A check that blocks a good photo is worse than one that misses a bad one,
/// so almost all of this is about the ways it must stay quiet.
void main() {
  final pixels = Uint8List.fromList([1, 2, 3, 4]);

  PhotoCheckService serviceReturning(
    Object? body, {
    int status = 200,
    Duration delay = Duration.zero,
  }) {
    return PhotoCheckService(
      baseUrl: 'https://box.invalid',
      headers: const {},
      timeout: const Duration(milliseconds: 200),
      client: MockClient((request) async {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        return http.Response(
          body is String ? body : jsonEncode(body),
          status,
        );
      }),
    );
  }

  group('what the box found', () {
    test('a turned head comes back as a turned head', () async {
      final service = serviceReturning({
        'issues': ['turned'],
        'usable': true,
      });
      expect(await service.inspectBytes(pixels), PhotoIssue.turned);
    });

    test('no face wins over the softer findings beside it', () async {
      // The box orders worst-first; the app shows one message, so it has to
      // be the one that means "this cannot work".
      final service = serviceReturning({
        'issues': ['no_face', 'blurry'],
      });
      expect(await service.inspectBytes(pixels), PhotoIssue.noFace);
    });

    test('every code the box can send has something to say', () async {
      const codes = {
        'no_face': PhotoIssue.noFace,
        'many_faces': PhotoIssue.manyFaces,
        'turned': PhotoIssue.turned,
        'chin': PhotoIssue.chin,
        'tilted': PhotoIssue.tilted,
        'too_far': PhotoIssue.tooFar,
        'too_dark': PhotoIssue.tooDark,
        'too_bright': PhotoIssue.tooBright,
        'blurry': PhotoIssue.blurry,
      };
      for (final entry in codes.entries) {
        expect(
          PhotoCheckService.issueFromCode(entry.key),
          entry.value,
          reason: '${entry.key} has no mapping',
        );
      }
    });

    test('a code this build has never heard of is skipped, not shown',
        () async {
      // A newer box must not be able to make an older app show a blank
      // warning it has no words for.
      final service = serviceReturning({
        'issues': ['sunglasses', 'turned'],
      });
      expect(await service.inspectBytes(pixels), PhotoIssue.turned);
    });
  });

  group('failing open', () {
    test('an empty finding accepts the photo', () async {
      expect(
        await serviceReturning({'issues': <String>[]}).inspectBytes(pixels),
        isNull,
      );
    });

    test('a server error accepts the photo', () async {
      expect(
        await serviceReturning({'detail': 'boom'}, status: 500)
            .inspectBytes(pixels),
        isNull,
      );
    });

    test('a reply that is not JSON accepts the photo', () async {
      expect(
        await serviceReturning('<html>gateway timeout</html>')
            .inspectBytes(pixels),
        isNull,
      );
    });

    test('a slow box accepts the photo rather than holding the screen',
        () async {
      final service = serviceReturning(
        {
          'issues': ['turned'],
        },
        delay: const Duration(seconds: 2),
      );
      expect(await service.inspectBytes(pixels), isNull);
    });

    test('with no backend configured it never even asks', () async {
      var asked = false;
      final service = PhotoCheckService(
        baseUrl: '',
        headers: const {},
        client: MockClient((_) async {
          asked = true;
          return http.Response('{}', 200);
        }),
      );

      expect(service.enabled, isFalse);
      expect(await service.inspect('does-not-matter.jpg'), isNull);
      expect(asked, isFalse, reason: 'it called out with no backend set');
    });
  });
}
