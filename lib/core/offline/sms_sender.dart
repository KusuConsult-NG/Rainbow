/// Sending an alert by SMS when there is signal but no data.
///
/// ## When this runs, and when it must not
///
/// The offline queue already handles "no network at all": the report is held
/// and goes when connectivity returns. That is the right answer for a report.
/// It is the wrong answer for an emergency, because the queue waits for a
/// network that may not come back for hours, and nobody at HQ knows anything
/// is happening.
///
/// So SMS is for the gap between those: the handset has a cellular connection
/// but cannot move data. Congested towers, exhausted bundles, a data block, 2G
/// coverage that carries a text and not a TLS handshake. In Plateau this is
/// far commoner than a total blackout.
///
/// It must NOT run when:
///
///   * the data path worked — an alert that arrived does not need sending
///     twice, and every duplicate is another charge on an emergency service's
///     budget;
///   * there is no cellular radio at all (flight mode, no SIM, no coverage) —
///     the message would fail and the queue is already holding the report;
///   * this handset has no device key — without one the message cannot be
///     authenticated and HQ would reject it, so sending would cost money to
///     achieve nothing;
///   * the alert is not urgent. A cattle-rustling report filed for the record
///     can wait for the queue. A kidnapping cannot.
///
/// That last rule is a judgement, and it is encoded rather than assumed:
/// [shouldFallBackToSms] takes the severity and says so out loud.
///
/// ## Android sends silently; iOS cannot
///
/// On Android the message goes through `SmsManager` with no interaction, which
/// is what a silent or duress SOS requires. iOS has no programmatic SMS at
/// all — `MFMessageComposeViewController` needs a tap — so on iOS this opens
/// the messaging app with the body pre-filled and the person presses send.
///
/// That is a real difference in what the app can promise, and it is surfaced
/// in [SmsSendOutcome] rather than hidden: a duress SOS on iOS cannot be
/// silent, and the caller has to know that rather than assume it worked.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// What happened when we tried to send.
enum SmsSendOutcome {
  /// Sent by the app, with no interaction. Android only.
  sentSilently,

  /// The messaging app was opened with the message ready. The person still has
  /// to press send, so this is NOT a delivery, and a silent SOS is no longer
  /// silent.
  composerOpened,

  /// Not attempted, because the conditions for falling back were not met.
  notNeeded,

  /// Attempted and refused — no permission, no SIM, no service.
  failed,
}

/// Why a fallback was or was not attempted, for the log and for the tests.
@immutable
class SmsFallbackDecision {
  /// Creates a decision.
  const SmsFallbackDecision({required this.send, required this.because});

  /// Whether to send.
  final bool send;

  /// A short reason, recorded so a run can explain itself.
  final String because;
}

/// Severities that justify spending a message.
///
/// HIGH and CRITICAL only. The line is drawn here because every SMS costs
/// money and an emergency service's budget is finite; a MEDIUM report waiting
/// in the queue for the network to return is an acceptable outcome, and a
/// kidnapping waiting there is not.
const Set<String> smsWorthySeverities = {'HIGH', 'CRITICAL'};

/// Decides whether this alert should also go by SMS.
///
/// Every condition is a parameter rather than something this function reads
/// for itself, so the decision can be tested exhaustively without a radio, a
/// keystore or a network.
SmsFallbackDecision shouldFallBackToSms({
  required bool dataSendSucceeded,
  required bool hasCellularSignal,
  required bool hasDeviceKey,
  required String severity,
  required bool isDuress,
}) {
  if (dataSendSucceeded) {
    return const SmsFallbackDecision(
      send: false,
      because: 'the report already reached HQ over data',
    );
  }
  if (!hasCellularSignal) {
    return const SmsFallbackDecision(
      send: false,
      because: 'no cellular service — the offline queue is holding it',
    );
  }
  if (!hasDeviceKey) {
    // Sending unauthenticated would cost money to produce something HQ
    // correctly refuses.
    return const SmsFallbackDecision(
      send: false,
      because: 'this handset has never registered a device key',
    );
  }
  // A duress alert always goes, whatever severity the UI attached to it. The
  // whole point is that the person could not say how bad it is.
  if (isDuress) {
    return const SmsFallbackDecision(send: true, because: 'duress');
  }
  if (!smsWorthySeverities.contains(severity.toUpperCase())) {
    return SmsFallbackDecision(
      send: false,
      because: '$severity can wait for the network to return',
    );
  }
  return SmsFallbackDecision(send: true, because: '$severity with no data path');
}

/// Sends a prepared message body to the HQ shortcode.
class SmsSender {
  /// Creates a sender.
  const SmsSender();

  static const MethodChannel _channel =
      MethodChannel('com.operationrainbow.app/sms');

  /// Test seam: the platform call.
  @visibleForTesting
  static Future<int> Function(String destination, String body)? sendOverride;

  /// Test seam: the compose-sheet fallback.
  @visibleForTesting
  static Future<bool> Function(Uri uri)? launchOverride;

  /// Test seam: which platform we are pretending to be.
  @visibleForTesting
  static bool? isAndroidOverride;

  static bool get _isAndroid =>
      isAndroidOverride ?? defaultTargetPlatform == TargetPlatform.android;

  /// Sends [body] to [destination].
  ///
  /// Never throws. An emergency path that can throw is an emergency path that
  /// can take the SOS down with it.
  Future<SmsSendOutcome> send({
    required String destination,
    required String body,
  }) async {
    if (destination.trim().isEmpty || body.trim().isEmpty) {
      return SmsSendOutcome.failed;
    }

    if (_isAndroid) {
      try {
        final segments = sendOverride != null
            ? await sendOverride!(destination, body)
            : await _channel.invokeMethod<int>('sendSms', {
                  'destination': destination,
                  'body': body,
                }) ??
                0;
        if (segments > 0) return SmsSendOutcome.sentSilently;
        return SmsSendOutcome.failed;
      } on PlatformException catch (e) {
        // SMS_DENIED lands here when the permission was refused, or when the
        // Play declaration was rejected and the permission never granted. Fall
        // through to the composer rather than failing outright.
        debugPrint('[SMS_SEND] platform refused (${e.code}) — offering the composer');
      } catch (e) {
        debugPrint('[SMS_SEND] failed: $e');
        return SmsSendOutcome.failed;
      }
    }

    // iOS always, and Android when the silent path is unavailable.
    try {
      final uri = Uri(
        scheme: 'sms',
        path: destination,
        queryParameters: {'body': body},
      );
      final launched = launchOverride != null
          ? await launchOverride!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      return launched ? SmsSendOutcome.composerOpened : SmsSendOutcome.failed;
    } catch (e) {
      debugPrint('[SMS_SEND] could not open the composer: $e');
      return SmsSendOutcome.failed;
    }
  }
}
