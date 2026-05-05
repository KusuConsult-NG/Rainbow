
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final termiiServiceProvider = Provider<TermiiService>((ref) {
  return TermiiService();
});

/// Handles dispatching SMS alerts through Termii CPaaS APIs.
/// Used during emergency fallback scenarios when active internet is unavailable,
/// or when dispatching bulk broadcast alerts to citizens.
class TermiiService {
  // Replace with actual API key and Sender ID when configured
  static String get _apiKey => dotenv.env['TERMII_API_KEY'] ?? 'MOCK_TERMII_API_KEY';
  static const String _senderId = 'RainbowHQ';
  static const String _baseUrl = 'https://api.ng.termii.com/api/sms/send';

  TermiiService();

  /// Send an emergency alert via Termii SMS.
  /// 
  /// [to] The recipient phone number (e.g. "2349012345678").
  /// [message] The message body to dispatch.
  Future<bool> sendEmergencyAlert(String to, String message) async {
    // Mock the standard Termii request payload
    final payload = {
      "to": to,
      "from": _senderId,
      "sms": message,
      "type": "plain",
      "api_key": _apiKey,
      "channel": "generic"
    };

    try {
      if (_apiKey.contains('MOCK')) {
        await Future.delayed(const Duration(milliseconds: 800));
        return true;
      }
      
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      // Handle network errors
      return false;
    }
  }

  Future<bool> sendBulkBroadcast(List<String> recipients, String message) async {
    bool allSuccess = true;
    for (var phone in recipients) {
      if (phone.isEmpty || phone == 'System') continue;
      final success = await sendEmergencyAlert(phone, message);
      if (!success) allSuccess = false;
    }
    return allSuccess;
  }
}
