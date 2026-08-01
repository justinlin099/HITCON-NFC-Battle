import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_home_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_pair_user_tag_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_pixel_widgets.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_print_cards_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_scoreboard_control_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/services/nfc_session_controller.dart';

void main() {
  setUp(() {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
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

  testWidgets('staff pairing page requires a user ID before NFC scanning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminPairUserTagPage()));

    expect(find.text('替使用者配對 Tag'), findsOneWidget);
    await tester.tap(find.text('開始配對 Tag'));
    await tester.pump();

    expect(find.text('請先輸入要配對的 User ID。'), findsOneWidget);
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
      await tester.pump();

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
      await tester.pump();

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
