import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/local_scoreboard_store.dart';
import '../../services/nfc_battle_api_client.dart';
import '../../services/scoreboard_data.dart';
import 'offline_retry_banner.dart';
import 'pixel_theme.dart';
import 'user_collection_page.dart';

class ScoreBoardPage extends StatefulWidget {
  const ScoreBoardPage({super.key, this.scheme});

  final PixelScheme? scheme;

  @override
  State<ScoreBoardPage> createState() => _ScoreBoardPageState();
}

class _ScoreBoardPageState extends State<ScoreBoardPage> {
  static const int _pageSize = 50;

  final ValueNotifier<RefreshIndicatorStatus?> _refreshStatus =
      ValueNotifier<RefreshIndicatorStatus?>(null);
  final ValueNotifier<double> _refreshPullDistance = ValueNotifier<double>(0);
  final AuthService _authService = AuthService();
  final LocalScoreboardStore _localStore = LocalScoreboardStore();

  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isPageLoading = false;
  bool _isOffline = false;
  List<ScoreboardEntry> _pageEntries = <ScoreboardEntry>[];
  ScoreboardEntry? _myRank;
  int _rankThreshold = 0;
  int _topScore = 0;
  int _currentPage = 0;
  int? _totalCount;
  bool _hasMore = false;
  bool _frozen = false;

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  @override
  void dispose() {
    _refreshStatus.dispose();
    _refreshPullDistance.dispose();
    super.dispose();
  }

