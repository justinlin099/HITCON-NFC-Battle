import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/main.dart';
import 'package:hitcon_nfc_battle/pages/user/my_card_editor_page.dart';

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

  testWidgets('pixel editor toolbar labels match their actions', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const MyApp());

      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/collection');
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的卡片'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('點擊設定圖片'));
      await tester.pumpAndSettle();

      Finder toolLabel(String text) => find.text(text, skipOffstage: false);

      expect(toolLabel('匯入圖片'), findsOneWidget);
      expect(toolLabel('清空畫布'), findsOneWidget);
      expect(toolLabel('筆刷 ON'), findsOneWidget);
      expect(toolLabel('橡皮擦'), findsOneWidget);
      expect(toolLabel('填滿'), findsOneWidget);
      expect(toolLabel('吸色'), findsOneWidget);
      expect(toolLabel('復原'), findsOneWidget);
      expect(toolLabel('重做'), findsOneWidget);
      expect(toolLabel('網格 ON'), findsOneWidget);
      expect(toolLabel('筆刷-'), findsOneWidget);
      expect(toolLabel('筆刷+'), findsOneWidget);
      expect(find.textContaining('工具: 筆刷'), findsOneWidget);
      expect(find.textContaining('撌'), findsNothing);
      expect(find.textContaining('蝑'), findsNothing);

      final Finder canvasFinder = find.byWidgetPredicate(
        (Widget widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_PixelCanvasPainter',
      );

      expect(canvasFinder, findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);

      PixelGrid canvasPixels() {
        final CustomPaint paintedCanvas = tester.widget<CustomPaint>(
          canvasFinder,
        );
        final dynamic painter = paintedCanvas.painter;
        return painter.pixels as PixelGrid;
      }

      final Size canvasSize = tester.getSize(canvasFinder);
      final Offset canvasTopLeft = tester.getTopLeft(canvasFinder);
      final double cellSize = canvasSize.width / 48;
      Offset cellCenter(int x, int y) =>
          canvasTopLeft + Offset((x + 0.5) * cellSize, (y + 0.5) * cellSize);

      final Offset lineStart = cellCenter(4, 12);
      final Offset lineEnd = cellCenter(20, 12);
      final TestGesture drawGesture = await tester.startGesture(lineStart);
      await drawGesture.moveBy(lineEnd - lineStart);
      await drawGesture.up();
      await tester.pump();

      PixelGrid pixels = canvasPixels();
      for (int x = 4; x <= 20; x++) {
        expect(pixels[12][x], isNotNull);
      }

      await tester.tap(find.text('復原'));
      await tester.pump();

      pixels = canvasPixels();
      for (int x = 4; x <= 20; x++) {
        expect(pixels[12][x], isNull);
      }

      await tester.tap(find.text('重做'));
      await tester.pump();

      pixels = canvasPixels();
      for (int x = 4; x <= 20; x++) {
        expect(pixels[12][x], isNotNull);
      }

      await tester.tap(find.text('橡皮擦'));
      await tester.pump();

      final TestGesture eraseGesture = await tester.startGesture(lineStart);
      await eraseGesture.moveBy(lineEnd - lineStart);
      await eraseGesture.up();
      await tester.pump();

      pixels = canvasPixels();
      for (int x = 4; x <= 20; x++) {
        expect(pixels[12][x], isNull);
      }

      await tester.tap(find.text('清空畫布'));
      await tester.pumpAndSettle();

      expect(find.text('目前的像素圖會被清空。你仍可用「復原」找回上一個版本。'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
