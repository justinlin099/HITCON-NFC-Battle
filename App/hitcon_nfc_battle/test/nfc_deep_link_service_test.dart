import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/nfc_deep_link_service.dart';

void main() {
  late NfcDeepLinkService service;

  setUp(() {
    service = NfcDeepLinkService.instance;
    service.resetTagMaintenanceForTest();
  });

  tearDown(() {
    service.resetTagMaintenanceForTest();
  });

  test('drops scan requests while a tag maintenance page owns NFC', () {
    service.beginTagMaintenance();
    service.publish(
      const NfcScanRequest(
        userId: 'attendee_001',
        physicalUid: '04:11:22:33:44:55:66',
        launchEvidence: NfcLaunchEvidence.physicalTag,
      ),
    );

    expect(service.takePending(), isNull);
  });

  test('keeps a cooldown after tag maintenance navigation closes', () {
    service.beginTagMaintenance();
    service.endTagMaintenance(cooldown: const Duration(seconds: 1));
    service.publish(
      const NfcScanRequest(
        userId: 'attendee_001',
        physicalUid: '04:11:22:33:44:55:66',
        launchEvidence: NfcLaunchEvidence.physicalTag,
      ),
    );

    expect(service.takePending(), isNull);
  });

  test('accepts scans after maintenance ends without a cooldown', () {
    service.beginTagMaintenance();
    service.endTagMaintenance(cooldown: Duration.zero);
    service.publish(
      const NfcScanRequest(
        userId: 'attendee_002',
        physicalUid: '04:AA:BB:CC:DD:EE:FF',
        launchEvidence: NfcLaunchEvidence.physicalTag,
      ),
    );

    final NfcScanRequest? pending = service.takePending();
    expect(pending, isNotNull);
    expect(pending!.userId, 'attendee_002');
  });
}
