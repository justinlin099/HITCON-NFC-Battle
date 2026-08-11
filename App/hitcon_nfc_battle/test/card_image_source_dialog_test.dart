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

  testWidgets('card image source buttons show pixel-style icons', (
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
        home: const Scaffold(body: MyCardEditorPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder imageEditorButton = find.byKey(
      const Key('my-card-image-editor-button'),
    );
    await tester.ensureVisible(imageEditorButton);
    await tester.tap(imageEditorButton);
    await tester.pumpAndSettle();

    const List<String> buttonKeys = <String>[
      'card-image-source-draw-button',
      'card-image-source-import-button',
      'card-image-source-default-button',
      'card-image-source-cancel-button',
    ];
    const List<String> iconKeys = <String>[
      'card-image-source-draw-icon',
      'card-image-source-import-icon',
      'card-image-source-default-icon',
      'card-image-source-cancel-icon',
    ];

    expect(find.text('選擇圖片來源'), findsOneWidget);
    for (final String key in buttonKeys) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    for (final String key in iconKeys) {
      final Finder icon = find.byKey(Key(key));
      expect(icon, findsOneWidget);
      expect(tester.getSize(icon), const Size(24, 24));
    }
  });
}
