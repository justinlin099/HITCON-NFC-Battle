import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/config/achievement_config.dart';
import 'package:hitcon_nfc_battle/services/achievement_data.dart';

void main() {
  test('evaluates every achievement from the available app data', () {
    final List<AchievementBadgeProgress> achievements = evaluateAchievements(
      AchievementSnapshot(
        profile: <String, dynamic>{
          'display_name': 'Alice',
          'pixel_avatar_base64': 'avatar',
          'bio': 'Hello',
          'physical_id': '04:A1',
          'collection': List<String>.generate(26, (int index) => 'u$index'),
          'phishing_count': 2,
          'solder_master': true,
        },
        collectionCards: const <Map<String, dynamic>>[
          <String, dynamic>{'role': 'ATTENDEE'},
          <String, dynamic>{'role': 'STAFF'},
          <String, dynamic>{'role': 'SPONSOR'},
          <String, dynamic>{'role': 'COMMUNITY'},
        ],
        stampMission: const <String, dynamic>{
          'sponsor_count': 5,
          'community_count': 10,
          'eligible_for_stamp_prize': true,
        },
        prizeResult: const <String, dynamic>{'rank_prize': true},
        rank: 7,
        scoreboardFrozen: true,
        remoteRules: AchievementRules(
          sponsorScout: AchievementRule(
            enabled: true,
            thresholds: <int>[1, 5, 10],
          ),
          communityExplorer: AchievementRule(
            enabled: true,
            thresholds: <int>[1, 5, 10],
          ),
        ),
      ),
    );

    AchievementBadgeProgress badge(AchievementKind kind) => achievements
        .singleWhere((AchievementBadgeProgress item) => item.kind == kind);

    expect(achievements, hasLength(12));
    expect(badge(AchievementKind.helloWorld).isUnlocked, isTrue);
    expect(badge(AchievementKind.nfcOnline).isUnlocked, isTrue);
    expect(badge(AchievementKind.firstContact).isUnlocked, isTrue);
    expect(badge(AchievementKind.packetCollector).unlockedLevel, 2);
    expect(badge(AchievementKind.packetCollector).nextLevel, 3);
    expect(badge(AchievementKind.packetCollector).activeTarget, 50);
    expect(badge(AchievementKind.sponsorScout).unlockedLevel, 2);
    expect(badge(AchievementKind.sponsorScout).nextLevel, 3);
    expect(badge(AchievementKind.communityExplorer).isMaxLevel, isTrue);
    expect(badge(AchievementKind.fullStackSocial).isUnlocked, isTrue);
    expect(badge(AchievementKind.stampMaster).isUnlocked, isTrue);
    expect(badge(AchievementKind.topRank).unlockedLevel, 2);
    expect(badge(AchievementKind.topRank).nextLevel, 3);
    expect(badge(AchievementKind.topRank).activeTarget, 1);
    expect(badge(AchievementKind.prizeUnlocked).isUnlocked, isTrue);
    expect(badge(AchievementKind.phishing).isUnlocked, isTrue);
    expect(badge(AchievementKind.solderMaster).isUnlocked, isTrue);
  });

  test('tiered badge advances one card from I to II to III', () {
    AchievementBadgeProgress progress(int current) => AchievementBadgeProgress(
      kind: AchievementKind.packetCollector,
      current: current,
      thresholds: const <int>[10, 25, 50],
    );

    expect(progress(0).displayedLevel, 1);
    expect(progress(0).nextLevel, 1);
    expect(progress(10).displayedLevel, 1);
    expect(progress(10).nextLevel, 2);
    expect(progress(25).displayedLevel, 2);
    expect(progress(25).nextLevel, 3);
    expect(progress(50).displayedLevel, 3);
    expect(progress(50).nextLevel, isNull);
    expect(progress(50).isMaxLevel, isTrue);
  });

  test('missing optional backend fields stay unavailable without throwing', () {
    final List<AchievementBadgeProgress> achievements = evaluateAchievements(
      const AchievementSnapshot(profile: <String, dynamic>{}),
    );

    AchievementBadgeProgress badge(AchievementKind kind) => achievements
        .singleWhere((AchievementBadgeProgress item) => item.kind == kind);

    expect(badge(AchievementKind.phishing).dataAvailable, isFalse);
    expect(badge(AchievementKind.phishing).isUnlocked, isFalse);
    expect(badge(AchievementKind.solderMaster).dataAvailable, isFalse);
    expect(badge(AchievementKind.solderMaster).isUnlocked, isFalse);
    expect(
      achievements.where(
        (AchievementBadgeProgress item) =>
            item.kind == AchievementKind.sponsorScout ||
            item.kind == AchievementKind.communityExplorer,
      ),
      isEmpty,
    );
  });

  test('roman level labels support every allowed remote tier', () {
    expect(achievementRomanLevel(1), 'I');
    expect(achievementRomanLevel(3), 'III');
    expect(achievementRomanLevel(10), 'X');
  });
}
