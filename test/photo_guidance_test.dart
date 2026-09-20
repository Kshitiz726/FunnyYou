import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/core/i18n/strings.dart';
import 'package:funny_you/features/capture/photo_quality.dart';

/// The client asked for something that "controls the lighting quality, angle,
/// etc". Telling somebody their head is turned without saying how far leaves
/// them guessing, so the wording carries the measurement -- and has to hold
/// up when there is no measurement to carry.
void main() {
  final en = S(AppLang.en);
  final da = S(AppLang.da);

  test('every finding has words in both languages', () {
    for (final issue in PhotoIssue.values) {
      final finding = PhotoFinding(issue, amount: 30);
      for (final s in [en, da]) {
        final message = photoIssueMessage(s, finding);
        expect(message.trim(), isNotEmpty, reason: '$issue has no message');
        expect(
          message,
          isNot(contains('null')),
          reason: '$issue leaked a null into the sentence',
        );
      }
    }
  });

  group('saying how much to adjust', () {
    test('an angle is quoted in degrees', () {
      final message = photoIssueMessage(
        en,
        const PhotoFinding(PhotoIssue.turned, amount: 43),
      );
      expect(message, contains('43'));
      expect(message, contains('°'));
    });

    test('a face too small is quoted as how much closer', () {
      final message = photoIssueMessage(
        en,
        const PhotoFinding(PhotoIssue.tooFar, amount: 100),
      );
      expect(message, contains('100%'));
      expect(message, contains('closer'));
    });

    test('the chin message names the axis it is about', () {
      final message = photoIssueMessage(
        en,
        const PhotoFinding(PhotoIssue.chin, amount: 25),
      );
      expect(message, contains('25'));
      expect(message.toLowerCase(), contains('eye level'));
    });
  });

  group('when there is nothing to measure', () {
    test('the sentence still reads, without a number', () {
      for (final issue in [
        PhotoIssue.turned,
        PhotoIssue.chin,
        PhotoIssue.tilted,
        PhotoIssue.tooFar,
      ]) {
        final message = photoIssueMessage(en, PhotoFinding(issue));
        expect(message, isNot(contains('°')), reason: '$issue invented an angle');
        expect(message, isNot(contains('%')), reason: '$issue invented a share');
        expect(RegExp(r'\d').hasMatch(message), isFalse, reason: '$issue');
      }
    });

    test('a nonsense reading is treated as no reading', () {
      // A zero or negative measurement means the box could not work it out,
      // and "turned about 0 degrees" would be worse than saying nothing.
      final message = photoIssueMessage(
        en,
        const PhotoFinding(PhotoIssue.turned, amount: 0),
      );
      expect(RegExp(r'\d').hasMatch(message), isFalse);
    });
  });

  _panel();

  test('the findings the phone makes on its own carry no number', () {
    // Exposure and focus are read on the phone, which has no idea where the
    // face is, so these must never try to quote an angle.
    for (final issue in [
      PhotoIssue.tooDark,
      PhotoIssue.tooBright,
      PhotoIssue.blurry,
    ]) {
      final message = photoIssueMessage(en, PhotoFinding(issue));
      expect(message.trim(), isNotEmpty);
      expect(message, isNot(contains('°')));
    }
  });
}

/// The panel the client will actually look at. Every check has to be listed,
/// passes included -- one that only appears when it is unhappy is
/// indistinguishable from one that was never built.
void _panel() {
  final en = S(AppLang.en);

  group('the photo check panel', () {
    test('a clean photo still lists every check, all passing', () {
      final lines = photoCheckLines(
        en,
        const PhotoReport(
          faceCount: 1,
          yaw: -4,
          pitch: 2,
          roll: -3,
          faceShare: 0.4,
          fromBackend: true,
        ),
      );

      expect(
        lines.map((l) => l.label),
        containsAll([
          en.checkLighting,
          en.checkSharpness,
          en.checkFace,
          en.checkAngle,
          en.checkFraming,
        ]),
      );
      expect(
        lines.every((l) => l.state == CheckState.good),
        isTrue,
        reason: 'a good photo showed a warning',
      );
    });

    test('the angle line quotes the measured degrees either way', () {
      final straight = photoCheckLines(
        en,
        const PhotoReport(faceCount: 1, yaw: -13, fromBackend: true),
      ).firstWhere((l) => l.label == en.checkAngle);
      expect(straight.value, contains('13'));
      expect(straight.state, CheckState.good);

      final turned = photoCheckLines(
        en,
        const PhotoReport(
          faceCount: 1,
          yaw: -43,
          issues: [PhotoIssue.turned],
          fromBackend: true,
        ),
      ).firstWhere((l) => l.label == en.checkAngle);
      expect(turned.value, contains('43'));
      expect(turned.state, CheckState.warning);
    });

    test('with no face there is no angle to report', () {
      final lines = photoCheckLines(
        en,
        const PhotoReport(issues: [PhotoIssue.noFace], fromBackend: true),
      );
      expect(lines.map((l) => l.label), isNot(contains(en.checkAngle)));
      expect(
        lines.firstWhere((l) => l.label == en.checkFace).state,
        CheckState.warning,
      );
    });

    test('offline it says the face checks need a connection, not that they passed',
        () {
      final lines = photoCheckLines(en, const PhotoReport());
      final face = lines.firstWhere((l) => l.label == en.checkFace);
      expect(face.state, CheckState.unknown);
      expect(face.value, en.checkNeedsConnection);
      expect(lines.map((l) => l.label), isNot(contains(en.checkAngle)));
    });

    test('the phone-only lighting result still shows', () {
      final lines = photoCheckLines(
        en,
        const PhotoReport(issues: [PhotoIssue.tooDark]),
      );
      final light = lines.firstWhere((l) => l.label == en.checkLighting);
      expect(light.value, en.checkDark);
      expect(light.state, CheckState.warning);
    });
  });
}
