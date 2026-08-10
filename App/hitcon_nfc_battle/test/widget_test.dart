import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/main.dart';
import 'package:hitcon_nfc_battle/pages/debug/test_login_page.dart';
import 'package:hitcon_nfc_battle/pages/user/my_card_editor_page.dart';

void main() {
  testWidgets('server token login page renders as initial route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(locale: const Locale('en'), child: const TestLoginPage()),
    );

    expect(find.byType(TestLoginPage), findsOneWidget);
    expect(find.text('Login token'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('NTag reader route renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/home');
    await tester.pumpAndSettle();

    expect(find.byType(NTagReaderPage), findsOneWidget);
    expect(find.text('NTag Reader'), findsOneWidget);
  });

  testWidgets('pixel editor toolbar labels match their actions', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'zh',
      'TW',
    );
    try {
      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('zh', 'TW'),
          child: const TestLoginPage(),
        ),
      );

      final BuildContext loginContext = tester.element(
        find.byType(TestLoginPage),
      );
      unawaited(
        openBlankCardPixelEditor(
          loginContext,
          cardColor: const Color(0xFFFFD700),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      Finder toolLabel(String text) => find.text(text, skipOffstage: false);

      expect(toolLabel('匯入'), findsOneWidget);
      expect(toolLabel('清空'), findsOneWidget);
      expect(toolLabel('筆刷 ON'), findsOneWidget);
      expect(toolLabel('橡皮擦'), findsOneWidget);
      expect(toolLabel('填色'), findsOneWidget);
      expect(toolLabel('取色'), findsOneWidget);
      expect(toolLabel('復原'), findsOneWidget);
      expect(toolLabel('重做'), findsOneWidget);
      expect(toolLabel('網格開啟'), findsOneWidget);
      expect(toolLabel('縮小筆刷'), findsNothing);
      expect(toolLabel('放大筆刷'), findsNothing);
      final Finder brushSizeSliderFinder = find.byKey(
        const Key('pixel-editor-brush-size-slider'),
        skipOffstage: false,
      );
      expect(brushSizeSliderFinder, findsOneWidget);
      expect(
        find.byKey(
          const Key('pixel-editor-brush-size-preview'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pixel-editor-apply-button'), skipOffstage: false),
        findsOneWidget,
      );

      final SingleChildScrollView editorScrollView = tester
          .widget<SingleChildScrollView>(
            find.byKey(
              const Key('pixel-editor-scroll-view'),
              skipOffstage: false,
            ),
          );
      expect(editorScrollView.controller?.position.maxScrollExtent, 0);

      final Slider brushSizeSlider = tester.widget<Slider>(
        brushSizeSliderFinder,
      );
      expect(brushSizeSlider.min, 1);
      expect(brushSizeSlider.max, 3);
      expect(brushSizeSlider.divisions, 2);
      brushSizeSlider.onChanged?.call(3);
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('pixel-editor-brush-size-value'),
                skipOffstage: false,
              ),
            )
            .data,
        '筆刷粗細：3',
      );

      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      expect(
        editorScrollView.controller?.position.maxScrollExtent,
        greaterThan(0),
      );
      expect(find.textContaining('撌'), findsNothing);
      expect(find.textContaining('蝑'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearLocaleTestValue();
    }
  });
}

Widget _localizedApp({required Locale locale, required Widget child}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}
