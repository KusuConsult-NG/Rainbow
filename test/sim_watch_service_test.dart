// The wiring around the SIM check: read, compare against what was stored,
// report, and tell the person.
//
// The decisions themselves are pure and tested in sim_fingerprint_test.dart.
// What is tested here is the bookkeeping, which has three ways to produce a
// false alarm — and a false "SIM REMOVED" costs an operator a call to somebody
// whose phone is fine.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/device/sim_channel.dart';
import 'package:rainbow_app/core/device/sim_fingerprint.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';
import 'package:rainbow_app/services/sim_watch_service.dart';

const mtn = SimSnapshot(
  presence: SimPresence.present,
  operatorCode: '62130',
  operatorName: 'MTN',
);
const airtel = SimSnapshot(
  presence: SimPresence.present,
  operatorCode: '62120',
  operatorName: 'Airtel',
);
const empty = SimSnapshot(presence: SimPresence.absent);

/// Secure storage without a keystore.
class _MemoryStorage implements SecureStorageService {
  final Map<String, Map<String, dynamic>> _json = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> readJson(String key) async => _json[key];

  @override
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    _json[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _json.remove(key);
  }

  @override
  Future<void> deleteAll() async => _json.clear();

  @override
  Future<void> clearAll() async => _json.clear();

  @override
  Future<void> clearCredentials() async {}

  @override
  Future<Map<String, String>?> getCredentials() async => null;

  @override
  Future<bool> hasCredentials() async => false;

  @override
  Future<void> saveCredentials(String badgeId, String pin) async {}
}

void main() {
  late List<({SimChange change, SimSnapshot now})> reported;

  setUp(() {
    reported = <({SimChange change, SimSnapshot now})>[];
    SimWatchService.reportOverride = (change, now) async {
      reported.add((change: change, now: now));
    };
  });

  tearDown(() {
    SimWatchService.reportOverride = null;
  });

  SimWatchService serviceWith(FakeSimReader reader, _MemoryStorage storage) =>
      SimWatchService(reader: reader, storage: storage);

  test('the first check reports nothing and records a baseline', () {
    // A silent upgrade must not raise "SIM REMOVED" on every handset in the
    // state at once.
    final reader = FakeSimReader(mtn);
    final storage = _MemoryStorage();

    return serviceWith(reader, storage).check().then((outcome) async {
      expect(outcome.change, SimChange.none);
      expect(reported, isEmpty);
      expect(await storage.readJson(SimWatchService.storageKey), isNotNull);
    });
  });

  test('taking the SIM out is reported, once', () async {
    final reader = FakeSimReader(mtn);
    final storage = _MemoryStorage();
    final service = serviceWith(reader, storage);

    await service.check(); // baseline
    reader.answer = empty;

    final outcome = await service.check();
    expect(outcome.change, SimChange.removed);
    expect(outcome.reported, isTrue);
    expect(reported, hasLength(1));

    // And the baseline has moved, so the same removal is not reported again
    // on every subsequent resume.
    final again = await service.check();
    expect(again.change, SimChange.none);
    expect(reported, hasLength(1));
  });

  test('a change of network is reported with the new network', () async {
    final reader = FakeSimReader(mtn);
    final storage = _MemoryStorage();
    final service = serviceWith(reader, storage);

    await service.check();
    reader.answer = airtel;

    final outcome = await service.check();
    expect(outcome.change, SimChange.replaced);
    expect(reported.single.now.operatorName, 'Airtel');
  });

  test('a platform that will not say is never a change', () async {
    // iOS. Reading "unavailable" as "absent" would report a removal from every
    // iPhone in the fleet.
    final reader = FakeSimReader(mtn);
    final storage = _MemoryStorage();
    final service = serviceWith(reader, storage);

    await service.check();
    reader.answer = const SimSnapshot.unavailable();

    final outcome = await service.check();
    expect(outcome.change, SimChange.none);
    expect(reported, isEmpty);

    // And it does not overwrite the baseline with nothing, so a real removal
    // after this is still caught.
    reader.answer = empty;
    expect((await service.check()).change, SimChange.removed);
  });

  test('a failed report does not lose the baseline', () async {
    // Offline. The change is not re-reported — a duplicate alert for every
    // offline period trains the console to ignore the alert — but the next
    // change still is.
    SimWatchService.reportOverride = (change, now) async {
      throw StateError('offline');
    };
    final reader = FakeSimReader(mtn);
    final storage = _MemoryStorage();
    final service = serviceWith(reader, storage);

    await service.check();
    reader.answer = empty;

    final outcome = await service.check();
    expect(outcome.change, SimChange.removed);
    expect(outcome.reported, isFalse, reason: 'it did not reach HQ');

    SimWatchService.reportOverride = (change, now) async {
      reported.add((change: change, now: now));
    };
    reader.answer = airtel;
    expect((await service.check()).change, SimChange.inserted);
    expect(reported, hasLength(1));
  });

  test('every reported change carries a line for the person holding it', () async {
    // Reporting to a state console without telling the holder is surveillance.
    final reader = FakeSimReader(mtn);
    final storage = _MemoryStorage();
    final service = serviceWith(reader, storage);

    await service.check();
    reader.answer = empty;

    final outcome = await service.check();
    expect(outcome.noticeForUser, isNotEmpty);
    expect(outcome.noticeForUser.toLowerCase(), contains('hq has been told'));
  });

  test('signing out forgets the baseline', () async {
    // Otherwise the next person to use this handset is compared against
    // somebody else's SIM, and gets an alert about a swap that is really a
    // change of owner.
    final reader = FakeSimReader(mtn);
    final storage = _MemoryStorage();
    final service = serviceWith(reader, storage);

    await service.check();
    await service.forget();

    expect(await storage.readJson(SimWatchService.storageKey), isNull);

    reader.answer = empty;
    expect((await service.check()).change, SimChange.none,
        reason: 'with no baseline there is nothing to compare against');
  });
}
