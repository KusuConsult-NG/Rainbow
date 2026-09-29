// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Documentation for this public member.

final termiiServiceProvider = Provider<TermiiService>((ref) {
  return TermiiService();
});

/// Handles dispatching SMS alerts through Termii CPaaS APIs.
/// Used during emergency fallback scenarios when active internet is unavailable,
/// or when dispatching bulk broadcast alerts to citizens.
class TermiiService {
  /// Documentation for this public member.
  TermiiService();
  // Replace with actual API key and Sender ID when configured
  static String get _apiKey {
    if (!dotenv.isInitialized) return 'MOCK_TERMII_API_KEY';
    return dotenv.env['TERMII_API_KEY'] ?? 'MOCK_TERMII_API_KEY';
  }

  static String get _senderId =>
      dotenv.isInitialized && (dotenv.env['TERMII_SENDER_ID'] ?? '').isNotEmpty
          ? dotenv.env['TERMII_SENDER_ID']!
          : 'OE Alert';
  static String get _baseUrl =>
      dotenv.isInitialized && (dotenv.env['TERMII_BASE_URL'] ?? '').isNotEmpty
          ? dotenv.env['TERMII_BASE_URL']!
          : 'https://v4.api.termii.com/api/sms/send';

  /// Send an emergency alert via Termii SMS.
  ///
  /// [to] The recipient phone number (e.g. "2349012345678").
  /// [message] The message body to dispatch.
  Future<bool> sendEmergencyAlert(String to, String message) async {
    // Mock the standard Termii request payload
    final payload = {
      'to': to,
      'from': _senderId,
      'sms': message,
      'type': 'plain',
      'api_key': _apiKey,
      'channel': 'dnd',
    };

    try {
      if (_apiKey.contains('MOCK')) {
        debugPrint('[TERMII_SMS] SIMULATED DISPATCH (MOCK_KEY): SMS to $to: "$message"');
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return true;
      }
      debugPrint('[TERMII_SMS] DISPATCHING LIVE SMS to $to via Termii CPaaS API...');

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      // Handle network errors
      return false;
    }
  }

  /// Documentation for this public member.

  Future<bool> sendBulkBroadcast(
    List<String> recipients,
    String message,
  ) async {
    var allSuccess = true;
    for (final phone in recipients) {
      if (phone.isEmpty || phone == 'System') continue;
      final success = await sendEmergencyAlert(phone, message);
      if (!success) allSuccess = false;
    }
    return allSuccess;
  }

  /// Cryptographically generates a secure 6-digit verification PIN and sends it via Termii
  /// using the approved DND template format:
  /// "Your Rainbow EWER Verification Pin is pin. It expires in 5 minutes"
  ///
  /// Returns the generated PIN on success, or null on failure.
  Future<String?> sendVerificationPin(String to) async {
    try {
      final rand = Random.secure();
      // Generate a cryptographically secure 6-digit PIN (100000 - 999999)
      final pinVal = 100000 + rand.nextInt(900000);
      final pin = pinVal.toString();

      final message =
          'Your Rainbow EWER Verification Pin is $pin. It expires in 5 minutes';

      final success = await sendEmergencyAlert(to, message);
      if (success) {
        return pin;
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      // Handle cryptographic random or dispatch error
    }
    return null;
  }
}
