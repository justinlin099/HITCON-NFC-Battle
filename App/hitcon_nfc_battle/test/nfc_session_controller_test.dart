import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/nfc_session_controller.dart';

void main() {
  late NfcSessionController controller;

  setUp(() {
    controller = NfcSessionController.instance;
    controller.resetForTest();
  });

  tearDown(() {
    controller.resetForTest();
  });

  test('blocks app-wide scanner while a tool owns NFC', () async {
    final NfcSessionLease? toolLease = await controller.acquire(
      NfcSessionOwner.ntagReader,
    );

    final NfcSessionLease? appWideLease = await controller.acquire(
      NfcSessionOwner.appWideScanner,
    );

    expect(toolLease, isNotNull);
    expect(toolLease!.isActive, isTrue);
    expect(appWideLease, isNull);
    expect(controller.activeOwner, NfcSessionOwner.ntagReader);
  });

  test('lets foreground tools preempt app-wide scanner', () async {
    var appWideWasPreempted = false;

    final NfcSessionLease? appWideLease = await controller.acquire(
      NfcSessionOwner.appWideScanner,
      onPreempt: () {
        appWideWasPreempted = true;
      },
    );

    final NfcSessionLease? toolLease = await controller.acquire(
      NfcSessionOwner.ntagReader,
      preemptExisting: true,
    );

    expect(appWideLease, isNotNull);
    expect(appWideLease!.isActive, isFalse);
    expect(appWideWasPreempted, isTrue);
    expect(toolLease, isNotNull);
    expect(toolLease!.isActive, isTrue);
    expect(controller.activeOwner, NfcSessionOwner.ntagReader);
  });

  test('does not let an old lease release the new owner', () async {
    final NfcSessionLease? appWideLease = await controller.acquire(
      NfcSessionOwner.appWideScanner,
    );
    final NfcSessionLease? toolLease = await controller.acquire(
      NfcSessionOwner.badgePairing,
      preemptExisting: true,
    );

    appWideLease!.release();

    expect(toolLease, isNotNull);
    expect(toolLease!.isActive, isTrue);
    expect(controller.activeOwner, NfcSessionOwner.badgePairing);
  });

  test('releases the owner when the active lease ends', () async {
    final NfcSessionLease? lease = await controller.acquire(
      NfcSessionOwner.badgePairing,
    );

    lease!.release();

    expect(lease.isActive, isFalse);
    expect(controller.activeOwner, isNull);
  });
}
