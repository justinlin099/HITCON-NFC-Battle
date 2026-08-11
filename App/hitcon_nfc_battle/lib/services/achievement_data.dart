import '../config/achievement_config.dart';

enum AchievementKind {
  helloWorld,
  nfcOnline,
  firstContact,
  packetCollector,
  sponsorScout,
  communityExplorer,
  fullStackSocial,
  stampMaster,
  topRank,
  prizeUnlocked,
  phishing,
  solderMaster,
}

enum AchievementProgressDirection { increasing, rank }

extension AchievementKindPresentation on AchievementKind {
  bool get isHiddenUntilUnlocked => this == AchievementKind.phishing;

  String get titleKey => switch (this) {
    AchievementKind.helloWorld => 'achievementHelloWorld',
    AchievementKind.nfcOnline => 'achievementNfcOnline',
    AchievementKind.firstContact => 'achievementFirstContact',
    AchievementKind.packetCollector => 'achievementPacketCollector',
    AchievementKind.sponsorScout => 'sponsorScout',
    AchievementKind.communityExplorer => 'communityExplorer',
    AchievementKind.fullStackSocial => 'achievementFullStackSocial',
    AchievementKind.stampMaster => 'achievementStampMaster',
    AchievementKind.topRank => 'achievementTopRank',
    AchievementKind.prizeUnlocked => 'achievementPrizeUnlocked',
    AchievementKind.phishing => 'achievementPhishing',
    AchievementKind.solderMaster => 'achievementSolderMaster',
  };

  String get requirementKey => switch (this) {
    AchievementKind.helloWorld => 'achievementRequirementHelloWorld',
    AchievementKind.nfcOnline => 'achievementRequirementNfcOnline',
    AchievementKind.firstContact => 'achievementRequirementFirstContact',
    AchievementKind.packetCollector => 'achievementRequirementPacketCollector',
    AchievementKind.sponsorScout => 'achievementRequirementSponsorScout',
    AchievementKind.communityExplorer =>
      'achievementRequirementCommunityExplorer',
    AchievementKind.fullStackSocial => 'achievementRequirementFullStackSocial',
    AchievementKind.stampMaster => 'achievementRequirementStampMaster',
    AchievementKind.topRank => 'achievementRequirementTopRank',
    AchievementKind.prizeUnlocked => 'achievementRequirementPrizeUnlocked',
    AchievementKind.phishing => 'achievementRequirementPhishing',
    AchievementKind.solderMaster => 'achievementRequirementSolderMaster',
  };

  String get assetPath => switch (this) {
    AchievementKind.helloWorld =>
      'assets/images/achievement_badges/hello_world_avatar_style_v1.png',
    AchievementKind.nfcOnline =>
      'assets/images/achievement_badges/nfc_online_avatar_style_v1.png',
    AchievementKind.firstContact =>
      'assets/images/achievement_badges/first_contact_avatar_style_v1.png',
    AchievementKind.packetCollector =>
      'assets/images/achievement_badges/packet_collector_avatar_style_v1.png',
    AchievementKind.sponsorScout =>
      'assets/images/achievement_badges/sponsor_scout_avatar_style_v1.png',
    AchievementKind.communityExplorer =>
      'assets/images/achievement_badges/community_explorer_avatar_style_v1.png',
    AchievementKind.fullStackSocial =>
      'assets/images/achievement_badges/full_stack_social_avatar_style_v1.png',
    AchievementKind.stampMaster =>
      'assets/images/achievement_badges/stamp_master_avatar_style_v1.png',
    AchievementKind.topRank =>
      'assets/images/achievement_badges/top_rank_avatar_style_v1.png',
    AchievementKind.prizeUnlocked =>
      'assets/images/achievement_badges/prize_unlocked_avatar_style_v1.png',
    AchievementKind.phishing =>
      'assets/images/achievement_badges/phishing_avatar_style_v1.png',
    AchievementKind.solderMaster =>
      'assets/images/achievement_badges/solder_master_avatar_style_v1.png',
  };
}

