import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_unpair_user_tag_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  setUp(() {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
  });

  testWidgets('staff unpair requires a user ID before NFC scanning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdminUnpairUserTagPage()),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('staff-unpair-start-button')),
    );
    await tester.pump();

    expect(find.text('Enter the User ID to unpair.'), findsOneWidget);
  });
}
