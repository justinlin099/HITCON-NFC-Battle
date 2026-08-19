import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/main.dart';
import 'package:hitcon_nfc_battle/pages/user/card_collection_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/services/nfc_deep_link_service.dart';
import 'package:hitcon_nfc_battle/services/nfc_session_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppConfig.resetApiBaseUrlForTesting();
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    NfcSessionController.instance.resetForTest();
  });

  tearDown(AppConfig.resetApiBaseUrlForTesting);

  test('card UID never substitutes the owner User ID', () {
    expect(
      physicalNtagUidForCard(<String, dynamic>{
        'owner': 'kktix_hash_user',
        'physical_uid': 'kktix_hash_user',
      }),
      isEmpty,
    );
    expect(
      physicalNtagUidForCard(<String, dynamic>{
        'owner': 'kktix_hash_user',
        'physical_uid': '04:11:22:33:44:55:66',
      }),
      '04:11:22:33:44:55:66',
    );
  });

  testWidgets(
    'main title scales down instead of truncating on narrow screens',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(280, 700);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.pumpWidget(_localizedApp(const CardCollectionPage()));
        await tester.pump();

        final FittedBox fittedTitle = tester.widget<FittedBox>(
          find.byKey(const Key('home-app-bar-title-fitted')),
        );
        final Text title = tester.widget<Text>(
          find.byKey(const Key('home-app-bar-title')),
        );

        expect(fittedTitle.fit, BoxFit.scaleDown);
        expect(title.data, 'HITCON NFC Battle');
        expect(title.maxLines, 1);
        expect(title.softWrap, isFalse);
        expect(title.overflow, TextOverflow.visible);
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets('main app bar exposes the configured manual button', (
    WidgetTester tester,
  ) async {
    expect(
      AppConfig.tryApplyRemoteManualUrl(
        'https://github.com/justinlin099/HITCON-NFC-Battle#readme',
      ),
      isTrue,
    );

    await tester.pumpWidget(_localizedApp(const CardCollectionPage()));
    await tester.pump();

    final Finder manualButton = find.byKey(const Key('home-manual-button'));
    expect(manualButton, findsOneWidget);
    expect(find.byTooltip('說明書'), findsOneWidget);
    expect(
      find.descendant(
        of: manualButton,
        matching: find.byKey(const Key('home-manual-pixel-question-mark')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: manualButton, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
  });

  testWidgets('iOS collection page exposes the manual NFC scan button', (
    WidgetTester tester,
  ) async {
    int scanStartCount = 0;
    NfcDeepLinkService.instance.registerInAppScanStarter(() async {
      scanStartCount += 1;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      await tester.pumpWidget(_localizedApp(const CardCollectionPage()));
      await tester.pump();

      final Finder scanButton = find.byKey(
        const ValueKey<String>('ios-collection-scan-button'),
      );
      expect(scanButton, findsOneWidget);
      expect(
        find.descendant(of: scanButton, matching: find.text('掃描')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: scanButton,
          matching: find.byIcon(Icons.center_focus_strong_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(scanButton);
      await tester.pump();
      await tester.tap(scanButton);
      await tester.pump();

      expect(scanStartCount, 2);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android collection page keeps manual NFC scan button hidden', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      await tester.pumpWidget(_localizedApp(const CardCollectionPage()));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('ios-collection-scan-button')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS scan button shows feedback until the scan finishes', (
    WidgetTester tester,
  ) async {
    final Completer<void> scan = Completer<void>();
    int scanStartCount = 0;
    NfcDeepLinkService.instance.registerInAppScanStarter(() async {
      scanStartCount += 1;
      await scan.future;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      await tester.pumpWidget(_localizedApp(const CardCollectionPage()));
      await tester.pump();

      final Finder scanButton = find.byKey(
        const ValueKey<String>('ios-collection-scan-button'),
      );
      await tester.tap(scanButton);
      await tester.pump();

      expect(scanStartCount, 1);
      expect(
        find.descendant(of: scanButton, matching: find.text('掃描中...')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: scanButton,
          matching: find.byIcon(Icons.nfc_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(scanButton);
      await tester.pump();
      expect(scanStartCount, 1);

      scan.complete();
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(of: scanButton, matching: find.text('掃描')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'iOS scanner queues a tap made while cancellation is finishing',
    () async {
      const MethodChannel scannerChannel = MethodChannel(
        'hitcon_nfc_battle/ios_collection_nfc_scanner',
      );
      final Completer<Object?> firstScan = Completer<Object?>();
      final Completer<Object?> secondScan = Completer<Object?>();
      int scanCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(scannerChannel, (MethodCall call) {
            if (call.method == 'stop') {
              return Future<Object?>.value();
            }
            scanCalls += 1;
            return scanCalls == 1 ? firstScan.future : secondScan.future;
          });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      try {
        expect(defaultTargetPlatform, TargetPlatform.iOS);
        final AutoNtagScanner scanner = AutoNtagScanner(
          deepLinks: NfcDeepLinkService.instance,
          iosCollectionScanner: scannerChannel,
        );
        final Future<void> firstRequest = scanner.start();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(
          NfcSessionController.instance.activeOwner,
          NfcSessionOwner.collectionScanner,
        );
        expect(scanCalls, 1);

        await scanner.start();
        expect(scanCalls, 1);

        firstScan.complete(<String, Object?>{'status': 'cancelled'});
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(scanCalls, 2);

        secondScan.complete(<String, Object?>{'status': 'cancelled'});
        await firstRequest;
        scanner.dispose();
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(scannerChannel, null);
        debugDefaultTargetPlatformOverride = null;
        NfcSessionController.instance.resetForTest();
      }
    },
  );
}

Widget _localizedApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}
