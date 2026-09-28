/// Noticing that the SIM has been taken out or swapped.
///
/// ## Why this matters here, and what it is not
///
/// In this app the phone number IS the identity. It is what the account was
/// created with, what `profiles.phone` holds, what HQ rings back, and — this is
/// the operational part — what the **SMS fallback channel** depends on. When
/// the SIM leaves the handset:
///
///   * the encrypted SMS path to HQ stops working, and nothing else notices;
///   * a re-entry code cannot arrive, so the person will be locked out the next
///     time they come back to the app;
///   * a handset that has been stolen usually gets a new SIM immediately.
///
/// So this is a record about **the channel**, not about the person. It carries
/// what changed and when. It does not carry a location, it is not a movement
/// log, and it must never become one: this app is used in a conflict zone by
/// people who report things they can be harmed for reporting, and a government
/// console that quietly tracks their SIM history would be a reason not to
/// install it. The person is told on the handset that this is reported.
///
/// ## What can actually be detected, per platform
///
/// **Android.** `TelephonyManager.getSimState()` needs no permission and gives
/// present / absent reliably. `getSimOperator()` (MCC+MNC) and
/// `getSimOperatorName()` also need no permission and identify the NETWORK. The
/// SIM's own serial — ICCID, and the IMSI — has needed
/// `READ_PRIVILEGED_PHONE_STATE` since Android 10, which is a signature-level
/// permission no ordinary app can hold. So:
///
///   * SIM removed → detected.
///   * SIM replaced with one from a DIFFERENT network → detected.
///   * SIM replaced with another from the SAME network → **not detectable.**
///
/// That last line is a real limit, not an implementation gap, and it is stated
/// rather than glossed: an operator who believes "SIM swap" is covered would be
/// wrong about the commonest swap of all.
///
/// **iOS.** `CTTelephonyNetworkInfo.serviceSubscriberCellularProviders` is
/// deprecated as of iOS 16 and returns a carrier whose `mobileCountryCode` is
/// the placeholder `65535`. There is no supported API that reports SIM removal
/// to a third-party app. On iOS this reports [SimPresence.unavailable] and
/// nothing is ever raised — an honest nothing, rather than a feature that
/// appears to be watching and is not.
library;

/// Whether a SIM is in the handset, as far as the platform will say.
enum SimPresence {
  /// A SIM is present and ready.
  present,

  /// No SIM in the tray.
  absent,

  /// The platform will not say: iOS 16+, or a device with no telephony at all.
  /// Distinct from [absent], and the distinction is the whole point — "we
  /// cannot see" must never be reported as "it has been removed".
  unavailable,
}

/// One reading of the SIM state.
class SimSnapshot {
  /// One reading of the SIM state.
  const SimSnapshot({
    required this.presence,
    this.operatorCode,
    this.operatorName,
  });

  /// Nothing is known about the SIM on this platform.
  const SimSnapshot.unavailable()
      : presence = SimPresence.unavailable,
        operatorCode = null,
        operatorName = null;


  /// Reads a snapshot back, tolerating anything unexpected as "unavailable".
  ///
  /// A stored record from an older build, or a platform response with a field
  /// missing, must not be read as "the SIM was removed".
  factory SimSnapshot.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SimSnapshot.unavailable();
    final raw = json['presence'];
    final presence = SimPresence.values.where((p) => p.name == raw).toList();
    if (presence.isEmpty) return const SimSnapshot.unavailable();
    return SimSnapshot(
      presence: presence.first,
      operatorCode: json['operator_code'] as String?,
      operatorName: json['operator_name'] as String?,
    );
  }

  /// Present / absent / unavailable.
  final SimPresence presence;

  /// MCC+MNC, e.g. `62130` for MTN Nigeria. Null when not readable.
  final String? operatorCode;

  /// The network's name as the handset reports it, for showing to a person.
  final String? operatorName;

  /// Round-trips through the device record and the platform channel.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'presence': presence.name,
        'operator_code': operatorCode,
        'operator_name': operatorName,
      };

  @override
  String toString() =>
      'SimSnapshot(${presence.name}, $operatorName, $operatorCode)';
}

/// What changed between two readings.
enum SimChange {
  /// Nothing worth reporting.
  none,

  /// There was a SIM and now there is not.
  removed,

  /// There was no SIM and now there is one.
  inserted,

  /// A SIM from a different network is in the handset.
  replaced,
}

/// Compares two readings, and errs towards saying nothing.
///
/// Every ambiguous case returns [SimChange.none]. A false "the SIM was removed"
/// costs an operator a call to somebody whose phone is fine, and a few of those
/// teach the whole console to ignore the alert — which is worse than not having
/// it. The cases that are deliberately silent:
///
///   * **No previous reading.** First run, or a fresh install. There is no
///     change to report, only a baseline to record.
///   * **Either side unavailable.** iOS, or a platform that would not answer.
///     "We cannot see" is not "it has been removed".
///   * **Same network, no operator code on one side.** Not enough to claim a
///     swap.
SimChange compareSim(SimSnapshot? before, SimSnapshot now) {
  if (before == null) return SimChange.none;
  if (before.presence == SimPresence.unavailable ||
      now.presence == SimPresence.unavailable) {
    return SimChange.none;
  }

  final was = before.presence == SimPresence.present;
  final is_ = now.presence == SimPresence.present;

  if (was && !is_) return SimChange.removed;
  if (!was && is_) return SimChange.inserted;
  if (!was && !is_) return SimChange.none;

  final beforeCode = before.operatorCode;
  final nowCode = now.operatorCode;
  if (beforeCode == null || nowCode == null) return SimChange.none;
  if (beforeCode.isEmpty || nowCode.isEmpty) return SimChange.none;
  return beforeCode == nowCode ? SimChange.none : SimChange.replaced;
}

/// Whether HQ should be told about this change.
///
/// [SimChange.inserted] is reported too, and deliberately: a handset that was
/// running without a SIM and now has one is the second half of a swap whose
/// first half may have happened while the app was closed.
bool shouldReport(SimChange change) => change != SimChange.none;

/// What HQ sees on the record, in words rather than an enum.
String describeSimChange(SimChange change, {String? operatorName}) {
  switch (change) {
    case SimChange.removed:
      return 'SIM REMOVED — this handset can no longer receive SMS, so the '
          'offline alert channel and sign-in codes will not reach it.';
    case SimChange.inserted:
      final network = operatorName == null || operatorName.isEmpty
          ? 'a SIM'
          : 'a $operatorName SIM';
      return 'SIM INSERTED — $network is now in this handset.';
    case SimChange.replaced:
      final network = operatorName == null || operatorName.isEmpty
          ? 'a different network'
          : operatorName;
      return 'SIM REPLACED — this handset is now on $network. The number the '
          'account was verified with may no longer reach it.';
    case SimChange.none:
      return 'No change.';
  }
}

/// What the PERSON is told, on the handset, when this is reported.
///
/// Reporting a change to a state console without telling the holder would be
/// surveillance. It is one line, it is shown once per change, and it says
/// exactly what was sent.
String simChangeNoticeForUser(SimChange change) {
  switch (change) {
    case SimChange.removed:
      return 'Your SIM has been removed. Emergency SMS and sign-in codes '
          'cannot reach this phone. HQ has been told the channel is down — '
          'not where you are.';
    case SimChange.replaced:
      return 'This phone is on a different network now. HQ has been told your '
          'SMS channel changed — not where you are. Update your number in '
          'Settings if it has changed.';
    case SimChange.inserted:
      return 'A SIM is in this phone again. Emergency SMS can reach you.';
    case SimChange.none:
      return '';
  }
}
