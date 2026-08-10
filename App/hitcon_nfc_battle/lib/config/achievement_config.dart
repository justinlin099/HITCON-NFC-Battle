import 'package:flutter/foundation.dart';

@immutable
class AchievementRule {
  AchievementRule({required this.enabled, required Iterable<int> thresholds})
    : thresholds = List<int>.unmodifiable(thresholds);

  const AchievementRule.disabled()
    : enabled = false,
      thresholds = const <int>[];

  final bool enabled;
  final List<int> thresholds;

  bool get isVisible => enabled && thresholds.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'thresholds': thresholds,
  };
}

@immutable
class AchievementRules {
  const AchievementRules({
    required this.sponsorScout,
    required this.communityExplorer,
  });

  final AchievementRule sponsorScout;
  final AchievementRule communityExplorer;

  bool get hasVisibleRules =>
      sponsorScout.isVisible || communityExplorer.isVisible;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sponsor_scout': sponsorScout.toJson(),
    'community_explorer': communityExplorer.toJson(),
  };
}
