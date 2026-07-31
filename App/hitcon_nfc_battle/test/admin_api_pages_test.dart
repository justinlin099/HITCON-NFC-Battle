import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_pair_user_tag_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_pixel_widgets.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_print_cards_page.dart';
import 'package:hitcon_nfc_battle/pages/admin/admin_scoreboard_control_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  setUp(() {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
  });

  Widget app(Widget child) {
    return MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('staff print page exposes scan, download, and PNG save flow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminPrintCardsPage()));

    expect(find.text('列印卡片'), findsOneWidget);
    expect(find.text('掃描條碼'), findsOneWidget);
    expect(find.text('下載圖片'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('下載圖片'));
    await tester.pump();

    expect(find.text('Token 格式不正確，應為 8 至 32 個英數字、底線或連字號。'), findsOneWidget);
  });

  testWidgets('staff pairing page requires a user ID before NFC scanning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminPairUserTagPage()));

    expect(find.text('替使用者配對 Tag'), findsOneWidget);
    await tester.tap(find.text('開始配對 Tag'));
    await tester.pump();

    expect(find.text('請先輸入要配對的 User ID。'), findsOneWidget);
  });

  testWidgets('scoreboard danger actions start disabled until status is read', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const AdminScoreboardControlPage()));

    expect(find.text('排行榜控制'), findsOneWidget);
    expect(find.text('STAFF_DANGER_TOKEN'), findsOneWidget);

    final AdminPixelButton freezeButton = tester.widget<AdminPixelButton>(
      find.widgetWithText(AdminPixelButton, '凍結排行榜'),
    );
    final AdminPixelButton resumeButton = tester.widget<AdminPixelButton>(
      find.widgetWithText(AdminPixelButton, '恢復計分'),
    );
    expect(freezeButton.onPressed, isNull);
    expect(resumeButton.onPressed, isNull);
  });
}
