import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/card_detail_page.dart';
import 'package:hitcon_nfc_battle/pages/user/panasonic_support_mark.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_card_face.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  testWidgets('expanded card places Panasonic left of HITCON', (
    WidgetTester tester,
  ) async {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    tester.view.physicalSize = const Size(390, 844);
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
        home: CardDetailPage(
          heroTag: 'sponsor-test-card',
          title: 'TEST CARD',
          attributeEmoji: '✨',
          attributeLabel: 'Magic',
          link: 'https://hitcon.org',
          description: 'Sponsor placement test.',
          uid: '',
          collectedAt: '',
          cardColor: Color(0xFFFFD700),
          showCollectionInfo: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final Finder panasonic = find.byType(PanasonicSupportMark);
    final Finder hitcon = find.byKey(
      const ValueKey<String>('hitcon-watermark'),
    );
    expect(panasonic, findsOneWidget);
    expect(hitcon, findsOneWidget);
    expect(
      find.descendant(of: panasonic, matching: find.byType(CustomPaint)),
      findsNothing,
    );

    final Rect cardRect = tester.getRect(find.byType(PixelCardFace));
    final Rect panasonicRect = tester.getRect(panasonic);
    final Rect hitconRect = tester.getRect(hitcon);
    expect(panasonicRect.center.dx, lessThan(hitconRect.center.dx));
    expect(panasonicRect.left, greaterThan(cardRect.left + 3));
    expect(panasonicRect.bottom, lessThan(cardRect.bottom - 3));

    final Text hitconText = tester.widget<Text>(hitcon);
    expect(hitconText.style?.fontSize, greaterThan(30));
  });
}
