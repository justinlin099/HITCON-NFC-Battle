import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/nfc_deep_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel nativeNfcChannel = MethodChannel(
    'hitcon_nfc_battle/nfc_intent',
  );
  late NfcDeepLinkService service;
  late List<bool> maintenanceModes;

  setUp(() {
    service = NfcDeepLinkService.instance;
    service.resetTagMaintenanceForTest();
    maintenanceModes = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeNfcChannel, (MethodCall call) async {
          if (call.method == 'setTagMaintenanceMode') {
            final Map<Object?, Object?> arguments =
                call.arguments as Map<Object?, Object?>;
            maintenanceModes.add(arguments['enabled'] == true);
          }
          return null;
        });
  });

  tearDown(() {
    service.resetTagMaintenanceForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeNfcChannel, null);
  });

  test('drops scan requests while a tag maintenance page owns NFC', () async {
    await service.beginTagMaintenance();
    service.publish(
      const NfcScanRequest(
        userId: 'attendee_001',
        physicalUid: '04:11:22:33:44:55:66',
        launchEvidence: NfcLaunchEvidence.physicalTag,
      ),
    );

    expect(service.takePending(), isNull);
  });

  test('keeps a cooldown after tag maintenance navigation closes', () async {
    await service.beginTagMaintenance();
    await service.endTagMaintenance(cooldown: const Duration(seconds: 1));
    service.publish(
      const NfcScanRequest(
        userId: 'attendee_001',
        physicalUid: '04:11:22:33:44:55:66',
        launchEvidence: NfcLaunchEvidence.physicalTag,
      ),
    );

    expect(service.takePending(), isNull);
  });

  test('accepts scans after maintenance ends without a cooldown', () async {
    await service.beginTagMaintenance();
    await service.endTagMaintenance(cooldown: Duration.zero);
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
    expect(maintenanceModes, <bool>[true, false]);
  });

  test('accepts a login token from the canonical b link', () async {
    const String token =
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhdHRlbmRlZV80In0.signature_123';
    final Future<String> emittedToken = service.loginTokens.first;

    await service.acceptUri(
      Uri.https('game.hitcon2026.online', '/b', <String, String>{
        'token': token,
      }),
    );

    expect(await emittedToken, token);
    expect(service.takePendingLoginToken(), token);
    expect(service.takePending(), isNull);
  });

  test('keeps b links with a user id in the collection flow', () async {
    const String token =
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhdHRlbmRlZV80In0.signature_123';

    await service.acceptUri(
      Uri.https('game.hitcon2026.online', '/b', <String, String>{
        'u': 'attendee_001',
        'token': token,
      }),
    );

    expect(service.takePendingLoginToken(), isNull);
    final NfcScanRequest? pending = service.takePending();
    expect(pending, isNotNull);
    expect(pending!.userId, 'attendee_001');
  });

  test('rejects malformed login tokens and untrusted hosts', () async {
    await service.acceptUri(
      Uri.https('game.hitcon2026.online', '/b', <String, String>{
        'token': 'not-a-jwt',
      }),
    );
    await service.acceptUri(
      Uri.https('example.com', '/b', <String, String>{
        'token': 'header.payload.signature',
      }),
    );

    expect(service.takePendingLoginToken(), isNull);
    expect(service.takePending(), isNull);
  });
}
