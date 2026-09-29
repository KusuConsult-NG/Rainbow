/// Evidence photographed before the SOS had an incident to attach it to.
///
/// ## The lie this replaces
///
/// `_captureEvidence` on the duress screen read:
///
///     final alertId = ref.read(emergencyProvider).alertId;
///     if (alertId == null) {
///       ScaffoldMessenger.of(context).showSnackBar(
///         const SnackBar(content:
///           Text('SOS not yet confirmed — evidence saved locally')),
///       );
///       setState(() => _isCapturingEvidence = false);
///       return;
///     }
///
/// Nothing was saved. The `XFile` path was dropped on the floor, nothing
/// recorded it, and nothing retried when the incident id arrived a second or two
/// later. A person under duress was told their photograph was safe, and it was
/// thrown away.
///
/// That window is exactly when the photograph matters most: it is the first
/// seconds of the emergency, before the alert has round-tripped, and it is
/// usually the only moment the person will get.
///
/// ## What this does
///
/// Holds the local paths, and attaches them the moment there is an incident to
/// attach them to. The flush is single-flight and failure-preserving, because
/// both of those decide whether evidence survives:
///
///   * **Single-flight.** The flush is triggered by a provider listener, which
///     fires on every state change — the timer on that screen ticks every
///     second. Without the guard, one photograph would be uploaded several times
///     over and a dispatcher would see the same frame four times in a dossier.
///
///   * **Failure keeps the path.** A path is only dropped once the database says
///     the URL is on the incident. An upload that failed, or that RLS refused,
///     stays held so the next flush tries again. Dropping on attempt rather than
///     on confirmation is how a queue quietly empties itself.
library;

import 'package:flutter/foundation.dart';

/// The outcome of one flush.
@immutable
class FlushResult {
  const FlushResult({required this.delivered, required this.stillHeld});

  /// Paths now confirmed on the incident. These are no longer held.
  final List<String> delivered;

  /// How many paths are still waiting, because their attach did not succeed.
  final int stillHeld;

  bool get anythingDelivered => delivered.isNotEmpty;
}

/// Local evidence files waiting for an incident id.
class PendingEvidence {
  final List<String> _paths = <String>[];
  bool _flushing = false;

  /// How many files are waiting.
  int get count => _paths.length;

  bool get isEmpty => _paths.isEmpty;

  /// The paths currently held, oldest first. A copy: a caller iterating this
  /// while a flush is running must not see the list mutate underneath them.
  List<String> get paths => List<String>.unmodifiable(_paths);

  /// Hold [path] until there is somewhere to send it.
  ///
  /// Already-held paths are ignored, so a double tap on the shutter does not
  /// queue the same frame twice.
  void hold(String path) {
    final p = path.trim();
    if (p.isEmpty || _paths.contains(p)) return;
    _paths.add(p);
  }

  /// Try to attach everything held, oldest first.
  ///
  /// [attach] reports whether the file is now ON the incident. Only then is the
  /// path dropped — see the note above about dropping on attempt.
  ///
  /// A second call while one is in flight returns immediately with nothing
  /// delivered, rather than uploading the same files again.
  Future<FlushResult> flush(Future<bool> Function(String path) attach) async {
    if (_flushing) {
      return FlushResult(delivered: const <String>[], stillHeld: _paths.length);
    }
    _flushing = true;
    try {
      final delivered = <String>[];
      // Iterate a snapshot: `hold` may be called from the shutter while this
      // runs, and a new photograph must not be attempted by the loop that is
      // already going — it will be picked up by the next flush.
      for (final path in List<String>.from(_paths)) {
        bool ok;
        try {
          ok = await attach(path);
          // ignore: avoid_catches_without_on_clauses, a throw and a false are
          // the same answer here: not confirmed, so keep holding it.
        } catch (e) {
          debugPrint('[PENDING_EVIDENCE] attach threw for $path: $e');
          ok = false;
        }
        if (ok) {
          _paths.remove(path);
          delivered.add(path);
        }
      }
      return FlushResult(delivered: delivered, stillHeld: _paths.length);
    } finally {
      _flushing = false;
    }
  }
}

/// What to tell someone who photographed something before the SOS landed.
///
/// Separate from the widget so the words are testable. They were the defect:
/// "evidence saved locally" was false, and a false reassurance during a duress
/// event is worse than an error, because the person stops trying.
String heldEvidenceMessage(int count) {
  if (count <= 0) return 'Photo captured.';
  final noun = count == 1 ? 'Photo' : '$count photos';
  return '$noun held — will be sent the moment HQ confirms the SOS. '
      'Keep the app open.';
}

/// What to tell them once it has actually gone.
String deliveredEvidenceMessage(int count) {
  if (count <= 1) return 'Evidence sent to HQ.';
  return '$count held photos sent to HQ.';
}
