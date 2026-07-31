import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/card_collection_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/services/nfc_deep_link_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
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
