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
      expect(toolLabel('縮小筆刷'), findsOneWidget);
      expect(toolLabel('放大筆刷'), findsOneWidget);
      expect(find.textContaining('撌'), findsNothing);
      expect(find.textContaining('蝑'), findsNothing);

    } finally {
      debugDefaultTargetPlatformOverride = null;
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
