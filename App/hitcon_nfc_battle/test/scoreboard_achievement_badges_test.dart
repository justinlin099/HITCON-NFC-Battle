import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/config/achievement_config.dart';
import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/pages/user/score_board_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppConfig.resetApiBaseUrlForTesting();
  });

  tearDown(AppConfig.resetApiBaseUrlForTesting);

  testWidgets('shows one progressive card per achievement above scoreboard', (
    WidgetTester tester,
  ) async {
    AppConfig.applyRemoteAchievementRules(
      AchievementRules(
        sponsorScout: AchievementRule(
          enabled: true,
          thresholds: <int>[1, 5, 10],
        ),
        communityExplorer: AchievementRule(enabled: true, thresholds: <int>[1]),
      ),
    );

    await tester.pumpWidget(
      _localizedApp(
        child: const ScoreBoardPage(
          profile: <String, dynamic>{
            'display_name': 'Alice',
            'pixel_avatar_base64': 'avatar',
            'bio': 'Hello',
            'phishing_count': 0,
          },
          collectionCards: <Map<String, dynamic>>[],
          stampMission: <String, dynamic>{
            'sponsor_count': 5,
            'community_count': 0,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scoreboard-achievements')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('scoreboard-achievement-sponsorScout')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('scoreboard-achievement-communityExplorer'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('scoreboard-achievement-sponsorScout-2'),
      ),
      findsNothing,
    );
    expect(find.text('NEXT'), findsNothing);
    expect(find.textContaining('NEXT III'), findsOneWidget);
    expect(find.textContaining('5/10'), findsOneWidget);

    final Offset achievementsTop = tester.getTopLeft(
      find.byKey(const Key('scoreboard-achievements')),
    );
    final Offset scoreboardTop = tester.getTopLeft(find.text('SCORE BOARD'));
    expect(achievementsTop.dy, lessThan(scoreboardTop.dy));
  });

  testWidgets('keeps static achievements but hides remote-only badges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        child: const ScoreBoardPage(
          stampMission: <String, dynamic>{
            'sponsor_count': 99,
            'community_count': 99,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scoreboard-achievements')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('scoreboard-achievement-helloWorld')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('scoreboard-achievement-sponsorScout')),
      findsNothing,
    );
  });
}

Widget _localizedApp({required Widget child}) {
  return MaterialApp(
    locale: const Locale('en'),
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
