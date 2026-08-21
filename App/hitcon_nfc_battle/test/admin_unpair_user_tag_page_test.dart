import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_unpair_user_tag_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/services/nfc_deep_link_service.dart';
import 'package:hitcon_nfc_battle/services/nfc_session_controller.dart';

void main() {
  const MethodChannel nativeNfcChannel = MethodChannel(
    'hitcon_nfc_battle/nfc_intent',
  );

  setUp(() {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    NfcDeepLinkService.instance.resetTagMaintenanceForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeNfcChannel, (_) async => null);
  });

  tearDown(() {
    NfcDeepLinkService.instance.resetTagMaintenanceForTest();
    NfcSessionController.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeNfcChannel, null);
  });

  Widget app() {
    return const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: AdminUnpairUserTagPage()),
    );
  }

  testWidgets('staff unpair requires a user ID before NFC scanning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());

    await tester.tap(
      find.byKey(const ValueKey<String>('staff-unpair-start-button')),
    );
    await tester.pump();

    expect(find.text('Enter the User ID to unpair.'), findsOneWidget);
  });

  testWidgets('staff unpair reads a user ID before scanning the tag again', (
    WidgetTester tester,
  ) async {
    const MethodChannel nfcChannel = MethodChannel(
      'plugins.flutter.io/nfc_manager',
    );
    final List<String> platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(nfcChannel, (
      MethodCall call,
    ) async {
      platformCalls.add(call.method);
      return call.method == 'Nfc#isAvailable' ? true : null;
    });
    NfcSessionController.instance.resetForTest();

    try {
      await tester.pumpWidget(app());
      await tester.ensureVisible(find.text('Read User ID from NTAG'));
      await tester.tap(find.text('Read User ID from NTAG'));
      await tester.pumpAndSettle();
      expect(
        platformCalls.where((String call) => call == 'Nfc#startSession'),
        hasLength(1),
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        nfcChannel.name,
        StandardMethodCodec().encodeMethodCall(
          MethodCall('onDiscovered', <String, Object>{
            'handle': 'ntag-user-id',
            'mifare': <String, Object>{
              'identifier': Uint8List.fromList(<int>[0x04, 0xA1, 0xB2, 0xC3]),
            },
            'ndef': <String, Object>{
              'isWritable': false,
              'maxSize': 144,
              'cachedMessage': <String, Object>{
                'records': <Map<String, Object>>[
                  <String, Object>{
                    'typeNameFormat': 0x01,
                    'type': Uint8List.fromList(<int>[0x55]),
                    'identifier': Uint8List(0),
                    'payload': Uint8List.fromList(<int>[
                      0x04,
                      ...'game.hitcon2026.online/b?u=test_attendee_004'
                          .codeUnits,
                    ]),
                  },
                ],
              },
            },
          }),
        ),
        (_) {},
      );
      await tester.pump();

      expect(find.textContaining('Read User ID:'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'test_attendee_004',
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        platformCalls.where((String call) => call == 'Ndef#write'),
        isEmpty,
      );
      expect(
        platformCalls.where((String call) => call == 'Nfc#startSession'),
        hasLength(1),
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('staff-unpair-start-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('staff-unpair-start-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(
        platformCalls.where((String call) => call == 'Nfc#startSession'),
        hasLength(2),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        nfcChannel,
        null,
      );
    }
  });
}
