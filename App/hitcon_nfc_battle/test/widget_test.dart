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
  test('fill tolerance matches nearby RGB colors by channel distance', () {
    const Color target = Color(0xFF646464);

    expect(pixelColorsMatchWithinTolerance(target, target, 0), isTrue);
    expect(
      pixelColorsMatchWithinTolerance(const Color(0xFF7D7D7D), target, 10),
      isTrue,
    );
    expect(
      pixelColorsMatchWithinTolerance(const Color(0xFF7F6464), target, 10),
      isFalse,
    );
    expect(pixelColorsMatchWithinTolerance(null, null, 100), isTrue);
    expect(pixelColorsMatchWithinTolerance(target, null, 100), isFalse);
  });

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
      await tester.pumpAndSettle();

      Finder toolLabel(String text) => find.text(text, skipOffstage: false);
      Finder editorKey(String value) =>
          find.byKey(Key(value), skipOffstage: false);

      expect(toolLabel('匯入'), findsOneWidget);
      expect(toolLabel('清除'), findsOneWidget);
      expect(toolLabel('筆刷 ON'), findsOneWidget);
      expect(toolLabel('橡皮擦'), findsOneWidget);
      expect(toolLabel('填色'), findsOneWidget);
      expect(toolLabel('取色'), findsOneWidget);
      expect(toolLabel('復原'), findsOneWidget);
      expect(toolLabel('重做'), findsOneWidget);
      expect(toolLabel('網格開啟'), findsOneWidget);
      expect(toolLabel('縮小筆刷'), findsNothing);
      expect(toolLabel('放大筆刷'), findsNothing);

      const List<Key> orderedToolKeys = <Key>[
        Key('pixel-editor-tool-import'),
        Key('pixel-editor-tool-undo'),
        Key('pixel-editor-tool-redo'),
        Key('pixel-editor-tool-grid'),
        Key('pixel-editor-tool-brush'),
        Key('pixel-editor-tool-eraser'),
        Key('pixel-editor-tool-fill'),
        Key('pixel-editor-tool-picker'),
        Key('pixel-editor-tool-clear'),
      ];
      final List<Rect> orderedToolRects = orderedToolKeys
          .map(
            (Key key) => tester.getRect(find.byKey(key, skipOffstage: false)),
          )
          .toList(growable: false);
      for (int index = 1; index < orderedToolRects.length; index += 1) {
        expect(
          orderedToolRects[index].left,
          greaterThan(orderedToolRects[index - 1].left),
        );
      }
      for (final Rect rect in orderedToolRects) {
        expect(rect.height, 70);
        expect(rect.top, orderedToolRects.first.top);
      }

      await tester.tap(editorKey('pixel-editor-tool-clear'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('pixel-editor-clear-confirm-dialog')),
        findsOneWidget,
      );
      expect(find.text('確定要清除畫布嗎？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pixel-editor-clear-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('pixel-editor-clear-confirm-dialog')),
        findsNothing,
      );

      await tester.tap(editorKey('pixel-editor-tool-clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pixel-editor-clear-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('畫布已清除'), findsOneWidget);
      expect(find.textContaining('不支援的圖片格式'), findsNothing);

      await tester.tap(editorKey('pixel-editor-tool-fill'));
      await tester.pump();
      expect(find.textContaining('準備畫圖...'), findsOneWidget);
      expect(find.textContaining('區域已填色'), findsNothing);
      expect(
        find.byKey(const Key('pixel-editor-fill-tolerance-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pixel-editor-brush-size-control')),
        findsNothing,
      );
      final Finder fillToleranceSliderFinder = find.byKey(
        const Key('pixel-editor-fill-tolerance-slider'),
      );
      final Slider fillToleranceSlider = tester.widget<Slider>(
        fillToleranceSliderFinder,
      );
      expect(fillToleranceSlider.min, 0);
      expect(fillToleranceSlider.max, 100);
      expect(fillToleranceSlider.divisions, 20);
      fillToleranceSlider.onChanged?.call(35);
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('pixel-editor-fill-tolerance-value')),
            )
            .data,
        '填色容忍度：35%',
      );
      expect(find.textContaining('工具：填色 | 容忍度：35%'), findsOneWidget);
      await tester.tapAt(tester.getCenter(editorKey('pixel-editor-canvas')));
      await tester.pump();
      expect(find.textContaining('區域已填色'), findsOneWidget);
      expect(find.textContaining('畫布已清除'), findsNothing);
      await tester.tapAt(tester.getCenter(editorKey('pixel-editor-canvas')));
      await tester.pump();
      expect(find.textContaining('顏色相同，未變更'), findsOneWidget);
      expect(find.textContaining('區域已填色'), findsNothing);

      await tester.tap(editorKey('pixel-editor-tool-brush'));
      await tester.pump();
      expect(
        find.byKey(const Key('pixel-editor-fill-tolerance-control')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('pixel-editor-brush-size-control')),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('pixel-editor-color-scroll-right-hint')),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(430, 1200);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('pixel-editor-tool-scroll-right-hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pixel-editor-color-scroll-right-hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pixel-editor-tool-scroll-left-hint')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('pixel-editor-color-scroll-left-hint')),
        findsNothing,
      );
      await tester.drag(
        find.byKey(const Key('pixel-editor-tool-scroll-view')),
        const Offset(-220, 0),
      );
      await tester.drag(
        find.byKey(const Key('pixel-editor-color-scroll-view')),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('pixel-editor-tool-scroll-left-hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pixel-editor-color-scroll-left-hint')),
        findsOneWidget,
      );

      tester.view.physicalSize = const Size(800, 1200);
      await tester.pumpAndSettle();
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
