import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/nfc_battle_api_client.dart';
import 'card_detail_page.dart';
import 'emoji_catalog.dart';
import 'offline_retry_banner.dart';
import 'pixel_card_face.dart';
import 'pixel_card_hero.dart';
import 'pixel_refresh_overlay.dart';
import 'pixel_theme.dart';

class UserCollectionPage extends StatefulWidget {
  const UserCollectionPage({
    super.key,
    required this.userId,
    required this.displayName,
    required this.emojiIcon,
    required this.rank,
    required this.score,
    this.scheme,
  });

  final String userId;
  final String displayName;
  final String emojiIcon;
  final int rank;
  final int score;
  final PixelScheme? scheme;

  @override
  State<UserCollectionPage> createState() => _UserCollectionPageState();
}

class _UserCollectionPageState extends State<UserCollectionPage> {
  final AuthService _authService = AuthService();
  final ValueNotifier<RefreshIndicatorStatus?> _refreshStatus =
      ValueNotifier<RefreshIndicatorStatus?>(null);
  final ValueNotifier<double> _refreshPullDistance = ValueNotifier<double>(0);

  bool _isLoading = true;
  bool _loadInFlight = false;
  bool _isOffline = false;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _collection;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshStatus.dispose();
    _refreshPullDistance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadInFlight) {
      return;
    }
    setState(() {
      _loadInFlight = true;
      _isLoading = true;
    });
    bool networkFailed = false;
    void recordError(Object error) {
      networkFailed = networkFailed || isNetworkConnectionError(error);
    }

    try {
      final List<Map<String, dynamic>?> results =
          await Future.wait<Map<String, dynamic>?>(
            <Future<Map<String, dynamic>?>>[
              _authService.fetchPublicUserProfile(
                widget.userId,
                onError: recordError,
              ),
              _authService.fetchUserCollection(
                widget.userId,
                onError: recordError,
              ),
            ],
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = results[0] ?? _profile;
        _collection = results[1] ?? _collection;
        _isOffline = networkFailed;
      });
    } finally {
      _loadInFlight = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(
      widget.scheme ?? PixelTheme.defaultScheme,
    );
    final String name = _displayName;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
        primaryTextTheme: Theme.of(
          context,
        ).primaryTextTheme.apply(fontFamily: 'Unifont'),
      ),
      child: Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: Text(
            context.l10n.tr('playerCollection', <String, Object?>{
              'name': name,
            }),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Stack(
          children: <Widget>[
            RefreshIndicator.noSpinner(
              onRefresh: _load,
              onStatusChange: _handleRefreshStatusChange,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleRefreshScrollNotification,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                  children: <Widget>[
                    if (_isOffline) ...<Widget>[
                      OfflineRetryBanner(
                        onRetry: _load,
                        isRetrying: _loadInFlight,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _PlayerHeader(
                      name: name,
                      userId: widget.userId,
                      avatarBase64: _profile?['pixel_avatar_base64'] as String?,
                      rank: widget.rank,
                      score: widget.score,
                      bio: _profile?['bio'] as String? ?? '',
                    ),
                    const SizedBox(height: 12),
                    if (_isLoading)
                      _MessagePanel(
                        icon: Icons.hourglass_top_rounded,
                        title: context.l10n.tr('loading'),
                      )
                    else if (_profile == null ||
                        (_collection == null && _isOffline))
                      _MessagePanel(
                        icon: Icons.wifi_off_rounded,
                        title: context.l10n.tr('profileUnavailable'),
                        actionLabel: context.l10n.tr('retry'),
                        onAction: _load,
                      )
                    else if (_collection == null)
                      _MessagePanel(
                        icon: Icons.lock_rounded,
                        title: context.l10n.tr('collectionUnavailable'),
                        body: context.l10n.tr('collectionUnavailableBody'),
                      )
                    else
                      _buildCollection(context),
                  ],
                ),
              ),
            ),
            PixelRefreshOverlay(
              statusListenable: _refreshStatus,
              pullDistanceListenable: _refreshPullDistance,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollection(BuildContext context) {
    final List<Map<String, dynamic>> cards =
        (_collection?['collection'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map(
              (Map<dynamic, dynamic> card) => card.map(
                (dynamic key, dynamic value) =>
                    MapEntry<String, dynamic>(key.toString(), value),
              ),
            )
            .toList(growable: false);

    return _PixelPanel(
      title: context.l10n.tr('collectedCards'),
      trailing: '${cards.length}',
      child: cards.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                context.l10n.tr('noCardsCollected'),
                textAlign: TextAlign.center,
                style: TextStyle(color: PixelTheme.textGray, height: 1.4),
              ),
            )
          : GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 53.98 / 85.60,
              ),
              itemCount: cards.length,
              itemBuilder: (BuildContext context, int index) {
                return _UserCollectionCard(
                  card: cards[index],
                  index: index,
                  heroTag: 'user-${widget.userId}-card-$index',
                  onOpen: () => _openCard(cards[index], index),
                );
              },
            ),
    );
  }

  Future<void> _openCard(Map<String, dynamic> card, int index) async {
    if (card['_profile_full'] != true) {
      return;
    }

    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: pixelCardHeroExpandDuration,
        reverseTransitionDuration: pixelCardHeroCollapseDuration,
        pageBuilder: (BuildContext context, _, _) => CardDetailPage(
          heroTag: 'user-${widget.userId}-card-$index',
          title: _cardTitle(card),
          attributeEmoji: _cardEmoji(card),
          attributeLabel: _cardAttribute(card),
          link: card['link'] as String? ?? '',
          description: card['bio'] as String? ?? '',
          uid: card['physical_id'] as String? ?? '',
          collectedAt: '',
          cardColor: _cardColor(card, index),
          imageBase64: card['pixel_avatar_base64'] as String?,
          showCollectionInfo: false,
        ),
        transitionsBuilder: (BuildContext context, animation, _, child) {
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  String get _displayName {
    return (_profile?['display_name'] as String?)?.trim().isNotEmpty == true
        ? _profile!['display_name'] as String
        : widget.displayName;
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

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({
    required this.name,
    required this.userId,
    required this.avatarBase64,
    required this.rank,
    required this.score,
    required this.bio,
  });

  final String name;
  final String userId;
  final String? avatarBase64;
  final int rank;
  final int score;
  final String bio;

  @override
  Widget build(BuildContext context) {
    final Uint8List? avatarBytes = _decodeImage(avatarBase64);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.accent, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: PixelTheme.bgDark,
                  border: Border.all(color: PixelTheme.border, width: 2),
                ),
                clipBehavior: Clip.hardEdge,
                child: avatarBytes == null
                    ? const _PixelQuestionImage()
                    : Image.memory(
                        avatarBytes,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.none,
                        gaplessPlayback: true,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: PixelTheme.textWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: PixelTheme.textGray,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    rank > 0 ? '#$rank' : '-',
                    style: TextStyle(
                      color: PixelTheme.accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${context.l10n.tr('scoreLabel')} $score',
                    style: TextStyle(
                      color: PixelTheme.accentBlue,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (bio.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(height: 1, color: PixelTheme.border),
            const SizedBox(height: 10),
            Text(
              bio.trim(),
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserCollectionCard extends StatefulWidget {
  const _UserCollectionCard({
    required this.card,
    required this.index,
    required this.heroTag,
    required this.onOpen,
  });

  final Map<String, dynamic> card;
  final int index;
  final String heroTag;
  final Future<void> Function() onOpen;

  @override
  State<_UserCollectionCard> createState() => _UserCollectionCardState();
}

class _UserCollectionCardState extends State<_UserCollectionCard>
    with SingleTickerProviderStateMixin {
  Uint8List? _imageBytes;
  late final AnimationController _textOpacityController;
  late final Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();
    _textOpacityController = AnimationController(
      vsync: this,
      duration: pixelCardThumbnailTextFadeDuration,
      value: 1,
    );
    _textOpacity = CurvedAnimation(
      parent: _textOpacityController,
      curve: Curves.easeInOut,
    );
    _imageBytes = _decodeImage(widget.card['pixel_avatar_base64'] as String?);
  }

  @override
  void didUpdateWidget(covariant _UserCollectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card['pixel_avatar_base64'] !=
        widget.card['pixel_avatar_base64']) {
      _imageBytes = _decodeImage(widget.card['pixel_avatar_base64'] as String?);
    }
  }

  Future<void> _handleTap() async {
    _textOpacityController.value = 0;
    await widget.onOpen();
    if (!mounted) {
      return;
    }
    await Future<void>.delayed(pixelCardHeroCollapseDuration);
    if (!mounted) {
      return;
    }
    _textOpacityController.forward(from: 0);
  }

  @override
  void dispose() {
    _textOpacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool unlocked = widget.card['_profile_full'] == true;
    final String title = _cardTitle(widget.card);
    final String attributeEmoji = _cardEmoji(widget.card);
    final String attributeLabel = _cardAttribute(widget.card);
    final Color cardColor = unlocked
        ? _cardColor(widget.card, widget.index)
        : const Color(0xFF71757A);

    return GestureDetector(
      onTap: unlocked ? _handleTap : null,
      child: Hero(
        tag: widget.heroTag,
        flightShuttleBuilder: unlocked
            ? pixelCardFlightShuttleBuilder(
                title: title,
                attributeEmoji: attributeEmoji,
                attributeLabel: attributeLabel,
                link: widget.card['link'] as String? ?? '',
                description: widget.card['bio'] as String? ?? '',
                cardColor: cardColor,
                imageBuilder: () => _cardImage(unlocked),
              )
            : null,
        child: Material(
          color: Colors.transparent,
          child: AnimatedBuilder(
            animation: _textOpacity,
            builder: (BuildContext context, Widget? child) {
              return PixelCardFace(
                title: title,
                attributeEmoji: attributeEmoji,
                attributeLabel: attributeLabel,
                cardColor: cardColor,
                showText: true,
                textOpacity: _textOpacity.value,
                textOpacityKey: const ValueKey<String>(
                  'user-collection-thumbnail-text-opacity',
                ),
                titleFontSize: 11,
                titleFontWeight: FontWeight.w900,
                attributeMaxLines: 3,
                stackAttributePairs: true,
                watermarkScale: 1.6,
                verticalHitconWatermark: true,
                verticalHitconScale:
                    ExpandedPixelCardStyle.thumbnailHitconScale,
                verticalHitconRightInsetFactor:
                    ExpandedPixelCardStyle.thumbnailHitconRightInsetFactor,
                verticalHitconBottomInsetFactor:
                    ExpandedPixelCardStyle.thumbnailHitconBottomInsetFactor,
                image: _cardImage(unlocked),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _cardImage(bool unlocked) {
    if (!unlocked) {
      return const _PixelQuestionImage();
    }
    final Uint8List? bytes = _imageBytes;
    if (bytes == null) {
      return Container(
        color: PixelTheme.bgDark,
        alignment: Alignment.center,
        child: Icon(Icons.person_rounded, color: PixelTheme.textGray, size: 34),
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.none,
      gaplessPlayback: true,
    );
  }
}

class _PixelQuestionImage extends StatelessWidget {
  const _PixelQuestionImage();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF24272B),
      child: CustomPaint(painter: const _PixelQuestionPainter()),
    );
  }
}

class _PixelQuestionPainter extends CustomPainter {
  const _PixelQuestionPainter();

  static const List<String> _pixels = <String>[
    '00111100',
    '01100110',
    '00000110',
    '00001100',
    '00011000',
    '00000000',
    '00011000',
    '00011000',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double pixel = (size.shortestSide / 12).floorToDouble();
    final double width = pixel * 8;
    final double height = pixel * 8;
    final Offset origin = Offset(
      ((size.width - width) / 2).roundToDouble(),
      ((size.height - height) / 2).roundToDouble(),
    );
    final Paint shadow = Paint()..color = const Color(0xFF3A3E43);
    final Paint foreground = Paint()..color = const Color(0xFFB5B8BC);

    for (int row = 0; row < _pixels.length; row += 1) {
      for (int column = 0; column < _pixels[row].length; column += 1) {
        if (_pixels[row][column] != '1') {
          continue;
        }
        final Rect rect = Rect.fromLTWH(
          origin.dx + column * pixel,
          origin.dy + row * pixel,
          pixel,
          pixel,
        );
        canvas.drawRect(rect.shift(Offset(pixel * 0.35, pixel * 0.35)), shadow);
        canvas.drawRect(rect, foreground);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelQuestionPainter oldDelegate) => false;
}

class _PixelPanel extends StatelessWidget {
  const _PixelPanel({
    required this.title,
    required this.trailing,
    required this.child,
  });

  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: PixelTheme.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                trailing,
                style: TextStyle(
                  color: PixelTheme.accentBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final Color accent = icon == Icons.wifi_off_rounded
        ? PixelTheme.warning
        : PixelTheme.accent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: accent, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        children: <Widget>[
          _PixelMessageGlyph(icon: icon, color: accent),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: TextStyle(color: PixelTheme.textGray, height: 1.4),
            ),
          ],
          if (onAction != null && actionLabel != null) ...<Widget>[
            const SizedBox(height: 14),
            Semantics(
              button: true,
              label: actionLabel,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('user-collection-pixel-retry'),
                  onTap: onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: PixelTheme.bgDark,
                      border: Border.all(color: accent, width: 2),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(3, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      actionLabel!,
                      style: TextStyle(
                        color: accent,
                        fontFamily: 'Unifont',
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PixelMessageGlyph extends StatelessWidget {
  const _PixelMessageGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: CustomPaint(painter: _PixelMessageGlyphPainter(icon, color)),
    );
  }
}

class _PixelMessageGlyphPainter extends CustomPainter {
  const _PixelMessageGlyphPainter(this.icon, this.color);

  final IconData icon;
  final Color color;

  static const List<String> _offline = <String>[
    '01111110',
    '11000011',
    '00111100',
    '01100110',
    '00011000',
    '00100100',
    '01000010',
    '10000001',
  ];

  static const List<String> _lock = <String>[
    '00111100',
    '01100110',
    '01100110',
    '11111111',
    '11011011',
    '11011011',
    '11111111',
    '00000000',
  ];

  static const List<String> _hourglass = <String>[
    '11111111',
    '01111110',
    '00111100',
    '00011000',
    '00100100',
    '01000010',
    '11111111',
    '00000000',
  ];

  List<String> get _pattern {
    if (icon == Icons.wifi_off_rounded) {
      return _offline;
    }
    if (icon == Icons.lock_rounded) {
      return _lock;
    }
    return _hourglass;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.shortestSide / 8;
    final Paint shadow = Paint()..color = Colors.black;
    final Paint foreground = Paint()..color = color;
    for (int y = 0; y < _pattern.length; y += 1) {
      for (int x = 0; x < _pattern[y].length; x += 1) {
        if (_pattern[y][x] != '1') {
          continue;
        }
        final Rect pixel = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        canvas.drawRect(pixel.shift(const Offset(1.5, 1.5)), shadow);
        canvas.drawRect(pixel, foreground);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelMessageGlyphPainter oldDelegate) {
    return oldDelegate.icon != icon || oldDelegate.color != color;
  }
}

String _cardTitle(Map<String, dynamic> card) {
  return card['card_title'] as String? ??
      card['display_name'] as String? ??
      card['user_id'] as String? ??
      '';
}

String _cardEmoji(Map<String, dynamic> card) {
  return card['attribute_emoji'] as String? ??
      card['emoji_icon'] as String? ??
      '';
}

String _cardAttribute(Map<String, dynamic> card) {
  final String emoji = _cardEmoji(card);
  final String label = normalizeEmojiAttributeLabel(
    emojiValue: emoji,
    rawLabel: card['attribute_label'] as String? ?? '',
  );
  if (label.isNotEmpty && !_isRoleLabel(label)) {
    return label;
  }
  return emojiNameLabelForValue(emoji).toUpperCase();
}

bool _isRoleLabel(String value) {
  switch (value.trim().toUpperCase()) {
    case 'ATTENDEE':
    case 'USER':
    case 'STAFF':
    case 'SPONSOR':
    case 'COMMUNITY':
      return true;
    default:
      return false;
  }
}

Color _cardColor(Map<String, dynamic> card, int index) {
  final Object? raw = card['card_color'];
  if (raw is int) {
    return Color(raw);
  }
  const List<Color> fallback = <Color>[
    Color(0xFF00AAFF),
    Color(0xFFFFAA00),
    Color(0xFFFF0099),
    Color(0xFF00E436),
    Color(0xFFFFFF00),
    Color(0xFF9900FF),
  ];
  return fallback[index % fallback.length];
}

Uint8List? _decodeImage(String? raw) {
  final String value = raw?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }
  final String payload = value.contains(',') ? value.split(',').last : value;
  try {
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}
