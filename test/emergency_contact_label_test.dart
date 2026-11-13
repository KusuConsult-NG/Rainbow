import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/settings/settings_screen.dart';

void main() {
  test('a contact stored as a map reads as name and number', () {
    expect(
      emergencyContactLabel({'name': 'Ada', 'phone': '08031234567'}),
      'Ada · 08031234567',
    );
  });

  test('a contact stored as text is unchanged', () {
    expect(emergencyContactLabel('08031234567'), '08031234567');
  });

  test('a map missing a field does not print the word null', () {
    expect(emergencyContactLabel({'phone': '0803'}), '0803');
    expect(emergencyContactLabel({'name': 'Ada'}), 'Ada');
  });
}
