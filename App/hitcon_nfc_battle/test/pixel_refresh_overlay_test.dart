import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_refresh_overlay.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  testWidgets('pixel refresh overlay replaces the material spinner', (
    WidgetTester tester,
  ) async {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    final ValueNotifier<RefreshIndicatorStatus?> status =
        ValueNotifier<RefreshIndicatorStatus?>(RefreshIndicatorStatus.refresh);
    final ValueNotifier<double> distance = ValueNotifier<double>(48);
    addTearDown(status.dispose);
    addTearDown(distance.dispose);

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
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              PixelRefreshOverlay(
                statusListenable: status,
                pullDistanceListenable: distance,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('同步中...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