class AchievementBadgeProgress {
  AchievementBadgeProgress({
    required this.kind,
    required this.current,
    required Iterable<int> thresholds,
    this.dataAvailable = true,
    this.direction = AchievementProgressDirection.increasing,
  }) : thresholds = List<int>.unmodifiable(thresholds);

  final AchievementKind kind;
  final int current;
  final List<int> thresholds;
  final bool dataAvailable;
  final AchievementProgressDirection direction;

  int get levelCount => thresholds.length;

  int get unlockedLevel {
    if (!dataAvailable) {
      return 0;
    }
    return thresholds.where(_meetsThreshold).length;
  }

  bool get isUnlocked => unlockedLevel > 0;
  bool get isTiered => levelCount > 1;
  bool get isMaxLevel => levelCount > 0 && unlockedLevel >= levelCount;

  int get displayedLevel {
    if (levelCount == 0) {
      return 0;
    }
    return unlockedLevel == 0 ? 1 : unlockedLevel;
  }

  int? get nextLevel {
    if (levelCount == 0 || isMaxLevel) {
      return null;
    }
    return unlockedLevel + 1;
  }

  int? get activeTarget {
    if (thresholds.isEmpty) {
      return null;
    }
    if (isMaxLevel) {
      return thresholds.last;
    }
    return thresholds[unlockedLevel];
  }

  bool _meetsThreshold(int threshold) {
    return switch (direction) {
      AchievementProgressDirection.increasing => current >= threshold,
      AchievementProgressDirection.rank => current > 0 && current <= threshold,
    };
  }
}

class AchievementSnapshot {
  const AchievementSnapshot({
    this.profile,
    this.collectionCards,
    this.stampMission,
    this.prizeResult,
    this.rank,
    this.phishingCount,
    this.externalPrizeClaimed,
    this.scoreboardFrozen = false,
    this.remoteRules,
  });

  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>>? collectionCards;
  final Map<String, dynamic>? stampMission;
  final Map<String, dynamic>? prizeResult;
  final int? rank;
  final int? phishingCount;
  final bool? externalPrizeClaimed;
  final bool scoreboardFrozen;
  final AchievementRules? remoteRules;
}

