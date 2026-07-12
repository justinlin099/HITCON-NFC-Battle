import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import 'card_detail_page.dart';
import 'emoji_catalog.dart';
import 'pixel_card_face.dart';
import 'pixel_card_hero.dart';
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

  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _collection;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });
    final List<Map<String, dynamic>?> results =
        await Future.wait<Map<String, dynamic>?>(
          <Future<Map<String, dynamic>?>>[
            _authService.fetchPublicUserProfile(widget.userId),
            _authService.fetchUserCollection(widget.userId),
          ],
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = results[0];
      _collection = results[1];
      _isLoading = false;
    });
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
        body: RefreshIndicator(
          onRefresh: _load,
          color: PixelTheme.accent,
          backgroundColor: PixelTheme.bgMid,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
            children: <Widget>[
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
              else if (_profile == null)
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
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 300),
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

class _UserCollectionCardState extends State<_UserCollectionCard> {
  Uint8List? _imageBytes;
  bool _showText = true;

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _showText = false;
    });
    await widget.onOpen();
    if (!mounted) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _showText = true;
      });
    }
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
                cardColor: cardColor,
                imageBuilder: () => _cardImage(unlocked),
              )
            : null,
        child: Material(
          color: Colors.transparent,
          child: PixelCardFace(
            title: title,
            attributeEmoji: attributeEmoji,
            attributeLabel: attributeLabel,
            cardColor: cardColor,
            showText: _showText,
            titleFontSize: 11,
            titleFontWeight: FontWeight.w900,
            attributeMaxLines: 3,
            stackAttributePairs: true,
            watermarkScale: 1.6,
            image: _cardImage(unlocked),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.border, width: 2),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: PixelTheme.accent, size: 36),
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
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
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
