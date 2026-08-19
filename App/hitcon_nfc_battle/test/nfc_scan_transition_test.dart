import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/pages/user/nfc_scan_transition.dart';
import 'package:hitcon_nfc_battle/pages/user/pixel_theme.dart';

void main() {
  testWidgets('NFC scan transition changes phase and accepts drag input', (
    WidgetTester tester,
  ) async {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    await tester.pumpWidget(
      const MaterialApp(
        home: NfcScanTransition(
          phase: NfcScanTransitionPhase.detected,
          label: 'TAG SIGNAL DETECTED',
        ),
      ),
    );

    expect(find.text('TAG SIGNAL DETECTED'), findsOneWidget);

    await tester.drag(find.byType(NfcScanTransition), const Offset(80, -60));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const MaterialApp(
        home: NfcScanTransition(
          phase: NfcScanTransitionPhase.ready,
          label: 'CARD LOCKED',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('CARD LOCKED'), findsOneWidget);
    expect(find.text('TAG SIGNAL DETECTED'), findsNothing);
  });
}
