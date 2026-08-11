import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_card_face.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_link_icon.dart';
import 'package:hitcon_nfc_battle/pages/user/setup_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('setup preview uses the latest expanded player card layout', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
        home: SetupPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    const List<String> stepTitles = <String>[
      'IMAGE',
      'BIO',
      'Link',
      'ATTRIBUTE',
      'COLOR',
      'PREVIEW',
    ];
    for (final String title in stepTitles) {
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsWidgets);
    }

    final PixelCardFace preview = tester.widget<PixelCardFace>(
      find.byKey(const Key('setup-card-preview-face')),
    );
    expect(preview.title, 'Alice');
    expect(preview.verticalHitconWatermark, isTrue);
    expect(preview.fadeExtraContentAtBottom, isTrue);
    expect(preview.fixedContent, isNotNull);
    expect(preview.extraContent, isNotNull);
    expect(preview.attributeEmoji, isEmpty);
    expect(preview.attributeLabel, contains('✨ MAGIC'));
    expect(find.byKey(const Key('setup-card-preview-link')), findsOneWidget);
    expect(find.byType(PixelLinkIcon), findsOneWidget);
    expect(find.text('No link'), findsOneWidget);
    expect(
      find.byKey(const Key('setup-card-preview-description')),
      findsOneWidget,
    );
  });
}
