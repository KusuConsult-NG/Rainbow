/// One phone number, one person, one account.
///
/// ## Why this exists
///
/// A citizen signs in by entering their phone number and typing back an SMS
/// code. The number IS the identity — there is no email, no password, and
/// `profiles.phone` is UNIQUE — so the string that reaches Supabase decides
/// which account the person lands in.
///
/// The app passed whatever was typed, minus non-digits:
///
/// ```dart
/// final cleanPhone = phone.trim().replaceAll(RegExp('[^0-9+]'), '');
/// await client.auth.signInWithOtp(phone: cleanPhone);
/// ```
///
/// Nigerians write their number four ways — `08030001111`, `8030001111`,
/// `2348030001111`, `+234 803 000 1111` — and all four are the same phone. To
/// that code they are four different identities. The same person signing in
/// from the same handset a week later, typing it the other way they habitually
/// do, gets a DIFFERENT account: no incident history, no emergency contacts, no
/// emergency PIN, and their old reports attributed to a profile they can no
/// longer reach. Supabase also expects E.164 for `signInWithOtp`, so the local
/// forms are additionally at the mercy of whatever the SMS provider does with
/// a number that has no country code.
///
/// So the number is normalised to exactly one form, here, in a pure function,
/// and everything that identifies a person by phone goes through it.
///
/// ## What "valid" means here
///
/// Deliberately narrow: Nigerian mobile numbers, which is who this app is for.
/// A number this refuses is refused BEFORE an SMS is paid for and before a
/// half-formed account exists, and the person is told what is wrong with it —
/// which is better than an OTP that never arrives and a screen that waits.
///
/// It does not attempt to decide whether a number is in service. Nothing can,
/// short of sending to it, which is what the OTP does.
library;

/// Nigeria's country calling code.
const String nigeriaDialCode = '234';

/// The digits a Nigerian mobile number starts with after the country code.
///
/// MTN, Airtel, Glo and 9mobile allocations all begin 70, 71, 80, 81, 90 or 91.
/// A landline (`1` for Lagos, `73` for Jos) cannot receive an SMS, so accepting
/// one would mean charging for a message that can never arrive and leaving the
/// person on a screen waiting for it.
const List<String> nigerianMobilePrefixes = <String>[
  '70', '71', '80', '81', '90', '91',
];

/// The result of reading a typed phone number.
class PhoneNumberResult {
  /// A number that can be used as an identity, in E.164.
  const PhoneNumberResult.valid(this.e164) : problem = null;

  /// A number that cannot, and what to tell the person about it.
  const PhoneNumberResult.invalid(this.problem) : e164 = null;

  /// The number in E.164 (`+234…`), or null when it could not be read.
  final String? e164;

  /// What is wrong with it, in words a person can act on, or null.
  final String? problem;

  /// Whether this reads as a Nigerian mobile number.
  bool get isValid => e164 != null;
}

/// Reads a typed Nigerian phone number into one canonical E.164 string.
///
/// Accepts every way the number is commonly written, including spaces, dashes,
/// brackets and a leading `00` international prefix. Returns the SAME string
/// for all of them, which is the whole point.
PhoneNumberResult readNigerianPhone(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const PhoneNumberResult.invalid('Enter your phone number.');
  }

  // Letters are never part of a number, and a person who typed some has made a
  // different mistake from one who typed too few digits.
  if (RegExp('[A-Za-z]').hasMatch(trimmed)) {
    return const PhoneNumberResult.invalid(
      'A phone number has no letters in it.',
    );
  }

  var digits = trimmed.replaceAll(RegExp('[^0-9]'), '');
  if (digits.isEmpty) {
    return const PhoneNumberResult.invalid('Enter your phone number.');
  }

  // `00234…` is the international prefix written out; `+` has already been
  // stripped above, and both mean the same thing.
  if (digits.startsWith('00')) digits = digits.substring(2);

  String national; // the 10 digits after the country code, e.g. 8030001111
  if (digits.startsWith(nigeriaDialCode)) {
    national = digits.substring(nigeriaDialCode.length);
    // A trunk zero after the country code — `2340803…` — is a common mix of
    // the two formats. It is not a different number.
    if (national.startsWith('0')) national = national.substring(1);
  } else if (digits.startsWith('0')) {
    national = digits.substring(1);
  } else {
    national = digits;
  }

  if (national.length < 10) {
    return const PhoneNumberResult.invalid(
      'That is too short for a Nigerian mobile number.',
    );
  }
  if (national.length > 10) {
    return const PhoneNumberResult.invalid(
      'That is too long for a Nigerian mobile number.',
    );
  }

  final prefix = national.substring(0, 2);
  if (!nigerianMobilePrefixes.contains(prefix)) {
    return const PhoneNumberResult.invalid(
      'That is not a Nigerian mobile number. Only a mobile line can receive '
      'the code.',
    );
  }

  return PhoneNumberResult.valid('+$nigeriaDialCode$national');
}

/// The canonical form, or null when the number cannot be read.
///
/// For callers that only want the answer. Anything that shows the person a
/// message should use [readNigerianPhone] and say what is wrong.
String? normaliseNigerianPhone(String input) => readNigerianPhone(input).e164;

/// How the number is shown back to the person: `0803 000 1111`.
///
/// People recognise their own number in the form they write it, not in E.164.
/// Used on the OTP screen ("code sent to …") and on the lock screen, where
/// showing `+2348030001111` invites the "is that mine?" pause.
String displayNigerianPhone(String e164) {
  final digits = e164.replaceAll(RegExp('[^0-9]'), '');
  if (!digits.startsWith(nigeriaDialCode) ||
      digits.length != nigeriaDialCode.length + 10) {
    return e164;
  }
  final national = digits.substring(nigeriaDialCode.length);
  return '0${national.substring(0, 3)} '
      '${national.substring(3, 6)} '
      '${national.substring(6)}';
}

/// Whether what has been typed so far could still become a valid number.
///
/// For enabling the button as the person types, without telling them off for
/// the first three digits.
bool couldStillBeAPhoneNumber(String input) {
  final digits = input.replaceAll(RegExp('[^0-9]'), '');
  return digits.length < 4 || readNigerianPhone(input).isValid;
}
