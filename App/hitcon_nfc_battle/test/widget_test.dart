// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/main.dart';

void main() {
  testWidgets('NTag reader page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('NTag Reader'), findsOneWidget);
    expect(find.textContaining('狀態：'), findsOneWidget);
    expect(find.textContaining('Tag ID:'), findsOneWidget);
    expect(find.text('NDEF 內容'), findsOneWidget);
  });
}
