// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/termii_service.dart';

void main() {
  group('TermiiService Verification PIN Tests', () {
    late TermiiService termiiService;

    setUp(() {
      termiiService = TermiiService();
    });

    test('should generate a valid 6-digit PIN and return it', () async {
      final pin = await termiiService.sendVerificationPin('+2348012345678');

      expect(pin, isNotNull);
      expect(pin!.length, equals(6));
      expect(int.tryParse(pin), isNotNull);

      final pinVal = int.parse(pin);
      expect(pinVal, greaterThanOrEqualTo(100000));
      expect(pinVal, lessThanOrEqualTo(999999));
    });

    test(
        'should generate different PINs on consecutive calls (dynamic and non-default)',
        () async {
      final pin1 = await termiiService.sendVerificationPin('+2348012345678');
      final pin2 = await termiiService.sendVerificationPin('+2348012345678');

      expect(pin1, isNotNull);
      expect(pin2, isNotNull);
      expect(pin1, isNot(equals(pin2)));
      expect(pin1, isNot(equals('123456')));
      expect(pin2, isNot(equals('123456')));
    });
  });
}
