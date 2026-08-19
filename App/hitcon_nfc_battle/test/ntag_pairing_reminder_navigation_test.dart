import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/my_card_editor_page.dart';
import 'package:hitcon_nfc_battle/pages/user/ntag_pairing_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
  });

  testWidgets('a reminder pairing request opens the NFC pairing page', (
    WidgetTester tester,
  ) async {
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
        home: const Scaffold(body: MyCardEditorPage(pairingRequest: 1)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(NtagPairingPage), findsOneWidget);
    expect(find.text('配對 NTAG Badge'), findsOneWidget);
  });
}
