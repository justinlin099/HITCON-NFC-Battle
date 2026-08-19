import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/main.dart';
import 'package:hitcon_nfc_battle/pages/user/panasonic_support_mark.dart';

void main() {
  test('iOS delegates universal links exclusively to app_links', () {
    final File infoPlist = File('ios/Runner/Info.plist');
    final String source = infoPlist.readAsStringSync();

    expect(
      source,
      contains('<key>FlutterDeepLinkingEnabled</key>\n\t<false/>'),
      reason:
          'Flutter built-in deep linking must remain disabled while app_links '
          'handles Universal Links, otherwise iOS can dispatch the same link '
          'twice and reopen it in Safari.',
    );
  });

  test('native launch screens stay plain before Flutter branding', () {
    final String android12 = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();
    final String androidLegacy = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final String ios = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();

    expect(
      android12,
      contains(
        '<item name="android:windowSplashScreenAnimatedIcon">'
        '@android:color/transparent</item>',
      ),
    );
    expect(android12, isNot(contains('windowSplashScreenBrandingImage')));
    expect(androidLegacy, isNot(contains('@drawable/launch_content')));
    expect(ios, isNot(contains('image="LaunchAppIcon"')));
    expect(ios, isNot(contains('image="LaunchPanasonicLogo"')));
  });

  testWidgets(
    'session restore screen replaces the progress circle with logos',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());

      expect(
        find.byKey(const ValueKey<String>('startup-app-icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('startup-panasonic-mark')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(PanasonicSupportMark), findsOneWidget);

      final Text caption = tester.widget<Text>(find.text('Supported by'));
      expect(caption.style?.fontFamily, 'Unifont');

      final Size screenSize = tester.getSize(find.byType(Scaffold));
      final Rect appIcon = tester.getRect(
        find.byKey(const ValueKey<String>('startup-app-icon')),
      );
      final Rect sponsorMark = tester.getRect(
        find.byKey(const ValueKey<String>('startup-panasonic-mark')),
      );
      expect(appIcon.center.dy, closeTo(screenSize.height / 2, 0.1));
      expect(sponsorMark.bottom, closeTo(screenSize.height - 48, 0.1));
    },
  );
}
