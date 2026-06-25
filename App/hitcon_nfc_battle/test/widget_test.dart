import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/main.dart';

void main() {
  testWidgets('mock login page renders as initial route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('🧪 角色測試面板'), findsOneWidget);
    expect(find.text('🔴 測試模式已啟用'), findsOneWidget);
    expect(find.text('🔧 管理者'), findsOneWidget);
    expect(find.text('🎮 玩家'), findsOneWidget);
  });

  testWidgets('NTag reader route renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/home');
    await tester.pumpAndSettle();

    expect(find.text('NTag Reader'), findsOneWidget);
    expect(find.textContaining('狀態：'), findsOneWidget);
    expect(find.textContaining('Tag ID:'), findsOneWidget);
    expect(find.text('NDEF 內容'), findsOneWidget);
  });
}
