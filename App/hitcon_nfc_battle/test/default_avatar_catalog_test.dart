import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/default_avatar_catalog.dart';
import 'package:hitcon_nfc_battle/pages/user/default_avatar_picker_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';
import 'package:image/image.dart' as img;

void main() {
  test('default avatar catalog contains valid square PNG assets', () {
    final Set<String> paths = <String>{};

    for (final DefaultAvatarOption option in defaultAvatarCatalog) {
      expect(paths.add(option.assetPath), isTrue);
      expect(option.labelKey, isNotEmpty);

      final File asset = File(option.assetPath);
      expect(asset.existsSync(), isTrue, reason: option.assetPath);

      final img.Image? decoded = img.decodePng(asset.readAsBytesSync());
      expect(decoded, isNotNull, reason: option.assetPath);
      expect(decoded!.width, 48, reason: option.assetPath);
      expect(decoded.height, 48, reason: option.assetPath);
    }
  });

  test('hacker seal avatar is registered as 駭客豹豹', () {
    final DefaultAvatarOption seal = defaultAvatarCatalog.singleWhere(
      (DefaultAvatarOption option) =>
          option.assetPath.endsWith('/hacker_seal.png'),
    );

    expect(seal.labelKey, 'defaultAvatarHackerSeal');
    final img.Image? decoded = img.decodePng(
      File(seal.assetPath).readAsBytesSync(),
    );
    expect(decoded, isNotNull);
    final img.Pixel corner = decoded!.getPixel(0, 0);
    expect(corner.r.toInt(), 0);
    expect(corner.g.toInt(), 25);
    expect(corner.b.toInt(), 51);
  });

  testWidgets('default avatar page title uses the pixel font', (
    WidgetTester tester,
  ) async {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh', 'TW'),
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: DefaultAvatarPickerPage(),
      ),
    );
    await tester.pump();

    final Finder titleFinder = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('預設大頭貼'),
    );
    final Text title = tester.widget<Text>(titleFinder);

    expect(title.style?.fontFamily, 'Unifont');
    expect(title.style?.fontWeight, FontWeight.w900);
  });
}
