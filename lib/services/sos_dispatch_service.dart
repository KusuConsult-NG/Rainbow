import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:rainbow_app/core/config/app_config.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';

/// Outcome of an SOS escalation SMS request.
enum SosDispatchResult {
  /// The HQ backend accepted the request and Termii acknowledged the send.
  sent,

  /// The backend is reachable but SMS is not configured on it. Not a failure of
  /// this app, and not a failure of the SOS: the alert row is the record.
  skipped,

  /// The request could not be made or was rejected. The SOS still stands.
  failed,

  /// No signed-in Supabase session, so no token to present. Nothing was sent.
  unauthenticated,

  /// No `HQ_API_BASE_URL` configured, so there is no endpoint to call.
  unconfigured,
}

final sosDispatchServiceProvider = Provider<SosDispatchService>(
  (ref) => SosDispatchService(),
);

/// Asks the HQ backend to send the out-of-band SOS SMS.
///
/// ## Why this replaced `TermiiService` (finding H-3)
///
/// The old service called Termii from the handset, so `TERMII_API_KEY` had to be
/// in `.env` — which `pubspec.yaml` declares as a Flutter **asset**, meaning it
/// ships verbatim in the APK and extracts with `unzip`. Every install carried the
/// SMS credential of an emergency service. No amount of care in this file could
/// have fixed that; the credential simply cannot be on the device.
///
/// This class holds no credential. It presents the user's own Supabase access
/// token to `POST /api/sos/dispatch-sms`, which holds the Termii key, chooses the
/// recipient, and composes the message. The app supplies facts, not prose.
///
/// ## This call is advisory
///
/// Every failure mode returns a value rather than throwing, and the caller must
/// not treat any of them as "the SOS failed". The alert row written by
/// `AlertService` is the system of record; this SMS is a redundant nudge for the
/// case where nobody is looking at the dashboard.
class SosDispatchService {
  SosDispatchService({http.Client? client, Future<String?> Function()? accessToken})
      : _client = client ?? http.Client(),
        _accessToken = accessToken ?? _sessionAccessToken;

  final http.Client _client;
  final Future<String?> Function() _accessToken;

  static Future<String?> _sessionAccessToken() async =>
      SupabaseConfig.client.auth.currentSession?.accessToken;

  /// How long to wait before giving up. Short on purpose: the SOS path must not
  /// block on a redundant channel while someone is in danger.
  static const Duration timeout = Duration(seconds: 8);

  /// Request the escalation SMS for [alertId] at [latitude]/[longitude].
  ///
  /// Coordinates are nullable and are sent as `null` when there is no GPS fix.
  /// They are never invented — a fabricated position sends responders to the
  /// wrong place, which is worse than sending them none (finding C-5).
  Future<SosDispatchResult> dispatchSos({
    String? alertId,
    double? latitude,
    double? longitude,
  }) async {
    final baseUrl = AppConfig.hqApiBaseUrl;
    if (baseUrl == null) {
      debugPrint('[SOS_DISPATCH] HQ_API_BASE_URL unset — cannot request SOS SMS.');
      return SosDispatchResult.unconfigured;
    }

    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      debugPrint('[SOS_DISPATCH] No Supabase session — cannot request SOS SMS.');
      return SosDispatchResult.unauthenticated;
    }

    final uri = Uri.parse('$baseUrl/api/sos/dispatch-sms');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{
              'alertId': alertId,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        debugPrint('[SOS_DISPATCH] HTTP ${response.statusCode} from $uri');
        return SosDispatchResult.failed;
      }

      final decoded = jsonDecode(response.body);
      final status = decoded is Map ? decoded['sms'] : null;
      switch (status) {
        case 'SENT':
          return SosDispatchResult.sent;
        case 'SKIPPED':
          debugPrint('[SOS_DISPATCH] Backend has no SMS configured — alert row still written.');
          return SosDispatchResult.skipped;
        default:
          return SosDispatchResult.failed;
      }
      // ignore: avoid_catches_without_on_clauses, any transport or decode failure is non-fatal here
    } catch (e) {
      // Deliberately broad. A redundant notification channel must never be able
      // to throw into the SOS path.
      debugPrint('[SOS_DISPATCH] Request failed: $e');
      return SosDispatchResult.failed;
    }
  }
}
