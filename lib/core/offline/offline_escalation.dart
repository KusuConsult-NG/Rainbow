/// Reaching HQ when the data path has just failed.
///
/// ## Why this file is the point of the last four commits
///
/// Both offline channels were built, tested and unreachable. A report raised
/// with no data was written to the local queue and sat there — the SMS codec, the
/// device key, the sealing, the relay and the transport all existed and **nothing
/// in the app called any of them**. This is the call.
///
/// It runs at the two moments in `AlertService.submitAlert` where a report has
/// failed to reach the database: the radio says there is no network, or the
/// insert was refused. Those are different failures and the second is the one
/// that matters more, because the radio can say "connected" through a captive
/// portal, an expired token, a congested tower or an RLS refusal.
///
/// ## One sealed body, both channels
///
/// The body is built ONCE and sent over whichever channels are available:
///
/// ```
///   encodeSmsAlert(...)  ──▶  SMS to the shortcode        (seconds, costs money)
///           │
///           └──────────────▶  sealed into a mesh envelope (minutes, costs nothing)
/// ```
///
/// Not two payloads, because the mesh plaintext IS the SMS body — see
/// `mesh_alert_envelope.dart` for why. So the two channels carry the same bytes,
/// authenticate the same way, and deduplicate against each other and against the
/// phone's own queue on the tag inside `local_id`.
///
/// ## What it will not do
///
/// It never throws. An emergency path that can throw is an emergency path that
/// can take the SOS down with it, and the report is already safely in the queue
/// by the time this runs. Every failure is recorded in the returned report and
/// logged, and the alert still exists.
///
/// It also does not decide to spend money lightly. `shouldFallBackToSms` refuses
/// for a MEDIUM report that can wait, for a handset with no device key, and when
/// the data path actually worked. The mesh has no such test because it costs
/// nothing: a relayed envelope is somebody's battery, not somebody's airtime.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/core/config/app_config.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/core/mesh/mesh_alert_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_node.dart';
import 'package:rainbow_app/core/offline/offline_ref.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';
import 'package:rainbow_app/core/offline/sms_device_key.dart';
import 'package:rainbow_app/core/offline/sms_sender.dart';

/// Severity codes, in the order the wire format expects. Append-only.
const List<String> offlineSeverities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];

/// The code meaning "an SOS with no category chosen".
const int offlineCategorySos = 255;

/// What happened when a report tried the offline channels.
@immutable
class OfflineEscalationReport {
  /// Creates a report.
  const OfflineEscalationReport({
    required this.because,
    this.smsOutcome = SmsSendOutcome.notNeeded,
    this.meshSent = false,
  });

  /// Why, in one phrase, for the log and for the tests.
  final String because;

  /// What the SMS attempt did.
  final SmsSendOutcome smsOutcome;

  /// Whether an envelope went into the mesh.
  final bool meshSent;

  /// Whether anything at all left the handset.
  bool get reachedAnything =>
      meshSent ||
      smsOutcome == SmsSendOutcome.sentSilently ||
      smsOutcome == SmsSendOutcome.composerOpened;
}

/// Maps an alert's `type` string onto a wire category code.
///
/// Types arrive as `'<label> - <subtype>'` — `'Kidnap - Immediate Abduction'` —
/// so the label is the part before the separator. Anything unrecognised becomes
/// an SOS rather than a wrong category: a dispatcher reading `SOS` investigates,
/// and one reading `Flood` for a kidnapping does not.
int smsCategoryCodeFor(String type) {
  final label = type.split(' - ').first.trim().toLowerCase();
  for (var i = 0; i < alertCategories.length; i++) {
    if (alertCategories[i].label.toLowerCase() == label) return i;
  }
  return offlineCategorySos;
}

/// Maps a severity name onto a wire code, defaulting to MEDIUM.
int smsSeverityCodeFor(String severity) {
  final i = offlineSeverities.indexOf(severity.trim().toUpperCase());
  return i < 0 ? 1 : i;
}

/// Sends a failed report over whatever channels this handset still has.
class OfflineEscalation {
  /// Creates an escalation path.
  ///
  /// Everything is injectable, because the whole of this decision has to be
  /// testable without a radio, a keystore, a SIM or a network.
  OfflineEscalation({
    SmsDeviceKeyService? keys,
    this.sender = const SmsSender(),
    this.mesh,
    this.shortcode,
    this.hqMeshPublicKey,
    DateTime Function()? clock,
  })  : keys = keys ?? SmsDeviceKeyService(),
        _clock = clock ?? DateTime.now;

