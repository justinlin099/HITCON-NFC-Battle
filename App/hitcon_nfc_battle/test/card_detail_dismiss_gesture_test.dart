import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/card_detail_page.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  testWidgets('swiping the enlarged card down closes it', (
    WidgetTester tester,
  ) async {
    await _openCard(tester);

    await tester.fling(
      find.byKey(const Key('card-detail-tiltable-card')),
      const Offset(0, 420),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailPage), findsNothing);
  });

  testWidgets('swiping the enlarged card up keeps it open', (
    WidgetTester tester,
  ) async {
    await _openCard(tester);

    await tester.fling(
      find.byKey(const Key('card-detail-tiltable-card')),
      const Offset(0, -420),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailPage), findsOneWidget);
  });
}

Future<void> _openCard(WidgetTester tester) async {
  PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
  late BuildContext homeContext;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) {
          homeContext = context;
          return const SizedBox.expand();
        },
      ),
    ),
  );

  Navigator.of(homeContext).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => const CardDetailPage(
        heroTag: 'dismiss-test-card',
        title: 'TEST CARD',
        attributeEmoji: '🧪',
        attributeLabel: 'TEST',
        link: '',
        description: '',
        uid: '',
        collectedAt: '',
        cardColor: Color(0xFF006C45),
        showCollectionInfo: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
