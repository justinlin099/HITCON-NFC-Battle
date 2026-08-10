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

    expect(find.text('SHOWN'), findsNothing);
    expect(find.text('PRIZE'), findsNothing);
    expect(find.text('TOP'), findsNothing);
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
    expect(
      find.byKey(const ValueKey<String>('achievement-complete-helloWorld')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('achievement-complete-nfcOnline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('achievement-complete-sponsorScout')),
      findsNothing,
    );

    final Finder helloWorldBadge = find.byKey(
      const ValueKey<String>('scoreboard-achievement-helloWorld'),
    );
    final Rect helloWorldImageRect = tester.getRect(
      find.descendant(of: helloWorldBadge, matching: find.byType(Hero)),
    );
    final Rect helloWorldTrophyRect = tester.getRect(
      find.byKey(const ValueKey<String>('achievement-complete-helloWorld')),
    );
    expect(
      helloWorldImageRect.bottom - helloWorldTrophyRect.bottom,
      closeTo(8, 0.01),
    );

    final Finder sponsorBadge = find.byKey(
      const ValueKey<String>('scoreboard-achievement-sponsorScout'),
    );
    final Rect sponsorImageRect = tester.getRect(
      find.descendant(of: sponsorBadge, matching: find.byType(Hero)),
    );
    final Rect sponsorLevelRect = tester.getRect(
      find.byKey(const ValueKey<String>('achievement-level-sponsorScout')),
    );
    expect(
      sponsorImageRect.bottom - sponsorLevelRect.bottom,
      closeTo(10, 0.01),
    );

    await tester.tap(helloWorldBadge);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('achievement-detail-dialog')), findsOneWidget);
    expect(find.text('HOW TO UNLOCK'), findsOneWidget);
    expect(
      find.text('Complete your display name, pixel avatar, and bio.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('achievement-detail-share')), findsOneWidget);
    await tester.tap(find.byKey(const Key('achievement-detail-share')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('social-share-dialog')), findsOneWidget);
    expect(find.text('Unlocked HELLO, WORLD!'), findsOneWidget);
    expect(find.text('#HITCON  #NFCBATTLE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('social-share-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('social-share-dialog')), findsNothing);
    expect(find.byKey(const Key('achievement-detail-dialog')), findsOneWidget);

    final Finder holographicBadge = find.byKey(
      const Key('achievement-holographic-badge'),
    );
    final Finder badgeTransform = find.byKey(
      const Key('achievement-badge-transform'),
    );
    expect(holographicBadge, findsOneWidget);
    expect(
      find.byKey(const Key('achievement-holographic-foil')),
      findsOneWidget,
    );
    expect(tester.getSize(holographicBadge).width, greaterThan(180));

    final List<double> restingTransform = List<double>.of(
      tester.widget<Transform>(badgeTransform).transform.storage,
    );
    final TestGesture tiltGesture = await tester.startGesture(
      tester.getCenter(holographicBadge),
    );
    await tiltGesture.moveBy(const Offset(48, -32));
    await tester.pump();
    final List<double> tiltedTransform = List<double>.of(
      tester.widget<Transform>(badgeTransform).transform.storage,
    );
    expect(tiltedTransform, isNot(equals(restingTransform)));
    await tiltGesture.up();
    await tester.pumpAndSettle();
    final List<double> returnedTransform = List<double>.of(
      tester.widget<Transform>(badgeTransform).transform.storage,
    );
    expect(returnedTransform, equals(restingTransform));

    await tester.tap(find.byKey(const Key('achievement-detail-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('achievement-detail-dialog')), findsNothing);

    final Finder achievementScroller = find.descendant(
      of: find.byKey(const Key('scoreboard-achievements')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      sponsorBadge,
      160,
      scrollable: achievementScroller,
    );
    await tester.tap(sponsorBadge);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Sponsor-stamp requirements by level:\n'
        'Level I: total sponsor stamps required — 1\n'
        'Level II: total sponsor stamps required — 5\n'
        'Level III: total sponsor stamps required — 10',
      ),
      findsOneWidget,
    );
    final Finder detailClose = find.byKey(
      const Key('achievement-detail-close'),
    );
    await tester.ensureVisible(detailClose);
    await tester.pumpAndSettle();
    await tester.tap(detailClose);
    await tester.pumpAndSettle();

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
