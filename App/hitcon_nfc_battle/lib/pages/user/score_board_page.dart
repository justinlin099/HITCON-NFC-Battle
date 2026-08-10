import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/achievement_config.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/achievement_data.dart';
import '../../services/local_scoreboard_store.dart';
import '../../services/nfc_battle_api_client.dart';
import '../../services/scoreboard_data.dart';
import 'offline_retry_banner.dart';
import 'pixel_theme.dart';
import 'user_collection_page.dart';

class ScoreBoardPage extends StatefulWidget {
  const ScoreBoardPage({
    super.key,
    this.scheme,
    this.stampMission,
    this.profile,
    this.collectionCards,
    this.prizeResult,
  });

  final PixelScheme? scheme;
  final Map<String, dynamic>? stampMission;
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>>? collectionCards;
  final Map<String, dynamic>? prizeResult;

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
  Map<String, dynamic>? _stampMission;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>>? _collectionCards;
  Map<String, dynamic>? _prizeResult;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? initialMission = widget.stampMission;
    if (initialMission != null) {
      _stampMission = Map<String, dynamic>.from(initialMission);
    }
    final Map<String, dynamic>? initialProfile = widget.profile;
    if (initialProfile != null) {
      _profile = Map<String, dynamic>.from(initialProfile);
    }
    final List<Map<String, dynamic>>? initialCards = widget.collectionCards;
    if (initialCards != null) {
      _collectionCards = initialCards
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    }
    final Map<String, dynamic>? initialPrize = widget.prizeResult;
    if (initialPrize != null) {
      _prizeResult = Map<String, dynamic>.from(initialPrize);
    }
    _loadBoard();
  }

  @override
  void didUpdateWidget(covariant ScoreBoardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final Map<String, dynamic>? updatedMission = widget.stampMission;
    if (updatedMission != null &&
        !identical(updatedMission, oldWidget.stampMission)) {
      _stampMission = Map<String, dynamic>.from(updatedMission);
    }
    final Map<String, dynamic>? updatedProfile = widget.profile;
    if (updatedProfile != null &&
        !identical(updatedProfile, oldWidget.profile)) {
      _profile = Map<String, dynamic>.from(updatedProfile);
    }
    final List<Map<String, dynamic>>? updatedCards = widget.collectionCards;
    if (updatedCards != null &&
        !identical(updatedCards, oldWidget.collectionCards)) {
      _collectionCards = updatedCards
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    }
    final Map<String, dynamic>? updatedPrize = widget.prizeResult;
    if (updatedPrize != null &&
        !identical(updatedPrize, oldWidget.prizeResult)) {
      _prizeResult = Map<String, dynamic>.from(updatedPrize);
    }
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
    Object? missionError;
    Object? profileError;
    Object? prizeError;
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
      final Future<Map<String, dynamic>?> missionFuture = refreshMe
          ? _authService.fetchStampMission(
              onError: (Object error) {
                missionError = error;
              },
            )
          : Future<Map<String, dynamic>?>.value(null);
      final Future<Map<String, dynamic>?> profileFuture = refreshMe
          ? _authService.fetchUserProfile(
              onError: (Object error) {
                profileError = error;
              },
            )
          : Future<Map<String, dynamic>?>.value(null);
      final Future<Map<String, dynamic>?> prizeFuture = refreshMe
          ? _authService.fetchMyPrize(
              onError: (Object error) {
                prizeError = error;
              },
            )
          : Future<Map<String, dynamic>?>.value(null);
      final List<Map<String, dynamic>?> results =
          await Future.wait<Map<String, dynamic>?>(
            <Future<Map<String, dynamic>?>>[
              boardFuture,
              meFuture,
              missionFuture,
              profileFuture,
              prizeFuture,
            ],
          );
      final Map<String, dynamic>? board = results[0];
      final Map<String, dynamic>? me = results[1];
      final Map<String, dynamic>? stampMission = results[2];
      final Map<String, dynamic>? profile = results[3];
      final Map<String, dynamic>? prizeResult = results[4];
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
        if (stampMission != null) {
          _stampMission = stampMission;
        }
        if (profile != null) {
          _profile = profile;
        }
        if (prizeResult != null) {
          _prizeResult = prizeResult;
        }
        _isOffline = <Object?>[
          boardError,
          meError,
          missionError,
          profileError,
          prizeError,
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
                    ValueListenableBuilder<AchievementRules?>(
                      valueListenable: AppConfig.achievementRulesListenable,
                      builder:
                          (
                            BuildContext context,
                            AchievementRules? rules,
                            Widget? child,
                          ) {
                            final List<AchievementBadgeProgress> achievements =
                                evaluateAchievements(
                                  AchievementSnapshot(
                                    profile: _profile,
                                    collectionCards: _collectionCards,
                                    stampMission: _stampMission,
                                    prizeResult: _prizeResult,
                                    rank: _myRank?.rank,
                                    scoreboardFrozen: _frozen,
                                    remoteRules: rules,
                                  ),
                                );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ScoreboardAchievementPanel(
                                achievements: achievements,
                              ),
                            );
                          },
                    ),
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

class _ScoreboardAchievementPanel extends StatelessWidget {
  const _ScoreboardAchievementPanel({required this.achievements});

  final List<AchievementBadgeProgress> achievements;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('scoreboard-achievements'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.accentBlue, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _PixelAchievementHeaderGlyph(),
              const SizedBox(width: 7),
              Text(
                context.l10n.tr('achievements'),
                style: TextStyle(
                  color: PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: achievements
                  .map(
                    (AchievementBadgeProgress achievement) => Padding(
                      padding: const EdgeInsets.only(right: 9),
                      child: _ScoreboardAchievementBadge(
                        key: ValueKey<String>(
                          'scoreboard-achievement-${achievement.kind.name}',
                        ),
                        achievement: achievement,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreboardAchievementBadge extends StatelessWidget {
  const _ScoreboardAchievementBadge({super.key, required this.achievement});

  final AchievementBadgeProgress achievement;

  @override
  Widget build(BuildContext context) {
    final bool unlocked = achievement.isUnlocked;
    final bool available = achievement.dataAvailable;
    final Color color = unlocked
        ? PixelTheme.accent
        : available
        ? PixelTheme.textGray
        : PixelTheme.textGray.withValues(alpha: 0.65);
    final String title = context.l10n.tr(achievement.kind.titleKey);
    final String status = !available
        ? context.l10n.tr('achievementPendingData')
        : context.l10n.tr(
            unlocked ? 'achievementUnlocked' : 'achievementLocked',
          );
    final int? target = achievement.activeTarget;
    final String progress = _progressLabel(context, target);
    final String level = achievement.isTiered
        ? achievementRomanLevel(achievement.displayedLevel)
        : '';
    final int? nextLevel = achievement.nextLevel;
    final String detail = achievement.isTiered
        ? achievement.isMaxLevel
              ? context.l10n.tr('achievementMaxLevel')
              : achievement.unlockedLevel == 0
              ? progress
              : '${context.l10n.tr('achievementNextLevel')} '
                    '${achievementRomanLevel(nextLevel!)}  $progress'
        : progress;
    final String semanticTitle = level.isEmpty ? title : '$title $level';

    return Semantics(
      label: '$semanticTitle, $status${detail.isEmpty ? '' : ', $detail'}',
      child: SizedBox(
        width: 118,
        child: Column(
          children: <Widget>[
            _AchievementBadgeImage(
              achievement: achievement,
              level: level,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontFamily: 'Unifont',
                fontSize: 9.5,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              status,
              style: TextStyle(
                color: color,
                fontFamily: 'Unifont',
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (detail.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: available ? color : PixelTheme.textGray,
                  fontFamily: 'Unifont',
                  fontSize: 8,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _progressLabel(BuildContext context, int? target) {
    if (!achievement.dataAvailable || target == null) {
      return '';
    }
    if (achievement.direction == AchievementProgressDirection.rank) {
      return context.l10n.tr('achievementRankProgress', <String, Object?>{
        'rank': achievement.current,
        'target': target,
      });
    }
    return '${achievement.current}/$target';
  }
}

class _AchievementBadgeImage extends StatelessWidget {
  const _AchievementBadgeImage({
    required this.achievement,
    required this.level,
    required this.color,
  });

  static const ColorFilter _lockedFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  final AchievementBadgeProgress achievement;
  final String level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      achievement.kind.assetPath,
      width: 92,
      height: 92,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      cacheWidth: 184,
      cacheHeight: 184,
      errorBuilder: (BuildContext context, Object error, StackTrace? trace) {
        return Container(
          width: 92,
          height: 92,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(color: PixelTheme.textGray, width: 2),
          ),
          child: Text(
            '?',
            style: TextStyle(
              color: PixelTheme.textGray,
              fontFamily: 'Unifont',
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
    if (!achievement.isUnlocked) {
      image = Opacity(
        opacity: achievement.dataAvailable ? 0.52 : 0.32,
        child: ColorFiltered(colorFilter: _lockedFilter, child: image),
      );
    }

    return SizedBox.square(
      dimension: 92,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          image,
          if (level.isNotEmpty)
            Positioned(
              left: 18,
              right: 18,
              bottom: 7,
              child: Text(
                level,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontFamily: 'Unifont',
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.black, offset: Offset(2, 2)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PixelAchievementHeaderGlyph extends StatelessWidget {
  const _PixelAchievementHeaderGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 14,
      child: CustomPaint(painter: const _PixelAchievementHeaderGlyphPainter()),
    );
  }
}

class _PixelAchievementHeaderGlyphPainter extends CustomPainter {
  const _PixelAchievementHeaderGlyphPainter();

  static const List<String> _pattern = <String>[
    '01111110',
    '11011011',
    '11011011',
    '01111110',
    '00111100',
    '00011000',
    '00111100',
    '01111110',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..isAntiAlias = false
      ..color = PixelTheme.accent
      ..style = PaintingStyle.fill;
    final double cell = size.shortestSide / 8;
    for (int y = 0; y < _pattern.length; y += 1) {
      for (int x = 0; x < _pattern[y].length; x += 1) {
        if (_pattern[y][x] == '1') {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelAchievementHeaderGlyphPainter oldDelegate) => false;
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
