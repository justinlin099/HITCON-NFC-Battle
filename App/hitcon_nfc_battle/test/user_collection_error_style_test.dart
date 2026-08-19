import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_refresh_overlay.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/pages/user/user_collection_page.dart';

void main() {
  testWidgets('user collection failure uses pixel refresh and retry controls', (
    WidgetTester tester,
  ) async {
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
        home: const UserCollectionPage(
          userId: 'offline-user',
          displayName: 'Offline User',
          emojiIcon: '',
          rank: 1,
          score: 99,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PixelRefreshOverlay), findsOneWidget);
    expect(
      find.byKey(const Key('user-collection-pixel-retry')),
      findsOneWidget,
    );
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });
}
