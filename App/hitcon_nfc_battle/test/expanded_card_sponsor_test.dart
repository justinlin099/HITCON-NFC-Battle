import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/card_detail_page.dart';
import 'package:hitcon_nfc_battle/pages/user/panasonic_support_mark.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_card_face.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:hitcon_nfc_battle/pages/user/social_share_dialog.dart';

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
    expect(panasonicRect.bottom, lessThan(cardRect.bottom - 10));

    final Text hitconText = tester.widget<Text>(hitcon);
    expect(hitconText.style?.fontSize, greaterThan(30));
    expect(
      hitconText.style?.color?.a,
      closeTo(ExpandedPixelCardStyle.watermarkOpacity, 0.001),
    );

    final PanasonicSupportMark panasonicMark = tester.widget(panasonic);
    expect(
      panasonicMark.color.a,
      closeTo(ExpandedPixelCardStyle.watermarkOpacity, 0.001),
    );
  });

  testWidgets('expanded card matches my-card bio height and bottom fade', (
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
          heroTag: 'bio-layout-test-card',
          title: 'BIO TEST',
          attributeEmoji: '',
          attributeLabel: 'COMMUNITY',
          link: 'https://hitcon.org',
          description:
              'Line one of the introduction. Line two stays visible. '
              'Line three stays visible. Line four fades near the bottom. '
              'More content remains scrollable after that.',
          uid: '',
          collectedAt: '',
          cardColor: Color(0xFFFFD700),
          showCollectionInfo: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final Finder fade = find.byKey(
      const ValueKey<String>('my-card-description-fade'),
    );
    expect(fade, findsOneWidget);
    expect(tester.getSize(fade).height, greaterThan(60));
  });

  testWidgets('collected card opens a social share image preview', (
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
          heroTag: 'share-test-card',
          title: 'SHARE TEST',
          attributeEmoji: '✨',
          attributeLabel: 'COMMUNITY',
          link: 'https://hitcon.org',
          description: 'A collected card ready to share.',
          uid: '04:A1',
          collectedAt: '2026-08-11',
          cardColor: Color(0xFF00D9FF),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('card-detail-share')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('social-share-dialog')), findsOneWidget);
    expect(find.text('Collected SHARE TEST'), findsOneWidget);
    expect(find.text('#HITCON  #HITCON2026  #NFCBATTLE'), findsOneWidget);
    final Size posterSize = tester.getSize(
      find.byKey(const Key('social-share-poster')),
    );
    expect(posterSize, const Size(360, 360));
    expect(find.byKey(const Key('social-share-visual-fitted')), findsOneWidget);
    final Finder sharePoster = find.byKey(const Key('social-share-poster'));
    final SocialSharePoster poster = tester.widget<SocialSharePoster>(
      find.byType(SocialSharePoster),
    );
    expect(poster.detail, isNull);
    final PixelCardFace sharedCard = tester.widget<PixelCardFace>(
      find.descendant(of: sharePoster, matching: find.byType(PixelCardFace)),
    );
    expect(sharedCard.attributeMaxLines, 3);
    expect(sharedCard.stackAttributePairs, isTrue);
    final Image appIcon = tester.widget<Image>(
      find.byKey(const Key('social-share-app-icon')),
    );
    expect(appIcon.image, isA<AssetImage>());
    expect(
      (appIcon.image as AssetImage).assetName,
      'assets/app_icon/app_icon_master.png',
    );
    expect(appIcon.width, 24);
    expect(appIcon.height, 24);
    final ClipRRect appIconClip = tester.widget<ClipRRect>(
      find.byKey(const Key('social-share-app-icon-clip')),
    );
    expect(appIconClip.borderRadius, BorderRadius.circular(5));
    expect(find.byKey(const Key('social-share-submit')), findsOneWidget);
  });
}
