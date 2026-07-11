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

  test('blocks collection scanner while a tool owns NFC', () async {
    final NfcSessionLease? toolLease = await controller.acquire(
      NfcSessionOwner.ntagReader,
    );

    final NfcSessionLease? collectionLease = await controller.acquire(
      NfcSessionOwner.collectionScanner,
    );

    expect(toolLease, isNotNull);
    expect(toolLease!.isActive, isTrue);
    expect(collectionLease, isNull);
    expect(controller.activeOwner, NfcSessionOwner.ntagReader);
  });

  test('lets foreground tools preempt collection scanner', () async {
    var collectionScannerWasPreempted = false;

    final NfcSessionLease? collectionLease = await controller.acquire(
      NfcSessionOwner.collectionScanner,
      onPreempt: () {
        collectionScannerWasPreempted = true;
      },
    );

    final NfcSessionLease? toolLease = await controller.acquire(
      NfcSessionOwner.ntagReader,
      preemptExisting: true,
    );

    expect(collectionLease, isNotNull);
    expect(collectionLease!.isActive, isFalse);
    expect(collectionScannerWasPreempted, isTrue);
    expect(toolLease, isNotNull);
    expect(toolLease!.isActive, isTrue);
    expect(controller.activeOwner, NfcSessionOwner.ntagReader);
  });

  test('does not let an old lease release the new owner', () async {
    final NfcSessionLease? collectionLease = await controller.acquire(
      NfcSessionOwner.collectionScanner,
    );
    final NfcSessionLease? toolLease = await controller.acquire(
      NfcSessionOwner.badgePairing,
      preemptExisting: true,
    );

    collectionLease!.release();

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
