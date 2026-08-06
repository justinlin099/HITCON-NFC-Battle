class ScoreboardEntry {
  const ScoreboardEntry({
    required this.userId,
    required this.displayName,
    required this.score,
    required this.rank,
    required this.emojiIcon,
  });

  final String userId;
  final String displayName;
  final int score;
  final int rank;
  final String emojiIcon;

  static ScoreboardEntry? tryParse(Object? raw, {String fallbackUserId = ''}) {
    final Map<String, dynamic>? item = _stringMap(raw);
    if (item == null) {
      return null;
    }

    final String userId = (item['user_id'] ?? item['id'] ?? fallbackUserId)
        .toString()
        .trim();
    final String displayName = (item['display_name'] ?? item['name'] ?? userId)
        .toString()
        .trim();
    final int rank = _intValue(item['rank'] ?? item['position']);
    final int score = _intValue(item['score'] ?? item['points']);
    final String emojiIcon = (item['emoji_icon'] ?? item['emoji'] ?? '')
        .toString();

    if (userId.isEmpty && displayName.isEmpty && rank <= 0 && score == 0) {
      return null;
    }

    return ScoreboardEntry(
      userId: userId,
      displayName: displayName,
      score: score,
      rank: rank,
      emojiIcon: emojiIcon,
    );
  }

  static ScoreboardEntry? fromMyRankPayload(
    Map<String, dynamic> payload, {
    String fallbackUserId = '',
  }) {
    Object selected = payload;
    for (final String key in <String>['ranking', 'entry', 'me', 'player']) {
      final Object? candidate = payload[key];
      if (_stringMap(candidate) != null) {
        selected = candidate!;
        break;
      }
    }
    return tryParse(selected, fallbackUserId: fallbackUserId);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'user_id': userId,
      'display_name': displayName,
      'score': score,
      'rank': rank,
      'emoji_icon': emojiIcon,
    };
  }
}

class ScoreboardPageData {
  const ScoreboardPageData({
    required this.entries,
    required this.rankThreshold,
    required this.frozen,
    required this.offset,
    required this.limit,
    required this.totalCount,
    required this.hasMore,
  });

  final List<ScoreboardEntry> entries;
  final int rankThreshold;
  final bool frozen;
  final int offset;
  final int limit;
  final int? totalCount;
  final bool hasMore;

  factory ScoreboardPageData.fromJson(
    Map<String, dynamic> json, {
    required int requestedOffset,
    required int requestedLimit,
  }) {
    final Map<String, dynamic> pagination =
        _stringMap(json['pagination']) ?? <String, dynamic>{};
    final Object? rawEntries =
        json['rankings'] ?? json['entries'] ?? json['items'];
    final List<ScoreboardEntry> entries = rawEntries is List
        ? rawEntries
              .map(ScoreboardEntry.tryParse)
              .whereType<ScoreboardEntry>()
              .toList(growable: false)
        : <ScoreboardEntry>[];
    final int offset = _intValue(
      json['offset'] ?? pagination['offset'],
      fallback: requestedOffset,
    );
    final int limit = _intValue(
      json['limit'] ?? pagination['limit'],
      fallback: requestedLimit,
    );
    final int? totalCount = _nullableIntValue(
      json['total_count'] ??
          json['total'] ??
          pagination['total_count'] ??
          pagination['total'],
    );
    final int? nextOffset = _nullableIntValue(
      json['next_offset'] ?? pagination['next_offset'],
    );
    final bool? explicitHasMore = _boolValue(
      json['has_more'] ?? pagination['has_more'],
    );
    final bool hasMore =
        explicitHasMore ??
        (nextOffset != null
            ? nextOffset > offset
            : totalCount != null
            ? offset + entries.length < totalCount
            : entries.length >= limit && limit > 0);
    final String state = (json['state'] ?? '').toString().toUpperCase();

    return ScoreboardPageData(
      entries: entries,
      rankThreshold: _intValue(json['rank_threshold']),
      frozen: _boolValue(json['frozen']) ?? state == 'FROZEN',
      offset: offset,
      limit: limit <= 0 ? requestedLimit : limit,
      totalCount: totalCount,
      hasMore: hasMore,
    );
  }
}

List<ScoreboardEntry> mergeScoreboardPageWithCurrentUser(
  List<ScoreboardEntry> page,
  ScoreboardEntry? currentUser,
) {
  final List<ScoreboardEntry> result = List<ScoreboardEntry>.of(page);
  if (currentUser == null || currentUser.rank <= 0) {
    return result;
  }
  if (result.any((ScoreboardEntry entry) {
    return scoreboardEntriesIdentifySameUser(entry, currentUser);
  })) {
    return result;
  }

  final int insertionIndex = result.indexWhere(
    (ScoreboardEntry entry) => entry.rank > currentUser.rank,
  );
  if (insertionIndex < 0) {
    result.add(currentUser);
  } else {
    result.insert(insertionIndex, currentUser);
  }
  return result;
}

bool scoreboardEntriesIdentifySameUser(
  ScoreboardEntry entry,
  ScoreboardEntry currentUser,
) {
  if (entry.userId.isNotEmpty && currentUser.userId.isNotEmpty) {
    return entry.userId == currentUser.userId;
  }
  return entry.rank > 0 && entry.rank == currentUser.rank;
}

int scoreboardPageOffsetForRank(int rank, int pageSize) {
  if (rank <= 0 || pageSize <= 0) {
    return 0;
  }
  return ((rank - 1) ~/ pageSize) * pageSize;
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? value) =>
          MapEntry<String, dynamic>(key.toString(), value),
    );
  }
  return null;
}

int _intValue(Object? value, {int fallback = 0}) {
  return _nullableIntValue(value) ?? fallback;
}

int? _nullableIntValue(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  return switch (value?.toString().toLowerCase()) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => null,
  };
}
