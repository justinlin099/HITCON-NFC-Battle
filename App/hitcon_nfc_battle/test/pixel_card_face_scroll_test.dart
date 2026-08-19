import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/pages/user/my_card_editor_page.dart';
import 'package:hitcon_nfc_battle/pages/user/panasonic_support_mark.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_card_face.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  test('print artwork uses the compact four-percent corner radius', () {
    expect(printArtworkCornerRadiusFraction, 0.04);
    expect(printArtworkCornerRadius(638), closeTo(25.52, 0.001));
  });

  testWidgets('app and print Panasonic flags are independent', (
    WidgetTester tester,
  ) async {
    AppConfig.applyRemoteShowPanasonicLogo(false);
    AppConfig.applyRemoteShowPanasonicLogoOnPrint(true);
    addTearDown(AppConfig.resetApiBaseUrlForTesting);

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            PanasonicBrandingBuilder(
              builder: (_, bool visible) => Text('app:$visible'),
            ),
            PanasonicBrandingBuilder(
              forPrint: true,
              builder: (_, bool visible) => Text('print:$visible'),
            ),
          ],
        ),
      ),
    );

    expect(find.text('app:false'), findsOneWidget);
    expect(find.text('print:true'), findsOneWidget);
  });

  testWidgets('preview card clips extra content instead of scrolling it', (
    WidgetTester tester,
  ) async {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 507,
            child: PixelCardFace(
              title: 'Preview',
              attributeEmoji: '',
              attributeLabel: 'CARD',
              cardColor: const Color(0xFF7A233D),
              showText: true,
              extraContentScrollable: false,
              image: const ColoredBox(color: Colors.black),
              extraContent: const Text(
                'A long description that must stay fixed inside the preview. '
                'It is clipped when it exceeds the available card area.',
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('card-extra-content-static')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PixelCardFace),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('print preview is rendered at twice the CR80 resolution', (
    WidgetTester tester,
  ) async {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    final GlobalKey artworkKey = GlobalKey();
    const double previewWidth = 320;
    const double previewHeight = previewWidth * 1011 / 638;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: artworkKey,
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
              child: PixelCardFace(
                title: 'Print preview',
                attributeEmoji: '',
                attributeLabel: '🙂 SMILE  🐣 CHICK  🐥 CHICK',
                cardColor: const Color(0xFF7A233D),
                showText: true,
                showOuterFrame: false,
                showDropShadow: false,
                verticalHitconWatermark: true,
                watermarkFooterHeight: 24,
                contentAboveWatermarks: true,
                extraContentBottomPadding: 0,
                titleFontSize: 22,
                attributeFontSize: 12,
                titleMaxLines: 1,
                imageToTitleSpacing: 8,
                extraContentSpacing: 8,
                extraContentScrollable: false,
                image: const ColoredBox(color: Colors.black),
                fixedContent: const Text(
                  'https://hitcon.org',
                  style: TextStyle(fontSize: 10),
                ),
                extraContent: const Text(
                  'This description is long enough to occupy all three lines '
                  'available in the printable card preview without scrolling.',
                  key: ValueKey<String>('three-line-print-description'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontFamily: 'Unifont',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderRepaintBoundary boundary =
        artworkKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(
      pixelRatio: printArtworkPixelRatio(previewWidth),
    );
    addTearDown(image.dispose);

    expect(printArtworkResolutionMultiplier, 2);
    expect(image.width, 1276);
    expect(image.height, 2022);
    final Stack cardStack = tester
        .widgetList<Stack>(
          find.descendant(
            of: find.byType(PixelCardFace),
            matching: find.byType(Stack),
          ),
        )
        .first;
    expect(cardStack.children.last, isA<Padding>());
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('three-line-print-description')),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
    final Text description = tester.widget<Text>(
      find.byKey(const ValueKey<String>('three-line-print-description')),
    );
    expect(description.maxLines, 3);
    expect(description.overflow, TextOverflow.ellipsis);
    final Rect descriptionRect = tester.getRect(
      find.byKey(const ValueKey<String>('three-line-print-description')),
    );
    final Rect viewportRect = tester.getRect(
      find.byKey(const ValueKey<String>('card-extra-content-static')),
    );
    expect(descriptionRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
  });
}