  /// Where the per-device key comes from.
  final SmsDeviceKeyService keys;

  /// How a message is sent.
  final SmsSender sender;

  /// This phone's participation in the mesh, or null when there is none.
  ///
  /// Null today in production: the BLE radio's native halves are not written, so
  /// nothing constructs a node. The path is here, tested, and switches on the
  /// moment a radio exists — which is deliberately visible rather than hidden,
  /// so nobody believes the mesh is carrying traffic when it is not.
  final MeshNode? mesh;

  /// Where an SMS goes. Defaults to configuration.
  final String? shortcode;

  /// HQ's mesh public key. Defaults to configuration.
  final Uint8List? hqMeshPublicKey;

  final DateTime Function() _clock;

  /// Tries the offline channels for one report.
  ///
  /// [localId] must be an id minted by [newOfflineLocalId]: the tag inside it is
  /// what lets HQ recognise this report arriving twice.
  Future<OfflineEscalationReport> escalate({
    required String localId,
    required String type,
    required String severity,
    double? latitude,
    double? longitude,
    bool isDuress = false,
    bool isAnonymous = false,
    bool dataSendSucceeded = false,
    bool hasCellularSignal = true,
  }) async {
    try {
      final ref = offlineRefOf(localId);
      if (ref == null) {
        // Without the tag HQ cannot recognise a duplicate, and an alert that
        // arrives twice sends two units to one place. Better to let the queue
        // deliver it once than to deliver it twice now.
        return const OfflineEscalationReport(
            because: 'no dedup tag in the local id');
      }

      final key = await keys.current();
      final decision = shouldFallBackToSms(
        dataSendSucceeded: dataSendSucceeded,
        hasCellularSignal: hasCellularSignal,
        hasDeviceKey: key != null,
        severity: severity,
        isDuress: isDuress,
      );

      final meshKey = hqMeshPublicKey ?? AppConfig.meshHqPublicKey;
      final meshPossible = mesh != null && meshKey != null && key != null;
      if (!decision.send && !meshPossible) {
        return OfflineEscalationReport(because: decision.because);
      }

      // Built once, for both channels. The nonce is used for exactly one
      // plaintext, which is what AES-GCM requires; the same bytes travelling two
      // ways is one message, not two.
      final body = encodeSmsAlert(
        payload: SmsAlertPayload(
          categoryCode: smsCategoryCodeFor(type),
          severityCode: smsSeverityCodeFor(severity),
          sentAt: _clock(),
          localRef: ref,
          latitude: latitude,
          longitude: longitude,
          isDuress: isDuress,
          isAnonymous: isAnonymous,
        ),
        key: key!.secret,
        deviceRef: key.deviceRef,
        nonce: newSmsNonce(),
      );

      var outcome = SmsSendOutcome.notNeeded;
      if (decision.send) {
        final destination = shortcode ?? AppConfig.smsShortcode;
        if (destination == null || destination.trim().isEmpty) {
          debugPrint(
              '[OFFLINE_ESCALATION] no SMS shortcode configured — skipping SMS');
          outcome = SmsSendOutcome.notNeeded;
        } else {
          outcome = await sender.send(destination: destination, body: body);
        }
      }

      var meshSent = false;
      if (meshPossible) {
        // Through the relay rather than straight at the radio, so our own alert
        // is carried onward at the next meeting exactly like anybody else's —
        // and so it is still held if nobody is in range right now.
        await mesh!.send(meshEnvelopeForSmsBody(
          smsBody: body,
          hqPublicKey: meshKey,
          now: _clock(),
        ));
        meshSent = true;
      }

      final report = OfflineEscalationReport(
        because: decision.send ? decision.because : 'mesh only',
        smsOutcome: outcome,
        meshSent: meshSent,
      );
      debugPrint(
        '[OFFLINE_ESCALATION] $localId: sms=${outcome.name} '
        'mesh=$meshSent (${report.because})',
      );
      return report;
    } catch (e) {
      // Never fatal. The report is already in the local queue; this was the
      // attempt to do better than that.
      debugPrint('[OFFLINE_ESCALATION] failed: $e');
      return OfflineEscalationReport(because: 'escalation failed: $e');
    }
  }
}
