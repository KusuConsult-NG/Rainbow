/// The platform side of reading the SIM state.
///
/// One method, `readSim`, answering with three fields. The contract is kept
/// this small on purpose: everything that decides anything lives in
/// `sim_fingerprint.dart`, which is pure and tested, and this file only carries
/// what the platform will say.
///
/// ## What each platform answers
///
/// **Android** (`MainActivity.kt`, channel `com.operationrainbow.app/sim`):
/// `TelephonyManager.getSimState()`, `getSimOperator()` and
/// `getSimOperatorName()`. None of the three needs a permission — which is why
/// this feature adds none. The SIM's own serial (ICCID) and the IMSI would
/// identify a specific card rather than a network, and have needed
/// `READ_PRIVILEGED_PHONE_STATE` since Android 10: a signature-level permission
/// no ordinary app can hold. So a SIM swapped for another on the SAME network
/// is invisible, and that is a platform limit, not a gap here.
///
/// **iOS**: answers `unavailable`, always.
/// `CTTelephonyNetworkInfo.serviceSubscriberCellularProviders` is deprecated as
/// of iOS 16 and returns a carrier whose `mobileCountryCode` is the placeholder
/// `65535`. There is no supported way for a third-party app to be told the SIM
/// was removed. Reporting an honest nothing beats a feature that looks like it
/// is watching and is not.
///
/// **Anything else** (a desktop build, a test): `unavailable`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rainbow_app/core/device/sim_fingerprint.dart';

/// The channel name. Must match `SIM_CHANNEL` in `MainActivity.kt`.
const String simChannelName = 'com.operationrainbow.app/sim';

/// Reads the SIM state from the platform.
abstract class SimReader {
  /// Reads the SIM state from the platform.
  Future<SimSnapshot> read();
}

/// The real reader, over a method channel.
class MethodChannelSimReader implements SimReader {
  /// The real reader, over a method channel.
  const MethodChannelSimReader([
    this.channel = const MethodChannel(simChannelName),
  ]);

  /// The channel to ask.
  final MethodChannel channel;

  @override
  Future<SimSnapshot> read() async {
    try {
      final reply = await channel.invokeMapMethod<String, dynamic>('readSim');
      if (reply == null) return const SimSnapshot.unavailable();
      return SimSnapshot.fromJson(Map<String, dynamic>.from(reply));
    } on Object catch (e) {
      // `on Object`, not `on Exception`: a MissingPluginException is an
      // Exception but a platform channel can also surface an Error, and the
      // whole point of this call site is that a failure to read must look like
      // "cannot see", never like "the SIM has gone".
      debugPrint('[SIM] could not read the SIM state: $e');
      return const SimSnapshot.unavailable();
    }
  }
}

/// A reader that answers whatever a test tells it to.
@visibleForTesting
class FakeSimReader implements SimReader {
  /// A reader that answers whatever a test tells it to.
  FakeSimReader(this.answer);

  /// What [read] returns. Reassign between calls to simulate a change.
  SimSnapshot answer;

  /// How many times it was asked.
  int reads = 0;

  @override
  Future<SimSnapshot> read() async {
    reads += 1;
    return answer;
  }
}
