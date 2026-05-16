import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'my_card_editor_page.dart';
import 'card_detail_page.dart';
import 'pixel_card_face.dart';
import 'pixel_theme.dart';
import 'score_board_page.dart';

import '../../services/auth_service.dart';
import '../../services/mock_api_service.dart';

class CardCollectionPage extends StatefulWidget {
  const CardCollectionPage({super.key});

  @override
  State<CardCollectionPage> createState() => _CardCollectionPageState();
}

class _CardCollectionPageState extends State<CardCollectionPage> {
  static const int _prizeRequirement = 9;

  final AuthService _authService = AuthService();

  PixelScheme _selectedScheme = PixelTheme.defaultScheme;
  int _selectedTabIndex = 0;

  bool _isLoading = true;
  Map<String, dynamic>? _collectionData;
  List<Map<String, String>> _featuredBooths = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final List<Map<String, String>> boothResult = await MockApiService.getFeaturedBooths();
      final Map<String, dynamic>? collectionResult = await _authService.fetchCollectionRecords();

      if (!mounted) {
        return;
      }

      setState(() {
        _featuredBooths = boothResult;
        _collectionData = collectionResult;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _cards {
    final dynamic raw = _collectionData?['collection'];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return <Map<String, dynamic>>[];
  }

  int get _totalCollected => _collectionData?['total_collected'] as int? ?? _cards.length;

  bool get _isComplete => _totalCollected >= _prizeRequirement;

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(_selectedScheme);
    final String pageTitle = switch (_selectedTabIndex) {
      1 => '我的卡片',
      2 => 'SCORE BOARD',
      _ => 'HITCON NFC 大亂鬥',
    };

    final ThemeData pixelTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(fontFamily: 'Unifont'),
    );

    return Theme(
      data: pixelTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Unifont'),
        child: Scaffold(
          backgroundColor: PixelTheme.bgDark,
          appBar: AppBar(
            title: Text(pageTitle),
            titleTextStyle: TextStyle(
              color: PixelTheme.accent,
              fontFamily: 'Unifont',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
            centerTitle: true,
            backgroundColor: PixelTheme.bgMid,
            foregroundColor: PixelTheme.accent,
            elevation: 0,
            toolbarHeight: 68,
            actions: [
              PopupMenuButton<PixelScheme>(
                tooltip: '切換配色',
                icon: const Icon(Icons.palette_rounded),
                onSelected: (PixelScheme scheme) {
                  setState(() {
                    _selectedScheme = scheme;
                  });
                },
                itemBuilder: (BuildContext context) {
                  return PixelScheme.values
                      .map(
                        (PixelScheme scheme) => PopupMenuItem<PixelScheme>(
                          value: scheme,
                          child: Text('${PixelTheme.labelOf(scheme)} 配色'),
                        ),
                      )
                      .toList();
                },
              ),
              if (_selectedTabIndex == 0)
                _PixelButton(
                  onPressed: _loadData,
                  label: '↻',
                  tooltip: '重新整理',
                ),
            ],
          ),
          body: IndexedStack(
            index: _selectedTabIndex,
            children: [
              _buildCollectionBody(),
              MyCardEditorPage(scheme: _selectedScheme),
              ScoreBoardPage(scheme: _selectedScheme),
            ],
          ),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: PixelTheme.bgMid,
              indicatorColor: PixelTheme.accent,
              labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    color: PixelTheme.bgDark,
                    fontFamily: 'Unifont',
                    fontWeight: FontWeight.w900,
                  );
                }
                return TextStyle(
                  color: PixelTheme.textWhite,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w700,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: PixelTheme.bgDark);
                }
                return IconThemeData(color: PixelTheme.textWhite);
              }),
            ),
            child: NavigationBar(
              selectedIndex: _selectedTabIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedTabIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.collections_rounded),
                  label: '收集卡牌',
                ),
                NavigationDestination(
                  icon: Icon(Icons.edit_rounded),
                  label: '我的卡片',
                ),
                NavigationDestination(
                  icon: Icon(Icons.emoji_events_rounded),
                  label: 'Score Board',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionBody() {
    if (_isLoading) {
      return Center(
        child: Text(
          'LOADING...',
          style: TextStyle(
            color: PixelTheme.accent,
            fontFamily: 'Unifont',
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: PixelTheme.accent,
      backgroundColor: PixelTheme.bgMid,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _HeroHeader(
              totalCollected: _totalCollected,
              prizeRequirement: _prizeRequirement,
              isComplete: _isComplete,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedBoothHeaderDelegate(
              child: _PinnedBoothStrip(
                booths: _featuredBooths,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  final Map<String, dynamic> card = _cards[index];
                  final String title = card['card_title'] as String? ?? card['tag_name'] as String? ?? 'Unknown';
                  final String attributeEmoji = card['attribute_emoji'] as String? ?? '❓';
                  final String attributeLabel = card['attribute_label'] as String? ?? 'UNKNOWN';
                  final String rawLink = card['link'] as String? ?? '';
                  final String link = rawLink.trim().isEmpty ? 'https://hitcon.org' : rawLink;
                  final Color cardColor = _PixelCard.colorForIndex(index);
                  final String heroTag = 'card-$index';
                  return _PixelCard(
                    title: title,
                    uid: card['physical_uid'] as String? ?? '',
                    collectedAt: card['collected_at'] as String? ?? '',
                    index: index,
                    attributeEmoji: attributeEmoji,
                    attributeLabel: attributeLabel,
                    heroTag: heroTag,
                    onTap: () async => _openCardDetail(
                      heroTag: heroTag,
                      title: title,
                      attributeEmoji: attributeEmoji,
                      attributeLabel: attributeLabel,
                      link: link,
                      uid: card['physical_uid'] as String? ?? '',
                      collectedAt: card['collected_at'] as String? ?? '',
                      cardColor: cardColor,
                    ),
                  );
                },
                childCount: _cards.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
              child: _PrizePanel(
                totalCollected: _totalCollected,
                requiredCount: _prizeRequirement,
                isComplete: _isComplete,
                onRedeem: null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCardDetail({
    required String heroTag,
    required String title,
    required String attributeEmoji,
    required String attributeLabel,
    required String link,
    required String uid,
    required String collectedAt,
    required Color cardColor,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return CardDetailPage(
            heroTag: heroTag,
            title: title,
            attributeEmoji: attributeEmoji,
            attributeLabel: attributeLabel,
            link: link,
            uid: uid,
            collectedAt: collectedAt,
            cardColor: cardColor,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: child,
          );
        },
      ),
    );
  }

}

/// 英雄區塊 - 顯示進度和統計
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.totalCollected,
    required this.prizeRequirement,
    required this.isComplete,
  });

  final int totalCollected;
  final int prizeRequirement;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final double progress = (totalCollected / prizeRequirement).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.accent, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: PixelTheme.accent,
                  border: Border.all(color: PixelTheme.bgDark, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(2, 2)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '◆',
                  style: TextStyle(fontSize: 28, color: PixelTheme.bgDark),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COLLECTION',
                      style: TextStyle(
                        color: PixelTheme.accent,
                        fontFamily: 'Unifont',
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isComplete ? 'COMPLETE !' : 'IN PROGRESS',
                      style: TextStyle(
                        color: isComplete ? PixelTheme.success : PixelTheme.accentBlue,
                        fontFamily: 'Unifont',
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: PixelTheme.bgDark,
              border: Border.all(color: PixelTheme.border, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatItem(label: 'CARDS', value: '$totalCollected'),
                _StatItem(label: 'NEED', value: '$prizeRequirement'),
                _StatItem(label: 'REMAIN', value: '${(prizeRequirement - totalCollected).clamp(0, 999)}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: PixelTheme.bgDark,
              valueColor: AlwaysStoppedAnimation<Color>(
                isComplete ? PixelTheme.success : PixelTheme.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isComplete ? '✓ 達成兌換條件' : '還需 ${prizeRequirement - totalCollected} 張',
            style: TextStyle(
              color: isComplete ? PixelTheme.success : PixelTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Courier New',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: PixelTheme.textGray,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            fontFamily: 'Unifont',
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: PixelTheme.accent,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            fontFamily: 'Unifont',
          ),
        ),
      ],
    );
  }
}

/// 釘選區域委派器
class _PinnedBoothHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedBoothHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 110;

  @override
  double get maxExtent => 110;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: PixelTheme.bgDark,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedBoothHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

/// 釘選攤位列
class _PinnedBoothStrip extends StatelessWidget {
  const _PinnedBoothStrip({required this.booths});

  final List<Map<String, String>> booths;

  Color _getBoothColor(String accent) {
    switch (accent) {
      case 'amber':
        return const Color(0xFFFFAA00);
      case 'cyan':
        return const Color(0xFF00FFFF);
      case 'green':
        return const Color(0xFF00FF00);
      case 'pink':
        return const Color(0xFFFF0099);
      default:
        return PixelTheme.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text(
                '📌 SPONSORS',
                style: TextStyle(
                  color: PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 70,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            scrollDirection: Axis.horizontal,
            itemCount: booths.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, String> booth = booths[index];
              final Color boothColor = _getBoothColor(booth['accent'] ?? '');

              return Container(
                width: 200,
                decoration: BoxDecoration(
                  color: PixelTheme.bgMid,
                  border: Border.all(color: boothColor, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(3, 3)),
                  ],
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: boothColor.withValues(alpha: 0.2),
                        border: Border.all(color: boothColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        booth['icon'] ?? '◆',
                        style: TextStyle(
                          fontSize: 18,
                          color: boothColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            booth['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: PixelTheme.textWhite,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            booth['tag'] ?? '',
                            style: TextStyle(
                              color: boothColor,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Unifont',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 像素卡片
class _PixelCard extends StatefulWidget {
  const _PixelCard({
    required this.title,
    required this.uid,
    required this.collectedAt,
    required this.index,
    required this.attributeEmoji,
    required this.attributeLabel,
    required this.heroTag,
    required this.onTap,
  });

  final String title;
  final String uid;
  final String collectedAt;
  final int index;
  final String attributeEmoji;
  final String attributeLabel;
  final String heroTag;
  final Future<void> Function() onTap;

  static Color colorForIndex(int seed) {
    const List<Color> colors = <Color>[
      Color(0xFF00AAFF), // 電光藍
      Color(0xFFFFAA00), // 橙
      Color(0xFFFF0099), // 粉紅
      Color(0xFF00FF00), // 綠
      Color(0xFFFFFF00), // 黃
      Color(0xFF9900FF), // 紫
    ];
    return colors[seed % colors.length];
  }

  @override
  State<_PixelCard> createState() => _PixelCardState();
}

class _PixelCardState extends State<_PixelCard> {
  bool _showText = true;

  Future<void> _handleTap() async {
    setState(() {
      _showText = false;
    });
    await widget.onTap();
    if (!mounted) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _showText = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color cardColor = _PixelCard.colorForIndex(widget.index);
    final Widget cardBody = PixelCardFace(
      title: widget.title,
      attributeEmoji: widget.attributeEmoji,
      attributeLabel: widget.attributeLabel,
      cardColor: cardColor,
      showText: _showText,
      image: Image.asset(
        'assets/images/mock_card_48.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
      ),
    );

    return GestureDetector(
      onTap: _handleTap,
      child: Hero(
        tag: widget.heroTag,
        flightShuttleBuilder: (context, animation, direction, fromContext, toContext) {
          final Hero fromHero = fromContext.widget as Hero;
          final Hero toHero = toContext.widget as Hero;
            final Widget rawShuttle = direction == HeroFlightDirection.push
              ? fromHero.child
              : toHero.child;
          final ThemeData shuttleTheme = Theme.of(fromContext);
          final Widget shuttle = Theme(
            data: shuttleTheme.copyWith(
              textTheme: shuttleTheme.textTheme.apply(fontFamily: 'Unifont'),
              primaryTextTheme: shuttleTheme.primaryTextTheme.apply(fontFamily: 'Unifont'),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Unifont'),
              child: rawShuttle,
            ),
          );
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return AnimatedBuilder(
            animation: curved,
            child: shuttle,
            builder: (context, child) {
              final double rotation = (1 - curved.value) * math.pi * 2;
              final Widget clippedChild = ClipRect(
                child: MediaQuery.withNoTextScaling(
                  child: RepaintBoundary(child: child ?? const SizedBox.shrink()),
                ),
              );
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(rotation),
                child: clippedChild,
              );
            },
          );
        },
        child: Material(
          color: Colors.transparent,
          child: cardBody,
        ),
      ),
    );
  }
}


/// 獎品面板
class _PrizePanel extends StatelessWidget {
  const _PrizePanel({
    required this.totalCollected,
    required this.requiredCount,
    required this.isComplete,
    required this.onRedeem,
  });

  final int totalCollected;
  final int requiredCount;
  final bool isComplete;
  final VoidCallback? onRedeem;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(
          color: isComplete ? PixelTheme.success : PixelTheme.border,
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isComplete ? '★' : '◇',
                style: TextStyle(
                  color: isComplete ? PixelTheme.success : PixelTheme.border,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isComplete ? 'PRIZE READY' : 'REQUIREMENTS',
                style: TextStyle(
                  color: PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isComplete
                ? '達成目標 ✓ 可到櫃台領取獎品'
                : '已收集 $totalCollected / $requiredCount\n還需 ${requiredCount - totalCollected} 張卡片',
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _PixelButton(
              onPressed: onRedeem,
              label: isComplete ? 'REDEEM' : 'LOCKED',
              fullWidth: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// 像素風按鈕
class _PixelButton extends StatefulWidget {
  const _PixelButton({
    required this.onPressed,
    required this.label,
    this.tooltip,
    this.fullWidth = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final String? tooltip;
  final bool fullWidth;

  @override
  State<_PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<_PixelButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    final Color color = enabled
        ? (widget.label == 'REDEEM' ? PixelTheme.success : PixelTheme.accent)
        : PixelTheme.textGray;
    final Color bgColor =
        enabled ? PixelTheme.bgDark : PixelTheme.bgMid.withValues(alpha: 0.5);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: Tooltip(
        message: widget.tooltip ?? '',
        child: Container(
          height: widget.fullWidth ? 44 : 36,
          width: widget.fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              if (_pressed && enabled)
                const BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(1, 1))
              else if (enabled)
                const BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(3, 3)),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontFamily: 'Unifont',
              fontWeight: FontWeight.w900,
              fontSize: widget.fullWidth ? 13 : 11,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

/// 像素風浮動按鈕
class _PixelFloatingButton extends StatefulWidget {
  const _PixelFloatingButton({
    required this.onPressed,
    required this.label,
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  State<_PixelFloatingButton> createState() => _PixelFloatingButtonState();
}

class _PixelFloatingButtonState extends State<_PixelFloatingButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: PixelTheme.accent,
          border: Border.all(color: PixelTheme.bgDark, width: 3),
          boxShadow: [
            if (_pressed && enabled)
              const BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(1, 1))
            else if (enabled)
              const BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(6, 6)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            color: PixelTheme.bgDark,
            fontFamily: 'Unifont',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
