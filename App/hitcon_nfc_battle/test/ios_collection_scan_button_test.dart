import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/card_collection_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/services/nfc_deep_link_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppConfig.resetApiBaseUrlForTesting();
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
  });

  tearDown(AppConfig.resetApiBaseUrlForTesting);

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
    bool scanStarted = false;
    NfcDeepLinkService.instance.registerInAppScanStarter(() async {
      scanStarted = true;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      await tester.pumpWidget(_localizedApp(const CardCollectionPage()));
      await tester.pump();

      final Finder scanButton = find.byKey(
        const ValueKey<String>('ios-collection-scan-button'),
      );
      expect(scanButton, findsOneWidget);

      await tester.tap(scanButton);
      await tester.pump();

      expect(scanStarted, isTrue);
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