List<AchievementBadgeProgress> evaluateAchievements(
  AchievementSnapshot snapshot,
) {
  final Map<String, dynamic>? profile = snapshot.profile;
  final List<Map<String, dynamic>>? cards = snapshot.collectionCards;
  final Map<String, dynamic>? mission = snapshot.stampMission;
  final Map<String, dynamic>? prize = snapshot.prizeResult;
  final int? collectionCount = _collectionCount(profile, cards);
  final int completedProfileFields = profile == null
      ? 0
      : <bool>[
          _nonEmpty(profile['display_name']),
          _nonEmpty(profile['pixel_avatar_base64']),
          _nonEmpty(profile['bio']),
        ].where((bool complete) => complete).length;
  final Set<String> roles = cards == null
      ? <String>{}
      : cards.map(_cardRole).where((String role) => role.isNotEmpty).toSet();
  final int socialRoleCount = <String>{
    'ATTENDEE',
    'STAFF',
    'SPONSOR',
    'COMMUNITY',
  }.where(roles.contains).length;
  final int? phishingCount = snapshot.phishingCount;
  final bool? solderCompleted = snapshot.externalPrizeClaimed;
  final bool prizeUnlocked =
      mission?['eligible_for_stamp_prize'] == true ||
      prize?['stamp_prize'] == true ||
      prize?['rank_prize'] == true;
  final bool prizeDataAvailable =
      mission?.containsKey('eligible_for_stamp_prize') == true ||
      prize?.containsKey('stamp_prize') == true ||
      prize?.containsKey('rank_prize') == true;

  final List<AchievementBadgeProgress> result = <AchievementBadgeProgress>[
    AchievementBadgeProgress(
      kind: AchievementKind.helloWorld,
      current: completedProfileFields,
      thresholds: const <int>[3],
      dataAvailable: profile != null,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.nfcOnline,
      current: _nonEmpty(profile?['physical_id'] ?? profile?['paired_ntag_uid'])
          ? 1
          : 0,
      thresholds: const <int>[1],
      dataAvailable: profile != null,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.firstContact,
      current: collectionCount ?? 0,
      thresholds: const <int>[1],
      dataAvailable: collectionCount != null,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.packetCollector,
      current: collectionCount ?? 0,
      thresholds: const <int>[10, 25, 50],
      dataAvailable: collectionCount != null,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.fullStackSocial,
      current: socialRoleCount,
      thresholds: const <int>[4],
      dataAvailable: cards != null,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.stampMaster,
      current: mission?['eligible_for_stamp_prize'] == true ? 1 : 0,
      thresholds: const <int>[1],
      dataAvailable: mission?.containsKey('eligible_for_stamp_prize') == true,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.topRank,
      current: snapshot.rank ?? 0,
      thresholds: const <int>[100, 10, 1],
      direction: AchievementProgressDirection.rank,
      dataAvailable:
          snapshot.scoreboardFrozen &&
          snapshot.rank != null &&
          snapshot.rank! > 0,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.prizeUnlocked,
      current: prizeUnlocked ? 1 : 0,
      thresholds: const <int>[1],
      dataAvailable: prizeDataAvailable,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.phishing,
      current: phishingCount ?? 0,
      thresholds: const <int>[1],
      dataAvailable: phishingCount != null,
    ),
    AchievementBadgeProgress(
      kind: AchievementKind.solderMaster,
      current: solderCompleted == true ? 1 : 0,
      thresholds: const <int>[1],
      dataAvailable: solderCompleted != null,
    ),
  ];

  final AchievementRule? sponsorRule = snapshot.remoteRules?.sponsorScout;
  if (sponsorRule?.isVisible == true) {
    result.insert(
      4,
      AchievementBadgeProgress(
        kind: AchievementKind.sponsorScout,
        current: _strictNonNegativeInt(mission?['sponsor_count']) ?? 0,
        thresholds: sponsorRule!.thresholds,
        dataAvailable: mission?.containsKey('sponsor_count') == true,
      ),
    );
  }
  final AchievementRule? communityRule =
      snapshot.remoteRules?.communityExplorer;
  if (communityRule?.isVisible == true) {
    result.insert(
      sponsorRule?.isVisible == true ? 5 : 4,
      AchievementBadgeProgress(
        kind: AchievementKind.communityExplorer,
        current: _strictNonNegativeInt(mission?['community_count']) ?? 0,
        thresholds: communityRule!.thresholds,
        dataAvailable: mission?.containsKey('community_count') == true,
      ),
    );
  }

  return List<AchievementBadgeProgress>.unmodifiable(result);
}

int? _collectionCount(
  Map<String, dynamic>? profile,
  List<Map<String, dynamic>>? cards,
) {
  final Object? rawCollection = profile?['collection'];
  if (rawCollection is List) {
    return rawCollection.length;
  }
  return cards?.length;
}

String _cardRole(Map<String, dynamic> card) {
  final String role =
      (card['role'] ?? card['card_role'] ?? card['attribute_label'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
  return switch (role) {
    'USER' => 'ATTENDEE',
    'EVENT_STAFF' => 'STAFF',
    _ => role,
  };
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

int? _strictNonNegativeInt(Object? value) {
  if (value is! num || !value.isFinite || value < 0) {
    return null;
  }
  final int result = value.toInt();
  return value == result ? result : null;
}

String achievementRomanLevel(int level) {
  const List<String> levels = <String>[
    '',
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
  ];
  if (level > 0 && level < levels.length) {
    return levels[level];
  }
  return '$level';
}
