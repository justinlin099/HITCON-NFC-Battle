import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/widgets/admin_mode_switch_button.dart';

void main() {
  testWidgets('admin mode switch opens the gameplay route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routes: <String, WidgetBuilder>{
          '/collection': (BuildContext context) {
            final Object? arguments = ModalRoute.of(
              context,
            )?.settings.arguments;
            final bool fromAdmin =
                arguments is Map && arguments['fromAdminMode'] == true;
            return Scaffold(
              body: Text(fromAdmin ? 'ADMIN GAMEPLAY' : 'GAMEPLAY'),
            );
          },
        },
        home: Scaffold(
          appBar: AppBar(
            leading: const AdminModeSwitchButton(
              target: AdminModeTarget.gameplay,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AdminModeSwitchButton));
    await tester.pumpAndSettle();

    expect(find.text('ADMIN GAMEPLAY'), findsOneWidget);
  });
}