  Future<void> _loadBoard({int? page, bool refreshMe = true}) async {
    if (_isRefreshing) {
      return;
    }
    final int targetPage = page ?? _currentPage;
    final int targetOffset = targetPage * _pageSize;
    _isRefreshing = true;
    setState(() {
      _isLoading = true;
      _isPageLoading = targetPage != _currentPage;
    });
    Object? boardError;
    Object? meError;
    try {
      final String? userId = _authService.currentUserId;
      if (userId != null) {
        final Future<Map<String, dynamic>?> cachedPageFuture = _localStore
            .loadPage(userId, offset: targetOffset, limit: _pageSize);
        final Future<Map<String, dynamic>?> cachedMeFuture = refreshMe
            ? _localStore.loadMyRank(userId)
            : Future<Map<String, dynamic>?>.value(null);
        final List<Map<String, dynamic>?> cached =
            await Future.wait<Map<String, dynamic>?>(
              <Future<Map<String, dynamic>?>>[cachedPageFuture, cachedMeFuture],
            );
        if (!mounted) {
          return;
        }
        if (cached[0] != null &&
            (_pageEntries.isEmpty || targetPage != _currentPage)) {
          setState(() {
            _applyBoard(
              cached[0]!,
              requestedOffset: targetOffset,
              requestedLimit: _pageSize,
            );
            _currentPage = targetPage;
          });
        }
        if (cached[1] != null && _myRank == null) {
          setState(() {
            _applyMyRank(
              cached[1]!,
              fallbackUserId: userId,
              allowUnmatched: true,
            );
          });
        }
      }

      final Future<Map<String, dynamic>?> boardFuture = _authService
          .fetchScoreboard(
            offset: targetOffset,
            limit: _pageSize,
            onError: (Object error) {
              boardError = error;
            },
          );
      final Future<Map<String, dynamic>?> meFuture = refreshMe
          ? _authService.fetchMyScoreboardRank(
              onError: (Object error) {
                meError = error;
              },
            )
          : Future<Map<String, dynamic>?>.value(null);
      final List<Map<String, dynamic>?> results =
          await Future.wait<Map<String, dynamic>?>(
            <Future<Map<String, dynamic>?>>[boardFuture, meFuture],
          );
      final Map<String, dynamic>? board = results[0];
      final Map<String, dynamic>? me = results[1];
      if (board != null && userId != null) {
        await _localStore.savePage(
          userId,
          board,
          offset: targetOffset,
          limit: _pageSize,
        );
      }
      if (!mounted) {
        return;
      }
      ScoreboardEntry? myRankMarker;
      setState(() {
        if (board != null) {
          _applyBoard(
            board,
            requestedOffset: targetOffset,
            requestedLimit: _pageSize,
          );
          _currentPage = targetPage;
        }
        if (me != null) {
          myRankMarker = _applyMyRank(me, fallbackUserId: userId ?? '');
        }
        _isOffline = <Object?>[
          boardError,
          meError,
        ].whereType<Object>().any(isNetworkConnectionError);
      });
      if (myRankMarker != null && userId != null) {
        await _resolveMyRankFromScoreboard(
          marker: myRankMarker!,
          currentBoard: board,
          currentOffset: targetOffset,
          userId: userId,
        );
      }
    } finally {
      _isRefreshing = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPageLoading = false;
        });
      }
    }
  }

  void _applyBoard(
    Map<String, dynamic> board, {
    required int requestedOffset,
    required int requestedLimit,
  }) {
    final ScoreboardPageData page = ScoreboardPageData.fromJson(
      board,
      requestedOffset: requestedOffset,
      requestedLimit: requestedLimit,
    );
    _rankThreshold = page.rankThreshold;
    _frozen = page.frozen;
    _hasMore = page.hasMore;
    if (page.totalCount != null || requestedOffset == 0) {
      _totalCount = page.totalCount;
    }
    _pageEntries = page.entries;
    if (requestedOffset == 0) {
      _topScore = page.entries.isEmpty ? 0 : page.entries.first.score;
    }
  }

  ScoreboardEntry? _applyMyRank(
    Map<String, dynamic> payload, {
    required String fallbackUserId,
    bool allowUnmatched = false,
  }) {
    final ScoreboardEntry? entry = ScoreboardEntry.fromMyRankPayload(
      payload,
      fallbackUserId: fallbackUserId,
    );
    if (entry != null && entry.rank > 0) {
      final ScoreboardEntry? pageEntry = _findCurrentUserEntry(
        _pageEntries,
        entry,
      );
      if (pageEntry != null) {
        _myRank = pageEntry;
      } else if (allowUnmatched) {
        _myRank = entry;
      } else if (_myRank?.rank != entry.rank) {
        _myRank = null;
      }
      return entry;
    }
    _myRank = null;
    return null;
  }

  Future<void> _resolveMyRankFromScoreboard({
    required ScoreboardEntry marker,
    required Map<String, dynamic>? currentBoard,
    required int currentOffset,
    required String userId,
  }) async {
    ScoreboardEntry? resolved;
    if (currentBoard != null) {
      final ScoreboardPageData currentPage = ScoreboardPageData.fromJson(
        currentBoard,
        requestedOffset: currentOffset,
        requestedLimit: _pageSize,
      );
      resolved = _findCurrentUserEntry(currentPage.entries, marker);
    } else {
      resolved = _findCurrentUserEntry(_pageEntries, marker);
    }
    if (resolved != null) {
      await _storeResolvedMyRank(userId, resolved);
      return;
    }

    final int ownPageOffset = scoreboardPageOffsetForRank(
      marker.rank,
      _pageSize,
    );
    final Map<String, dynamic>? cachedOwnPage = await _localStore.loadPage(
      userId,
      offset: ownPageOffset,
      limit: _pageSize,
    );
    if (cachedOwnPage != null) {
      final ScoreboardPageData cachedPage = ScoreboardPageData.fromJson(
        cachedOwnPage,
        requestedOffset: ownPageOffset,
        requestedLimit: _pageSize,
      );
      resolved = _findCurrentUserEntry(cachedPage.entries, marker);
      if (resolved != null && mounted) {
        setState(() {
          _myRank = resolved;
        });
      }
    }

    Object? exactRankError;
    final Map<String, dynamic>? ownPage = await _authService.fetchScoreboard(
      offset: ownPageOffset,
      limit: _pageSize,
      onError: (Object error) {
        exactRankError = error;
      },
    );
    if (ownPage != null) {
      await _localStore.savePage(
        userId,
        ownPage,
        offset: ownPageOffset,
        limit: _pageSize,
      );
      final ScoreboardPageData exactPage = ScoreboardPageData.fromJson(
        ownPage,
        requestedOffset: ownPageOffset,
        requestedLimit: _pageSize,
      );
      resolved = _findCurrentUserEntry(exactPage.entries, marker) ?? resolved;
    }
    if (exactRankError != null &&
        isNetworkConnectionError(exactRankError!) &&
        mounted) {
      setState(() {
        _isOffline = true;
      });
    }
    if (resolved != null) {
      await _storeResolvedMyRank(userId, resolved);
    }
  }

  Future<void> _storeResolvedMyRank(
    String userId,
    ScoreboardEntry resolved,
  ) async {
    await _localStore.saveMyRank(userId, resolved.toJson());
    if (!mounted) {
      return;
    }
    setState(() {
      _myRank = resolved;
    });
  }

  ScoreboardEntry? _findCurrentUserEntry(
    List<ScoreboardEntry> entries,
    ScoreboardEntry marker,
  ) {
    if (marker.userId.isNotEmpty) {
      for (final ScoreboardEntry entry in entries) {
        if (entry.userId == marker.userId) {
          return entry;
        }
      }
    }
    for (final ScoreboardEntry entry in entries) {
      if (entry.rank == marker.rank) {
        return entry;
      }
    }
    return null;
  }

  Map<String, Object> _rankRow(ScoreboardEntry entry) {
    return <String, Object>{
      'userId': entry.userId,
      'name': entry.displayName,
      'score': entry.score,
      'rank': entry.rank,
      'badge': entry.rank <= 0 ? '-' : '#${entry.rank}',
      'emoji': entry.emojiIcon,
      'color': _rankColor(entry.rank),
    };
  }

  List<Map<String, Object>> get _ranks {
    final ScoreboardEntry? myRank = _myRank;
    return mergeScoreboardPageWithCurrentUser(_pageEntries, myRank)
        .map((ScoreboardEntry entry) {
          return <String, Object>{
            ..._rankRow(entry),
            'isMe':
                myRank != null &&
                scoreboardEntriesIdentifySameUser(entry, myRank),
          };
        })
        .toList(growable: false);
  }

  Color _rankColor(int rank) {
    if (rank == 1) {
      return PixelTheme.accent;
    }
    if (rank == 2) {
      return PixelTheme.accentBlue;
    }
    if (rank == 3) {
      return PixelTheme.success;
    }
    return PixelTheme.textGray;
  }

  int? get _totalPages {
    final int? totalCount = _totalCount;
    if (totalCount == null) {
      return null;
    }
    return totalCount <= 0 ? 1 : (totalCount + _pageSize - 1) ~/ _pageSize;
  }

  Future<void> _showPreviousPage() async {
    if (_currentPage <= 0 || _isRefreshing) {
      return;
    }
    await _loadBoard(page: _currentPage - 1, refreshMe: false);
  }

  Future<void> _showNextPage() async {
    if (!_hasMore || _isRefreshing) {
      return;
    }
    await _loadBoard(page: _currentPage + 1, refreshMe: false);
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(
      widget.scheme ?? PixelTheme.defaultScheme,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
        primaryTextTheme: Theme.of(
          context,
        ).primaryTextTheme.apply(fontFamily: 'Unifont'),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Unifont'),
        child: Stack(
          children: [
            RefreshIndicator.noSpinner(
              onRefresh: _loadBoard,
              onStatusChange: _handleRefreshStatusChange,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleRefreshScrollNotification,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    if (_isOffline) ...<Widget>[
                      OfflineRetryBanner(
                        onRetry: _loadBoard,
                        isRetrying: _isRefreshing,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _BoardHeader(isLoading: _isLoading, frozen: _frozen),
                    const SizedBox(height: 12),
                    _StatRow(
                      shownRanks: _pageEntries.length,
                      topScore: _topScore,
                      rankThreshold: _rankThreshold,
                    ),
                    const SizedBox(height: 12),
                    _RankPanel(
                      ranks: _ranks,
                      currentPage: _currentPage,
                      totalPages: _totalPages,
                      hasNextPage: _hasMore,
                      isPageLoading: _isPageLoading,
                      onPreviousPage: _showPreviousPage,
                      onNextPage: _showNextPage,
                      onOpenUser: _openUser,
                    ),
                  ],
                ),
              ),
            ),
            _PixelRefreshBanner(
              statusListenable: _refreshStatus,
              pullDistanceListenable: _refreshPullDistance,
            ),
          ],
        ),
      ),
    );
  }

  void _openUser(Map<String, Object> row) {
    final String userId = row['userId'] as String? ?? '';
    if (userId.isEmpty) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => UserCollectionPage(
          userId: userId,
          displayName: row['name'] as String? ?? userId,
          emojiIcon: row['emoji'] as String? ?? '',
          rank: row['rank'] as int? ?? 0,
          score: row['score'] as int? ?? 0,
          scheme: widget.scheme,
        ),
      ),
    );
  }

  void _handleRefreshStatusChange(RefreshIndicatorStatus? status) {
    if (_refreshStatus.value == status) {
      return;
    }
    _refreshStatus.value = status;
    if (status == null || status == RefreshIndicatorStatus.canceled) {
      _refreshPullDistance.value = 0;
    }
    if (status == RefreshIndicatorStatus.done) {
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (!mounted || _refreshStatus.value != RefreshIndicatorStatus.done) {
          return;
        }
        _refreshStatus.value = null;
        _refreshPullDistance.value = 0;
      });
    }
  }

  bool _handleRefreshScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent &&
        notification.overscroll < 0) {
      _refreshPullDistance.value =
          (_refreshPullDistance.value - notification.overscroll)
              .clamp(0, 96)
              .toDouble();
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent &&
        notification.dragDetails != null) {
      _refreshPullDistance.value = (-notification.metrics.pixels)
          .clamp(0, 96)
          .toDouble();
    } else if (notification is ScrollEndNotification &&
        _refreshStatus.value != RefreshIndicatorStatus.refresh &&
        _refreshStatus.value != RefreshIndicatorStatus.snap) {
      _refreshPullDistance.value = 0;
    }
    return false;
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({required this.isLoading, required this.frozen});

  final bool isLoading;
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.accent, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.tr('scoreboardTitle'),
                  style: TextStyle(
                    color: PixelTheme.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              if (isLoading)
                Text(
                  context.l10n.tr('sync'),
                  style: TextStyle(
                    color: PixelTheme.accentBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                )
              else if (frozen)
                Text(
                  context.l10n.tr('frozen'),
                  style: TextStyle(
                    color: PixelTheme.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.tr('scoreboardHint'),
            style: TextStyle(color: PixelTheme.textWhite),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.shownRanks,
    required this.topScore,
    required this.rankThreshold,
  });

  final int shownRanks;
  final int topScore;
  final int rankThreshold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: context.l10n.tr('shownRanks'),
            value: '$shownRanks',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: context.l10n.tr('prize'),
            value: rankThreshold <= 0 ? '-' : '$rankThreshold',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(label: context.l10n.tr('top'), value: '$topScore'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.border, width: 2),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: PixelTheme.textGray,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: PixelTheme.accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankPanel extends StatelessWidget {
  const _RankPanel({
    required this.ranks,
    required this.currentPage,
    required this.totalPages,
    required this.hasNextPage,
    required this.isPageLoading,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onOpenUser,
  });

  final List<Map<String, Object>> ranks;
  final int currentPage;
  final int? totalPages;
  final bool hasNextPage;
  final bool isPageLoading;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final ValueChanged<Map<String, Object>> onOpenUser;

  bool get _showPagination =>
      currentPage > 0 || hasNextPage || (totalPages ?? 1) > 1;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.border, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.l10n.tr('ranking'),
                  style: TextStyle(
                    color: PixelTheme.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (isPageLoading)
                Text(
                  context.l10n.tr('sync'),
                  style: TextStyle(
                    color: PixelTheme.accentBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (ranks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.l10n.tr('noRankings'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PixelTheme.textGray),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ranks.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final Map<String, Object> row = ranks[index];
                return _RankTile(
                  row: row,
                  highlighted: row['isMe'] == true,
                  onTap: () => onOpenUser(row),
                );
              },
            ),
          if (_showPagination) ...<Widget>[
            const SizedBox(height: 14),
            _ScoreboardPagination(
              currentPage: currentPage,
              totalPages: totalPages,
              previousEnabled: currentPage > 0 && !isPageLoading,
              nextEnabled: hasNextPage && !isPageLoading,
              onPrevious: onPreviousPage,
              onNext: onNextPage,
            ),
          ],
        ],
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.row,
    required this.onTap,
    this.highlighted = false,
  });

  final Map<String, Object> row;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final Color color = highlighted
        ? PixelTheme.accentBlue
        : row['color'] as Color;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(color: color, width: 2),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: PixelTheme.bgDark, width: 2),
                ),
                child: Text(
                  '${row['badge']}',
                  maxLines: 1,
                  style: TextStyle(
                    color: PixelTheme.bgDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${row['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: PixelTheme.textWhite,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (highlighted) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: PixelTheme.accentBlue,
                          border: Border.all(color: PixelTheme.bgDark),
                        ),
                        child: Text(
                          context.l10n.tr('scoreboardYou'),
                          style: TextStyle(
                            color: PixelTheme.bgDark,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${row['score']}',
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: PixelTheme.textGray,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreboardPagination extends StatelessWidget {
  const _ScoreboardPagination({
    required this.currentPage,
    required this.totalPages,
    required this.previousEnabled,
    required this.nextEnabled,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int? totalPages;
  final bool previousEnabled;
  final bool nextEnabled;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final int pageNumber = currentPage + 1;
    final String pageLabel = totalPages == null
        ? context.l10n.tr('scoreboardPage', <String, Object?>{
            'current': pageNumber,
          })
        : context.l10n.tr('scoreboardPageOf', <String, Object?>{
            'current': pageNumber,
            'total': totalPages,
          });
    return Row(
      children: <Widget>[
        Expanded(
          child: _PixelPageButton(
            key: const Key('scoreboard-previous-page'),
            label: context.l10n.tr('previousPage'),
            leading: true,
            enabled: previousEnabled,
            onTap: onPrevious,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          key: const Key('scoreboard-page-label'),
          constraints: const BoxConstraints(minWidth: 76),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(color: PixelTheme.border, width: 2),
          ),
          child: Text(
            pageLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PixelPageButton(
            key: const Key('scoreboard-next-page'),
            label: context.l10n.tr('nextPage'),
            leading: false,
            enabled: nextEnabled,
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}

class _PixelPageButton extends StatelessWidget {
  const _PixelPageButton({
    super.key,
    required this.label,
    required this.leading,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool leading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = enabled ? PixelTheme.accent : PixelTheme.textGray;
    final Widget arrow = Text(
      leading ? '<' : '>',
      style: TextStyle(color: color, fontWeight: FontWeight.w900),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: PixelTheme.bgDark,
              border: Border.all(color: color, width: 2),
              boxShadow: enabled
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Colors.black,
                        blurRadius: 0,
                        offset: Offset(3, 3),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (leading) ...<Widget>[arrow, const SizedBox(width: 5)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (!leading) ...<Widget>[const SizedBox(width: 5), arrow],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelRefreshBanner extends StatefulWidget {
  const _PixelRefreshBanner({
    required this.statusListenable,
    required this.pullDistanceListenable,
  });

  final ValueListenable<RefreshIndicatorStatus?> statusListenable;
  final ValueListenable<double> pullDistanceListenable;

  @override
  State<_PixelRefreshBanner> createState() => _PixelRefreshBannerState();
}

class _PixelRefreshBannerState extends State<_PixelRefreshBanner> {
  RefreshIndicatorStatus? _displayStatus;
  double _displayPullDistance = 0;

  @override
  void initState() {
    super.initState();
    widget.statusListenable.addListener(_handleRefreshValueChanged);
    widget.pullDistanceListenable.addListener(_handleRefreshValueChanged);
    _syncDisplayState();
  }

  @override
  void didUpdateWidget(covariant _PixelRefreshBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statusListenable != widget.statusListenable) {
      oldWidget.statusListenable.removeListener(_handleRefreshValueChanged);
      widget.statusListenable.addListener(_handleRefreshValueChanged);
    }
    if (oldWidget.pullDistanceListenable != widget.pullDistanceListenable) {
      oldWidget.pullDistanceListenable.removeListener(
        _handleRefreshValueChanged,
      );
      widget.pullDistanceListenable.addListener(_handleRefreshValueChanged);
    }
    _syncDisplayState();
  }

  @override
  void dispose() {
    widget.statusListenable.removeListener(_handleRefreshValueChanged);
    widget.pullDistanceListenable.removeListener(_handleRefreshValueChanged);
    super.dispose();
  }

  RefreshIndicatorStatus? get _status => widget.statusListenable.value;

  double get _pullDistance => widget.pullDistanceListenable.value;

  void _handleRefreshValueChanged() {
    setState(_syncDisplayState);
  }

  void _syncDisplayState() {
    if (_status != null && _status != RefreshIndicatorStatus.canceled) {
      _displayStatus = _status;
    }
    if (_pullDistance > 0 || _visible) {
      _displayPullDistance = _pullDistance;
    }
  }

  bool get _visible {
    return _status != null && _status != RefreshIndicatorStatus.canceled;
  }

  String get _message {
    return switch (_displayStatus) {
      RefreshIndicatorStatus.drag => context.l10n.tr('pullToRefresh'),
      RefreshIndicatorStatus.armed => context.l10n.tr('releaseToSync'),
      RefreshIndicatorStatus.snap ||
      RefreshIndicatorStatus.refresh => context.l10n.tr('syncing'),
      RefreshIndicatorStatus.done => context.l10n.tr('updateComplete'),
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final double top = (_displayPullDistance * 0.72).clamp(8, 62).toDouble();
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: PixelTheme.bgMid,
                border: Border.all(color: PixelTheme.accent, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(4, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PixelRefreshGlyph(status: _displayStatus),
                  const SizedBox(width: 8),
                  Text(
                    _message,
                    style: TextStyle(
                      color: PixelTheme.accent,
                      fontFamily: 'Unifont',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelRefreshGlyph extends StatelessWidget {
  const _PixelRefreshGlyph({required this.status});

  final RefreshIndicatorStatus? status;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18,
      child: CustomPaint(painter: _PixelRefreshGlyphPainter(status: status)),
    );
  }
}

class _PixelRefreshGlyphPainter extends CustomPainter {
  const _PixelRefreshGlyphPainter({required this.status});

  final RefreshIndicatorStatus? status;

  static const List<String> _down = <String>[
    '00111100',
    '00111100',
    '00111100',
    '11111111',
    '01111110',
    '00111100',
    '00011000',
    '00000000',
  ];

  static const List<String> _up = <String>[
    '00011000',
    '00111100',
    '01111110',
    '11111111',
    '00111100',
    '00111100',
    '00111100',
    '00000000',
  ];

  static const List<String> _sync = <String>[
    '00111100',
    '01100010',
    '11000001',
    '10011001',
    '10011001',
    '10000011',
    '01000110',
    '00111100',
  ];

  static const List<String> _done = <String>[
    '00000001',
    '00000011',
    '00000110',
    '11001100',
    '11111000',
    '01110000',
    '00100000',
    '00000000',
  ];

  List<String> get _pattern {
    return switch (status) {
      RefreshIndicatorStatus.armed => _up,
      RefreshIndicatorStatus.snap || RefreshIndicatorStatus.refresh => _sync,
      RefreshIndicatorStatus.done => _done,
      _ => _down,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = PixelTheme.accent
      ..style = PaintingStyle.fill;
    final double cell = size.shortestSide / 8;
    final double left = (size.width - cell * 8) / 2;
    final double top = (size.height - cell * 8) / 2;

    for (int y = 0; y < _pattern.length; y += 1) {
      for (int x = 0; x < _pattern[y].length; x += 1) {
        if (_pattern[y][x] != '1') {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(left + x * cell, top + y * cell, cell, cell),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PixelRefreshGlyphPainter oldDelegate) {
    return oldDelegate.status != status;
  }
}
