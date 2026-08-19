import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/my_card_editor_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppConfig.resetApiBaseUrlForTesting();
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
  });

  tearDown(AppConfig.resetApiBaseUrlForTesting);

  testWidgets('remote flag disables and grays out attendee Tag unlock', (
    WidgetTester tester,
  ) async {
    AppConfig.applyRemoteAllowUserTagUnlock(false);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MyCardEditorPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder unlockLabel = find.text('Unlock NTAG');
    await tester.scrollUntilVisible(
      unlockLabel,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.text('Tag unlock is currently disabled for attendees'),
      findsOneWidget,
    );
    final GestureDetector button = tester.widget<GestureDetector>(
      find.ancestor(of: unlockLabel, matching: find.byType(GestureDetector)),
    );
    expect(button.onTap, isNull);
  });
}
