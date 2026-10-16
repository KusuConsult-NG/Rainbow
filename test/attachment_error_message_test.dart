// What somebody is told when an attachment fails.
//
// The four attachment buttons called image_picker with no error handling at
// all. pickImage and pickVideo THROW when the camera is unavailable or the
// permission has been refused — on a real handset the ordinary case, not an
// exotic one — and the exception went nowhere: the person pressed SCAN PHOTO,
// nothing happened, and nothing on the screen said why.
//
// The browser harness now drives the SUCCESS path against a real file input
// and a real insert. This covers the other half, which no browser will produce
// on demand: what is said when the picker throws.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/report/report_details_screen.dart';

void main() {
  group('when an attachment fails', () {
    test('a refused permission is named, because it is the one they can fix',
        () {
      for (final error in <Object>[
        'PlatformException(camera_access_denied, The user did not allow camera access.)',
        Exception('Permission denied'),
        'photo_access_denied',
      ]) {
        expect(
          attachmentErrorMessage(error),
          contains('has not given Plateau Eye access'),
          reason: '$error should read as a permission problem',
        );
      }
    });

    test('anything else says plainly that it did not work here', () {
      expect(
        attachmentErrorMessage(Exception('no camera hardware')),
        contains('did not work on this phone'),
      );
    });

    test('both endings say the report can still be sent', () {
      // The report matters more than the photo, and a dead end in the middle of
      // an emergency is how a report gets abandoned.
      for (final error in <Object>[
        Exception('Permission denied'),
        Exception('something else entirely'),
      ]) {
        expect(attachmentErrorMessage(error), contains('You can still'));
      }
    });

    test('never shows the raw exception to the person', () {
      // "PlatformException(camera_access_denied, ...)" is for the log, not for
      // somebody who is trying to report a fire.
      final message = attachmentErrorMessage(
        'PlatformException(camera_access_denied, The user did not allow camera access.)',
      );
      expect(message, isNot(contains('PlatformException')));
      expect(message, isNot(contains('camera_access_denied')));
    });
  });
}
