import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_home_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_pair_user_tag_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_pixel_widgets.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_print_cards_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_scoreboard_control_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/services/nfc_deep_link_service.dart';
import 'package:hitcon_nfc_battle/services/nfc_session_controller.dart';
import 'package:hitcon_nfc_battle/services/auth_service.dart';

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeNfcChannel, null);
  });

  Widget app(Widget child) {
    return MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('staff print page exposes scan, download, and PNG save flow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminPrintCardsPage()));

    expect(find.text('列印卡片'), findsOneWidget);
    expect(find.text('掃描條碼'), findsOneWidget);
    expect(find.text('下載圖片'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('下載圖片'));
    await tester.pump();

    expect(find.text('Token 格式不正確，應為 8 至 32 個英數字、底線或連字號。'), findsOneWidget);
  });

  testWidgets('staff pairing requires a user ID before NFC scanning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminPairUserTagPage()));
    await tester.tap(find.text('開始配對 Tag'));
    await tester.pump();

    expect(find.text('請先輸入要配對的 User ID。'), findsOneWidget);
  });

  testWidgets('staff pairing reads a user ID before scanning another tag', (
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
      await tester.pumpWidget(app(const AdminPairUserTagPage()));
      await tester.tap(find.text('從 NTAG 讀取 User ID'));
      await tester.pumpAndSettle();
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

      await tester.tap(find.text('開始配對 Tag'));
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
      NfcSessionController.instance.resetForTest();
    }
  });

  testWidgets('staff unlock can select production or staging API', (
    WidgetTester tester,
  ) async {
    addTearDown(AppConfig.resetApiBaseUrlForTesting);
    expect(
      AppConfig.tryApplyRemoteApiBaseUrl('https://game.hitcon2026.online'),
      isTrue,
    );

    await tester.pumpWidget(app(const AdminTagUnlockPage()));

    expect(find.text('解鎖碼來源'), findsNWidgets(2));
    expect(find.text('正式 API（線上設定）'), findsNWidgets(2));
    expect(
      find.textContaining('https://game.hitcon2026.online'),
      findsOneWidget,
    );
    expect(
      find.textContaining(AppConfig.staffUnlockStagingApiBaseUrl),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('selected-staff-unlock-api-production'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('staff-unlock-api-staging')),
    );
    await tester.pump();

    expect(find.text('登入 STAGING API'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('staging-login-token-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('selected-staff-unlock-api-production'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-staging-token')),
    );
    await tester.pump();
    expect(find.text('請輸入 Staging 登入 Token。'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('staging-login-token-field')),
      'staging-test-token',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-staging-token')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('selected-staff-unlock-api-staging')),
      findsOneWidget,
    );
    expect(find.text('STAGING API'), findsNWidgets(2));

    await tester.tap(
      find.byKey(const ValueKey<String>('staff-unlock-api-production')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('staff-unlock-api-staging')),
    );
    await tester.pump();

    expect(find.text('登入 STAGING API'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('staging-login-token-field')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('cancel-staging-token')),
    );
    await tester.pumpAndSettle();
  });

  test('staff unlock API targets resolve independently', () {
    addTearDown(AppConfig.resetApiBaseUrlForTesting);
    expect(
      AppConfig.tryApplyRemoteApiBaseUrl('https://game.hitcon2026.online'),
      isTrue,
    );

    expect(
      staffNtagUnlockApiBaseUrl(StaffNtagUnlockApiTarget.production),
      'https://game.hitcon2026.online',
    );
    expect(
      staffNtagUnlockApiBaseUrl(StaffNtagUnlockApiTarget.staging),
      AppConfig.staffUnlockStagingApiBaseUrl,
    );
  });

  testWidgets('staff prize page lists stamp, ranking, and soldering prizes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminPrizeClaimPage()));

    expect(find.text('獎項類型'), findsNWidgets(2));
    expect(find.text('STAMP PRIZE'), findsNWidgets(2));
    expect(find.text('集滿 Sponsor 與 Community 印章的集章獎'), findsOneWidget);
    expect(find.text('RANKING PRIZE'), findsOneWidget);
    expect(find.text('排行榜結算獎項（需先凍結排行榜）'), findsOneWidget);
    expect(find.text('EXTERNAL PRIZE'), findsOneWidget);
    expect(find.text('焊接活動獎項'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('selected-prize-type-STAMP')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('prize-type-EXTERNAL')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('selected-prize-type-EXTERNAL')),
      findsOneWidget,
    );
    expect(find.text('EXTERNAL PRIZE'), findsNWidgets(2));
  });

  testWidgets('staff pairing owns NFC before starting the reader', (
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

    final NfcSessionController sessions = NfcSessionController.instance;
    sessions.resetForTest();
    bool collectionWasPreempted = false;
    final NfcSessionLease? collectionLease = await sessions.acquire(
      NfcSessionOwner.collectionScanner,
      onPreempt: () {
        collectionWasPreempted = true;
      },
    );

    try {
      await tester.pumpWidget(app(const AdminPairUserTagPage()));
      await tester.enterText(find.byType(TextField), 'user-123');
      await tester.tap(find.text('開始配對 Tag'));
      await tester.pumpAndSettle();

      expect(collectionLease!.isActive, isFalse);
      expect(collectionWasPreempted, isTrue);
      expect(sessions.activeOwner, NfcSessionOwner.badgePairing);
      expect(
        platformCalls,
        containsAllInOrder(<String>[
          'Nfc#isAvailable',
          'Nfc#stopSession',
          'Nfc#startSession',
        ]),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        nfcChannel,
        null,
      );
      sessions.resetForTest();
    }
  });

  testWidgets('staff NTag readers request ISO 14443 only', (
    WidgetTester tester,
  ) async {
    const MethodChannel nfcChannel = MethodChannel(
      'plugins.flutter.io/nfc_manager',
    );
    final List<MethodCall> platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(nfcChannel, (
      MethodCall call,
    ) async {
      platformCalls.add(call);
      return call.method == 'Nfc#isAvailable' ? true : null;
    });

    Future<void> expectIso14443(
      Widget page,
      String button, {
      bool verifyIosUid = false,
    }) async {
      platformCalls.clear();
      NfcSessionController.instance.resetForTest();
      await tester.pumpWidget(app(page));
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();

      final MethodCall startCall = platformCalls.firstWhere(
        (MethodCall call) => call.method == 'Nfc#startSession',
      );
      expect(
        (startCall.arguments as Map<Object?, Object?>)['pollingOptions'],
        <String>['iso14443'],
      );

      if (verifyIosUid) {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          nfcChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onDiscovered', <String, Object>{
              'handle': 'ios-tag',
              'mifare': <String, Object>{
                'identifier': <int>[0x04, 0xA1, 0xB2, 0xC3],
              },
            }),
          ),
          (_) {},
        );
        await tester.pump();
        expect(find.text('04:A1:B2:C3'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    try {
      await expectIso14443(
        const AdminTagWriterPage(),
        '寫入 Tag',
        verifyIosUid: true,
      );
      await expectIso14443(const AdminPrizeClaimPage(), '開始掃描');
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        nfcChannel,
        null,
      );
      NfcSessionController.instance.resetForTest();
    }
  });

  testWidgets('scoreboard danger actions start disabled until status is read', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminScoreboardControlPage()));

    expect(find.text('排行榜控制'), findsOneWidget);
    expect(find.text('STAFF_DANGER_TOKEN'), findsOneWidget);

    final AdminPixelButton freezeButton = tester.widget<AdminPixelButton>(
      find.widgetWithText(AdminPixelButton, '凍結排行榜'),
    );
    final AdminPixelButton resumeButton = tester.widget<AdminPixelButton>(
      find.widgetWithText(AdminPixelButton, '恢復計分'),
    );
    expect(freezeButton.onPressed, isNull);
    expect(resumeButton.onPressed, isNull);
  });
}
