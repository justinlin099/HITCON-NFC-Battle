import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/card_collection_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  const String manualUrl = 'https://guide.hitcon2026.online/manual';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppConfig.resetApiBaseUrlForTesting();
    AppConfig.tryApplyRemoteManualUrl(manualUrl);
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
  });

  tearDown(AppConfig.resetApiBaseUrlForTesting);

  testWidgets('declining the manual shows where it can be opened later', (
    WidgetTester tester,
  ) async {
    bool launched = false;
    await tester.pumpWidget(
      _promptApp(
        manualLauncher: (Uri uri) async {
          launched = true;
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('post-setup-manual-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('post-setup-manual-later')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('manual-access-hint')), findsOneWidget);
    expect(find.text('之後想再查看說明書，可以點左上角的「？」圖示。'), findsOneWidget);
    expect(launched, isFalse);
  });

  testWidgets('opening the manual shows the hint before launching browser', (
    WidgetTester tester,
  ) async {
    Uri? launchedUri;
    await tester.pumpWidget(
      _promptApp(
        manualLauncher: (Uri uri) async {
          launchedUri = uri;
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byKey(const Key('post-setup-manual-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('manual-access-hint')), findsOneWidget);
    expect(launchedUri, Uri.parse(manualUrl));
  });
}

Widget _promptApp({required Future<bool> Function(Uri uri) manualLauncher}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    initialRoute: '/collection',
    onGenerateRoute: (RouteSettings settings) => null,
    onGenerateInitialRoutes: (String initialRoute) => <Route<dynamic>>[
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: '/collection',
          arguments: <String, Object>{'tab': 1, 'promptManualAfterSetup': true},
        ),
        builder: (BuildContext context) =>
            CardCollectionPage(manualLauncher: manualLauncher),
      ),
    ],
  );
}
