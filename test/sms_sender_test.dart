// When to spend a text message, and what happens when we do.
//
// The offline queue already handles "no network at all": the report is held
// and goes when connectivity returns. That is right for a report and wrong for
// an emergency, because the queue waits for a network that may not come back
// for hours and nobody at HQ knows anything is happening.
//
// SMS covers the gap between those — signal but no usable data, which in
// Plateau is far commoner than a total blackout. These tests pin the decision
// of when to use it, because every message costs money and an emergency
// service's budget is finite.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/offline/sms_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SmsFallbackDecision decide({
    bool dataSendSucceeded = false,
    bool hasCellularSignal = true,
    bool hasDeviceKey = true,
    String severity = 'CRITICAL',
    bool isDuress = false,
  }) =>
      shouldFallBackToSms(
        dataSendSucceeded: dataSendSucceeded,
        hasCellularSignal: hasCellularSignal,
        hasDeviceKey: hasDeviceKey,
        severity: severity,
        isDuress: isDuress,
      );

  group('when NOT to send', () {
    test('not when the report already reached HQ over data', () {
      // Every duplicate is another charge, and a second copy of the same
      // emergency on the board is a second unit dispatched.
      expect(decide(dataSendSucceeded: true).send, isFalse);
    });

    test('not when there is no cellular service at all', () {
      // Flight mode, no SIM, no coverage. The message would fail and the queue
      // is already holding the report.
      expect(decide(hasCellularSignal: false).send, isFalse);
    });

    test('not when this handset has never registered a device key', () {
      // Unauthenticated, HQ correctly refuses it, and it cost money.
      expect(decide(hasDeviceKey: false).send, isFalse);
    });

    test('not for a report that can wait for the network', () {
      expect(decide(severity: 'LOW').send, isFalse);
      expect(decide(severity: 'MEDIUM').send, isFalse);
    });

    test('and each refusal says why, for the log', () {
      expect(decide(dataSendSucceeded: true).because, contains('already'));
      expect(decide(hasCellularSignal: false).because, contains('cellular'));
      expect(decide(hasDeviceKey: false).because, contains('device key'));
      expect(decide(severity: 'LOW').because, contains('wait'));
    });
  });

  group('when to send', () {
    test('a critical alert with no data path', () {
      expect(decide(severity: 'CRITICAL').send, isTrue);
    });

    test('a high alert with no data path', () {
      expect(decide(severity: 'HIGH').send, isTrue);
    });

    test('a DURESS alert goes whatever severity the UI attached', () {
      // The whole point of duress is that the person could not say how bad it
      // is. Letting a severity filter suppress it would defeat the feature.
      expect(decide(severity: 'LOW', isDuress: true).send, isTrue);
      expect(decide(severity: 'MEDIUM', isDuress: true).send, isTrue);
      expect(decide(isDuress: true).because, 'duress');
    });

    test('but duress still does not send when it could not possibly work', () {
      // No radio, or no key to sign with. Spending a message on something that
      // cannot arrive helps nobody.
      expect(decide(isDuress: true, hasCellularSignal: false).send, isFalse);
      expect(decide(isDuress: true, hasDeviceKey: false).send, isFalse);
    });

    test('and never when the data path already worked, duress or not', () {
      expect(decide(isDuress: true, dataSendSucceeded: true).send, isFalse);
    });

    test('severity matching is not case-sensitive', () {
      expect(decide(severity: 'critical').send, isTrue);
      expect(decide(severity: 'High').send, isTrue);
    });
  });

  group('sending it', () {
    tearDown(() {
      SmsSender.sendOverride = null;
      SmsSender.launchOverride = null;
      SmsSender.isAndroidOverride = null;
    });

    test('Android sends silently, which is what a duress SOS requires', () async {
      SmsSender.isAndroidOverride = true;
      var sentTo = '';
      var sentBody = '';
      SmsSender.sendOverride = (d, b) async {
        sentTo = d;
        sentBody = b;
        return 1;
      };
      final outcome = await const SmsSender()
          .send(destination: '32123', body: 'OR1abc');
      expect(outcome, SmsSendOutcome.sentSilently);
      expect(sentTo, '32123');
      expect(sentBody, 'OR1abc');
    });

    test('iOS opens the composer, and says so rather than claiming a send',
        () async {
      // iOS has no programmatic SMS. The caller must know the message is not
      // gone yet and that a silent SOS is no longer silent.
      SmsSender.isAndroidOverride = false;
      Uri? opened;
      SmsSender.launchOverride = (uri) async {
        opened = uri;
        return true;
      };
      final outcome = await const SmsSender()
          .send(destination: '32123', body: 'OR1abc');
      expect(outcome, SmsSendOutcome.composerOpened);
      expect(opened!.scheme, 'sms');
      expect(opened!.path, '32123');
      expect(opened!.queryParameters['body'], 'OR1abc');
    });

    test('a refused permission falls back to the composer, not to failure',
        () async {
      // This is the path taken if Google refuses the SEND_SMS declaration.
      SmsSender.isAndroidOverride = true;
      SmsSender.sendOverride = (d, b) async =>
          throw PlatformException(code: 'SMS_DENIED', message: 'no permission');
      SmsSender.launchOverride = (uri) async => true;
      expect(
        await const SmsSender().send(destination: '32123', body: 'OR1abc'),
        SmsSendOutcome.composerOpened,
      );
    });

    test('a hard failure is reported as a failure', () async {
      SmsSender.isAndroidOverride = true;
      SmsSender.sendOverride = (d, b) async => 0;
      expect(
        await const SmsSender().send(destination: '32123', body: 'OR1abc'),
        SmsSendOutcome.failed,
      );
    });

    test('it never throws, whatever the platform does', () async {
      // An emergency path that can throw is one that can take the SOS with it.
      SmsSender.isAndroidOverride = true;
      SmsSender.sendOverride = (d, b) async => throw StateError('radio on fire');
      expect(
        await const SmsSender().send(destination: '32123', body: 'OR1abc'),
        SmsSendOutcome.failed,
      );
    });

    test('an empty destination or body is refused before anything is spent',
        () async {
      SmsSender.isAndroidOverride = true;
      var called = false;
      SmsSender.sendOverride = (d, b) async {
        called = true;
        return 1;
      };
      expect(await const SmsSender().send(destination: '', body: 'OR1abc'),
          SmsSendOutcome.failed);
      expect(await const SmsSender().send(destination: '32123', body: '  '),
          SmsSendOutcome.failed);
      expect(called, isFalse);
    });
  });
}
