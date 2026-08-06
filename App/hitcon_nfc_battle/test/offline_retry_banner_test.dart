import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/offline_retry_banner.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  testWidgets('offline banner retries when tapped', (
    WidgetTester tester,
  ) async {
    int retries = 0;
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: OfflineRetryBanner(onRetry: () => retries += 1)),
      ),
    );

    expect(find.text('未連上網路，點一下重新整理。'), findsOneWidget);
    await tester.tap(find.byType(OfflineRetryBanner));
    expect(retries, 1);
  });
}
