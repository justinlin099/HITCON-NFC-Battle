import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import 'pixel_theme.dart';
import 'user_collection_page.dart';

class ScoreBoardPage extends StatefulWidget {
  const ScoreBoardPage({super.key, this.scheme});

  final PixelScheme? scheme;

  @override
  State<ScoreBoardPage> createState() => _ScoreBoardPageState();
}

class _ScoreBoardPageState extends State<ScoreBoardPage> {
  final ValueNotifier<RefreshIndicatorStatus?> _refreshStatus =
      ValueNotifier<RefreshIndicatorStatus?>(null);
  final ValueNotifier<double> _refreshPullDistance = ValueNotifier<double>(0);
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  List<Map<String, Object>> _remoteRanks = <Map<String, Object>>[];
  int _rankThreshold = 0;
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

  Future<void> _loadBoard() async {
    setState(() {
      _isLoading = true;
    });
    final Map<String, dynamic>? board = await _authService.fetchScoreboard();
    if (!mounted) {
      return;
    }
    setState(() {
      if (board != null) {
        _rankThreshold = board['rank_threshold'] as int? ?? 0;
        _frozen = board['frozen'] as bool? ?? false;
        final List<dynamic> rankings =
            board['rankings'] as List<dynamic>? ?? <dynamic>[];
        _remoteRanks = rankings
            .whereType<Map>()
            .map((Map row) {
              final Map<String, dynamic> item = row.map((
                Object? key,
                Object? value,
              ) {
                return MapEntry<String, dynamic>(key.toString(), value);
              });
              final int rank = item['rank'] as int? ?? 0;
              return <String, Object>{
                'userId': item['user_id'] as String? ?? '',
                'name':
                    item['display_name'] as String? ?? item['user_id'] ?? '',
                'score': item['score'] as int? ?? 0,
                'rank': rank,
                'badge': rank <= 0 ? '-' : '#$rank',
                'emoji': item['emoji_icon'] as String? ?? '',
                'color': _rankColor(rank),
              };
            })
            .toList(growable: false);
      }
      _isLoading = false;
    });
  }

  List<Map<String, Object>> get _ranks {
    return _remoteRanks;
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
                    _BoardHeader(isLoading: _isLoading, frozen: _frozen),
                    const SizedBox(height: 12),
                    _StatRow(
                      shownRanks: _ranks.length,
                      topScore: _ranks.isEmpty
                          ? 0
                          : _ranks.first['score'] as int? ?? 0,
                      rankThreshold: _rankThreshold,
                    ),
                    const SizedBox(height: 12),
                    _RankPanel(ranks: _ranks, onOpenUser: _openUser),
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
  const _RankPanel({required this.ranks, required this.onOpenUser});

  final List<Map<String, Object>> ranks;
  final ValueChanged<Map<String, Object>> onOpenUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.border, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr('ranking'),
            style: TextStyle(
              color: PixelTheme.accent,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
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
                final Color color = row['color'] as Color;
                return GestureDetector(
                  onTap: () => onOpenUser(row),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: PixelTheme.bgDark,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color,
                            border: Border.all(
                              color: PixelTheme.bgDark,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            '${row['badge']}',
                            style: TextStyle(
                              color: PixelTheme.bgDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['name']}',
                                style: TextStyle(
                                  color: PixelTheme.textWhite,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                );
              },
            ),
        ],
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
