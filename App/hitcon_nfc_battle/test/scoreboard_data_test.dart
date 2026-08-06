import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/services/scoreboard_data.dart';

void main() {
  test('parses scoreboard pagination metadata and rankings', () {
    final ScoreboardPageData page = ScoreboardPageData.fromJson(
      <String, dynamic>{
        'offset': 20,
        'limit': 20,
        'total_count': 45,
        'has_more': true,
        'rank_threshold': 10,
        'frozen': false,
        'rankings': <Map<String, dynamic>>[
          <String, dynamic>{
            'user_id': 'alice',
            'display_name': 'Alice',
            'rank': 21,
            'score': 42,
          },
        ],
      },
      requestedOffset: 20,
      requestedLimit: 20,
    );

    expect(page.offset, 20);
    expect(page.limit, 20);
    expect(page.totalCount, 45);
    expect(page.hasMore, isTrue);
    expect(page.entries.single.displayName, 'Alice');
  });

  test('supports entries and infers whether another page exists', () {
    final ScoreboardPageData page = ScoreboardPageData.fromJson(
      <String, dynamic>{
        'entries': List<Map<String, dynamic>>.generate(
          2,
          (int index) => <String, dynamic>{
            'id': 'user-$index',
            'name': 'Player $index',
            'position': index + 1,
            'points': 10 - index,
          },
        ),
      },
      requestedOffset: 0,
      requestedLimit: 2,
    );

    expect(page.hasMore, isTrue);
    expect(page.entries, hasLength(2));
    expect(page.entries.first.rank, 1);
  });

  test('parses nested scoreboard me payload with a user id fallback', () {
    final ScoreboardEntry? entry = ScoreboardEntry.fromMyRankPayload(
      <String, dynamic>{
        'ranking': <String, dynamic>{
          'rank': 87,
          'score': 123,
          'display_name': 'Me',
          'emoji_icon': '🐾',
        },
      },
      fallbackUserId: 'current-user',
    );

    expect(entry?.userId, 'current-user');
    expect(entry?.rank, 87);
    expect(entry?.score, 123);
  });

  test('keeps parsing the root when ranking is a scalar field', () {
    final ScoreboardEntry? entry = ScoreboardEntry.fromMyRankPayload(
      <String, dynamic>{
        'ranking': 12,
        'rank': 12,
        'score': 88,
        'display_name': 'Scalar Rank',
      },
      fallbackUserId: 'current-user',
    );

    expect(entry?.rank, 12);
    expect(entry?.displayName, 'Scalar Rank');
  });

  test('places the current user at the exact rank inside a page', () {
    final List<ScoreboardEntry> merged = mergeScoreboardPageWithCurrentUser(
      <ScoreboardEntry>[
        _entry('rank-1', 1),
        _entry('rank-2', 2),
        _entry('rank-4', 4),
      ],
      _entry('me', 3),
    );

    expect(merged.map((ScoreboardEntry entry) => entry.rank), <int>[
      1,
      2,
      3,
      4,
    ]);
  });

  test('pins the current user above or below an out-of-range page', () {
    final List<ScoreboardEntry> page = <ScoreboardEntry>[
      _entry('rank-51', 51),
      _entry('rank-52', 52),
    ];

    expect(
      mergeScoreboardPageWithCurrentUser(page, _entry('me', 20)).first.rank,
      20,
    );
    expect(
      mergeScoreboardPageWithCurrentUser(page, _entry('me', 87)).last.rank,
      87,
    );
  });

  test('does not duplicate the current user already in the page', () {
    final List<ScoreboardEntry> page = <ScoreboardEntry>[
      _entry('alice', 1),
      _entry('me', 2, score: 99),
      _entry('carol', 3),
    ];

    final List<ScoreboardEntry> merged = mergeScoreboardPageWithCurrentUser(
      page,
      _entry('me', 2),
    );

    expect(merged, hasLength(3));
    expect(merged[1].score, 99);
  });

  test('finds the scoreboard page containing a rank', () {
    expect(scoreboardPageOffsetForRank(1, 50), 0);
    expect(scoreboardPageOffsetForRank(50, 50), 0);
    expect(scoreboardPageOffsetForRank(87, 50), 50);
    expect(scoreboardPageOffsetForRank(101, 50), 100);
  });
}

ScoreboardEntry _entry(String userId, int rank, {int score = 0}) {
  return ScoreboardEntry(
    userId: userId,
    displayName: userId,
    score: score,
    rank: rank,
    emojiIcon: '',
  );
}
