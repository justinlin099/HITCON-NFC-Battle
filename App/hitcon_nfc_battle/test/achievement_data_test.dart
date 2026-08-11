import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:hitcon_nfc_battle/config/achievement_config.dart';
import 'package:hitcon_nfc_battle/l10n/strings_en.dart';
import 'package:hitcon_nfc_battle/l10n/strings_zh_tw.dart';
import 'package:hitcon_nfc_battle/services/achievement_data.dart';

void main() {
  test('every achievement has localized unlock requirements', () {
    for (final AchievementKind kind in AchievementKind.values) {
      expect(appStringsEn, contains(kind.requirementKey));
      expect(appStringsZhTw, contains(kind.requirementKey));
    }
  });

  test('Taiwan localization uses consistent Taiwan terminology', () {
    const Map<String, String> replacements = <String, String>{
      '頭像': '大頭貼',
      '保存': '儲存',
      '密鑰': '金鑰',
      '點擊': '點一下',
      '重置': '重設',
      '剪裁': '裁剪',
      '卡牌': '卡片',
      '清空': '清除',
    };
    for (final String oldTerm in replacements.keys) {
      expect(
        appStringsZhTw.values.where((String value) => value.contains(oldTerm)),
        isEmpty,
        reason: '請將「$oldTerm」改為「${replacements[oldTerm]}」',
      );
    }
    expect(
      appStringsZhTw['achievementRequirementHelloWorld'],
      contains('像素大頭貼'),
    );
  });

  test('tier requirements explain every level with an explicit unit', () {
    const List<String> tierKeys = <String>[
      'achievementTierPlayerCards',
      'achievementTierSponsorStamps',
      'achievementTierCommunityStamps',
      'achievementTierRanking',
    ];
    for (final String key in tierKeys) {
      expect(appStringsEn[key], contains('{level}'));
      expect(appStringsEn[key], contains('{target}'));
      expect(appStringsZhTw[key], contains('等級 {level}'));
      expect(appStringsZhTw[key], contains('{target}'));
    }
    expect(
      appStringsZhTw['achievementRequirementSponsorScout'],
      isNot(contains('等級門檻')),
    );
  });

  test('every displayed achievement badge has a transparent exterior', () {
    for (final AchievementKind kind in AchievementKind.values) {
      final img.Image? badge = img.decodePng(
        File(kind.assetPath).readAsBytesSync(),
      );
      expect(badge, isNotNull, reason: kind.assetPath);

      final img.Image decoded = badge!;
      expect(decoded.numChannels, 4, reason: kind.assetPath);
      expect(decoded.getPixel(0, 0).a, 0, reason: kind.assetPath);
      expect(
        decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).a,
        255,
        reason: kind.assetPath,
      );
    }
  });

  test('evaluates every achievement from the available app data', () {
    final List<AchievementBadgeProgress> achievements = evaluateAchievements(
      AchievementSnapshot(
        profile: <String, dynamic>{
          'display_name': 'Alice',
          'pixel_avatar_base64': 'avatar',
          'bio': 'Hello',
          'physical_id': '04:A1',
          'collection': List<String>.generate(26, (int index) => 'u$index'),
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
        phishingCount: 2,
        externalPrizeClaimed: true,
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

  test('ignores obsolete profile guesses for API-backed achievements', () {
    final List<AchievementBadgeProgress> achievements = evaluateAchievements(
      const AchievementSnapshot(
        profile: <String, dynamic>{
          'phishing_count': 2,
          'solder_master': true,
          'solder_completed': true,
          'solder_count': 1,
        },
      ),
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

  test('valid false API values keep phishing and solder badges locked', () {
    final List<AchievementBadgeProgress> achievements = evaluateAchievements(
      const AchievementSnapshot(phishingCount: 0, externalPrizeClaimed: false),
    );

    AchievementBadgeProgress badge(AchievementKind kind) => achievements
        .singleWhere((AchievementBadgeProgress item) => item.kind == kind);

    expect(badge(AchievementKind.phishing).dataAvailable, isTrue);
    expect(badge(AchievementKind.phishing).isUnlocked, isFalse);
    expect(badge(AchievementKind.solderMaster).dataAvailable, isTrue);
    expect(badge(AchievementKind.solderMaster).isUnlocked, isFalse);
  });

  test('roman level labels support every allowed remote tier', () {
    expect(achievementRomanLevel(1), 'I');
    expect(achievementRomanLevel(3), 'III');
    expect(achievementRomanLevel(10), 'X');
  });
}
