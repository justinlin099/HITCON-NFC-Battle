import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import 'my_card_editor_page.dart';
import 'card_detail_page.dart';
import 'emoji_catalog.dart';
import 'pixel_card_face.dart';
import 'pixel_card_hero.dart';
import 'pixel_theme.dart';
import 'score_board_page.dart';

import '../../services/auth_service.dart';
import '../../services/local_collection_store.dart';
import '../../services/local_profile_store.dart';
import '../../services/mock_api_service.dart';
import '../../services/nfc_deep_link_service.dart';
import '../../widgets/admin_mode_switch_button.dart';

class CardCollectionPage extends StatefulWidget {
  const CardCollectionPage({super.key});

  @override
  State<CardCollectionPage> createState() => _CardCollectionPageState();
}

class _CardCollectionPageState extends State<CardCollectionPage> {
  final AuthService _authService = AuthService();
  final LocalCollectionStore _localStore = LocalCollectionStore();
  final LocalProfileStore _localProfileStore = LocalProfileStore();
  final NfcDeepLinkService _deepLinks = NfcDeepLinkService.instance;
  final ScrollController _collectionScrollController = ScrollController();
  final PageController _pageController = PageController();
  final ValueNotifier<int> _selectedTab = ValueNotifier<int>(0);

  PixelScheme _selectedScheme = PixelTheme.defaultScheme;
  bool _appliedInitialTab = false;
  bool _showAdminModeSwitch = false;

  bool _isLoading = true;
  bool _isHandlingNfcRequest = false;
  bool _ntagReminderChecked = false;
  StreamSubscription<NfcScanRequest>? _nfcRequestSubscription;
  final ValueNotifier<RefreshIndicatorStatus?> _refreshStatus =
      ValueNotifier<RefreshIndicatorStatus?>(null);
  final ValueNotifier<double> _refreshPullDistance = ValueNotifier<double>(0);
  Map<String, dynamic>? _collectionData;
  Map<String, dynamic>? _stampMission;
  List<Map<String, dynamic>> _localCards = <Map<String, dynamic>>[];
  List<Map<String, String>> _featuredBooths = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    _nfcRequestSubscription = _deepLinks.requests.listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_consumePendingNfcRequest());
      });
    });
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumePendingNfcRequest());
      unawaited(_showNtagPairingReminderIfNeeded());
    });
  }

  @override
  void dispose() {
    _nfcRequestSubscription?.cancel();
    _collectionScrollController.dispose();
    _pageController.dispose();
    _selectedTab.dispose();
    _refreshStatus.dispose();
    _refreshPullDistance.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedInitialTab) {
      return;
    }
    _appliedInitialTab = true;

    final Object? args = ModalRoute.of(context)?.settings.arguments;
    _showAdminModeSwitch =
        _authService.isAdmin || (args is Map && args['fromAdminMode'] == true);
    if (args is Map && args['tab'] is int) {
      final int tab = args['tab'] as int;
      if (tab >= 0 && tab <= 2) {
        _selectedTab.value = tab;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(tab);
          }
        });
      }
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final String? userId = _authService.currentUserId;
      List<Map<String, dynamic>> localCards = <Map<String, dynamic>>[];
      if (userId != null) {
        localCards = await _localStore.loadCards(userId);
      }

      final Future<List<Map<String, String>>> boothFuture =
          MockApiService.getFeaturedBooths();
      final Future<Map<String, dynamic>?> collectionFuture = _authService
          .fetchCollectionRecords();
      final Future<Map<String, dynamic>?> stampMissionFuture = _authService
          .fetchStampMission();
      final List<Map<String, String>> boothResult = await boothFuture;
      final Map<String, dynamic>? collectionResult = await collectionFuture;
      final Map<String, dynamic>? stampMission = await stampMissionFuture;
      if (userId != null && collectionResult != null) {
        await _localStore.saveCollectionIndex(
          userId: userId,
          collection: collectionResult,
        );
        localCards = await _localStore.loadCards(userId);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _featuredBooths = boothResult;
        _collectionData = collectionResult;
        _stampMission = stampMission;
        _localCards = localCards;
      });
    } finally {
      if (mounted && showLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _cards {
    if (_localCards.isNotEmpty) {
      return _localCards;
    }
    final dynamic raw = _collectionData?['collection'];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return <Map<String, dynamic>>[];
  }

  int get _stampThreshold =>
      (_stampMission?['stamp_threshold'] as num?)?.toInt() ?? 10;

  int get _sponsorStampCount =>
      (_stampMission?['sponsor_count'] as num?)?.toInt() ?? 0;

  int get _communityStampCount =>
      (_stampMission?['community_count'] as num?)?.toInt() ?? 0;

  int get _stampProgress => _sponsorStampCount + _communityStampCount;

  bool get _isComplete => _stampMission?['eligible_for_stamp_prize'] == true;

  Future<void> _showNtagPairingReminderIfNeeded() async {
    if (_ntagReminderChecked || !mounted) {
      return;
    }
    _ntagReminderChecked = true;

    if (!_authService.isRegularUser || _deepLinks.hasPending) {
      return;
    }
    final String? userId = _authService.currentUserId;
    if (userId == null) {
      return;
    }

    final Map<String, dynamic> profile = await _localProfileStore.load(userId);
    final String pairedUid = (profile['paired_ntag_uid'] as String? ?? '')
        .trim();
    if (pairedUid.isNotEmpty || !mounted) {
      return;
    }

    final bool? goPair = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => const _NtagPairingReminderDialog(),
    );
    if (goPair == true && mounted) {
      await _selectTab(1);
    }
  }

  String _titleForCard(Map<String, dynamic> card) {
    return card['card_title'] as String? ??
        card['display_name'] as String? ??
        card['sponsor_stand_name'] as String? ??
        card['community_stand_name'] as String? ??
        card['tag_name'] as String? ??
        context.l10n.tr('unknown');
  }

  String _attributeEmojiForCard(Map<String, dynamic> card) {
    return card['attribute_emoji'] as String? ??
        card['emoji_icon'] as String? ??
        '*';
  }

  String _attributeLabelForCard(Map<String, dynamic> card) {
    final String emoji = _attributeEmojiForCard(card);
    final String label = normalizeEmojiAttributeLabel(
      emojiValue: emoji,
      rawLabel: card['attribute_label'] as String? ?? '',
    );
    if (label.trim().isNotEmpty && !_isRoleLabel(label)) {
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

  Color _cardColorForCard(Map<String, dynamic> card, int index) {
    final Object? raw = card['card_color'];
    if (raw is int) {
      return Color(raw);
    }
    if (raw is num) {
      return Color(raw.toInt());
    }
    if (raw is String) {
      final int? parsed = _parseColorString(raw);
      if (parsed != null) {
        return Color(parsed);
      }
    }
    return _PixelCard.colorForIndex(index);
  }

  int? _parseColorString(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('#')) {
      final String normalized = value.substring(1);
      return int.tryParse(
        normalized.length == 6 ? 'FF$normalized' : normalized,
        radix: 16,
      );
    }
    if (RegExp(r'^\d+$').hasMatch(value)) {
      return int.tryParse(value);
    }
    return int.tryParse(value, radix: 16);
  }

  Future<void> _selectTab(int index, {bool animate = true}) async {
    if (index < 0 || index > 2 || !mounted) {
      return;
    }
    if (!_pageController.hasClients) {
      _selectedTab.value = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(index);
        }
      });
      return;
    }
    if (animate) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(_selectedScheme);

    final ThemeData pixelTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
      primaryTextTheme: Theme.of(
        context,
      ).primaryTextTheme.apply(fontFamily: 'Unifont'),
    );

    return Theme(
      data: pixelTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Unifont'),
        child: Scaffold(
          backgroundColor: PixelTheme.bgDark,
          appBar: AppBar(
            leading: _showAdminModeSwitch
                ? AdminModeSwitchButton(
                    target: AdminModeTarget.adminTools,
                    color: PixelTheme.accent,
                  )
                : null,
            title: ValueListenableBuilder<int>(
              valueListenable: _selectedTab,
              builder: (BuildContext context, int tab, Widget? child) {
                final String title = switch (tab) {
                  1 => context.l10n.tr('myCardTab'),
                  2 => context.l10n.tr('scoreboardTab'),
                  _ => context.l10n.tr('appTitle'),
                };
                return Text(title);
              },
            ),
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
                tooltip: context.l10n.tr('paletteTooltip'),
                icon: _PixelThemeIcon(color: PixelTheme.accent),
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
                          child: Text(
                            context.l10n.tr('themeName', <String, Object?>{
                              'name': PixelTheme.labelOf(scheme),
                            }),
                          ),
                        ),
                      )
                      .toList();
                },
              ),
            ],
          ),
          body: PageView(
            controller: _pageController,
            onPageChanged: (int index) {
              _selectedTab.value = index;
            },
            children: [
              _KeepAlivePage(child: _buildCollectionBody()),
              _KeepAlivePage(
                child: MyCardEditorPage(
                  scheme: _selectedScheme,
                  onBackupRestored: _loadData,
                ),
              ),
              _KeepAlivePage(child: ScoreBoardPage(scheme: _selectedScheme)),
            ],
          ),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: PixelTheme.bgMid,
              indicatorColor: Colors.transparent,
              indicatorShape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
              labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    color: PixelTheme.accent,
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
              iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: PixelTheme.accent);
                }
                return IconThemeData(color: PixelTheme.textGray);
              }),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: _selectedTab,
              builder: (BuildContext context, int tab, Widget? child) {
                return NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (int index) {
                    unawaited(_selectTab(index));
                  },
                  destinations: [
                    NavigationDestination(
                      icon: _PixelNavIcon(
                        type: _PixelNavIconType.collection,
                        color: PixelTheme.textGray,
                      ),
                      selectedIcon: _PixelNavSelectedIcon(
                        type: _PixelNavIconType.collection,
                      ),
                      label: context.l10n.tr('collectionTab'),
                    ),
                    NavigationDestination(
                      icon: _PixelNavIcon(
                        type: _PixelNavIconType.edit,
                        color: PixelTheme.textGray,
                      ),
                      selectedIcon: _PixelNavSelectedIcon(
                        type: _PixelNavIconType.edit,
                      ),
                      label: context.l10n.tr('myCardTab'),
                    ),
                    NavigationDestination(
                      icon: _PixelNavIcon(
                        type: _PixelNavIconType.trophy,
                        color: PixelTheme.textGray,
                      ),
                      selectedIcon: _PixelNavSelectedIcon(
                        type: _PixelNavIconType.trophy,
                      ),
                      label: context.l10n.tr('scoreboardTab'),
                    ),
                  ],
                );
              },
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
          context.l10n.tr('loading'),
          style: TextStyle(
            color: PixelTheme.accent,
            fontFamily: 'Unifont',
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: () => _loadData(showLoading: false),
          onStatusChange: (RefreshIndicatorStatus? status) {
            _handleRefreshStatusChange(status);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleRefreshScrollNotification,
            child: CustomScrollView(
              controller: _collectionScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _HeroHeader(
                    totalCollected: _stampProgress,
                    sponsorCollected: _sponsorStampCount,
                    communityCollected: _communityStampCount,
                    prizeRequirement: _stampThreshold,
                    isComplete: _isComplete,
                    onRedeem: _isComplete ? _handleRedeem : null,
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedBoothHeaderDelegate(
                    child: _PinnedBoothStrip(booths: _featuredBooths),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 10,
                          childAspectRatio: 53.98 / 85.60,
                        ),
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final Map<String, dynamic> card = _cards[index];
                      final String title = _titleForCard(card);
                      final String attributeEmoji = _attributeEmojiForCard(
                        card,
                      );
                      final String attributeLabel = _attributeLabelForCard(
                        card,
                      );
                      final String link = (card['link'] as String? ?? '')
                          .trim();
                      final String description =
                          card['bio'] as String? ??
                          card['description'] as String? ??
                          '';
                      final Color cardColor = _cardColorForCard(card, index);
                      final String imageAsset = _PixelCard.imageAssetForIndex(
                        index,
                      );
                      final String heroTag = 'card-$index';
                      return _PixelCard(
                        title: title,
                        uid: card['physical_uid'] as String? ?? '',
                        collectedAt: card['collected_at'] as String? ?? '',
                        index: index,
                        cardColor: cardColor,
                        imageBase64: card['pixel_avatar_base64'] as String?,
                        attributeEmoji: attributeEmoji,
                        attributeLabel: attributeLabel,
                        heroTag: heroTag,
                        onTap: () async => _openCardDetail(
                          heroTag: heroTag,
                          title: title,
                          attributeEmoji: attributeEmoji,
                          attributeLabel: attributeLabel,
                          link: link,
                          description: description,
                          uid: card['physical_uid'] as String? ?? '',
                          collectedAt: card['collected_at'] as String? ?? '',
                          cardColor: cardColor,
                          imageAsset: imageAsset,
                          imageBase64: card['pixel_avatar_base64'] as String?,
                        ),
                      );
                    }, childCount: _cards.length),
                  ),
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
    );
  }

  void _handleRedeem() {
    _showNfcMessage(context.l10n.tr('prizeReady'));
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

  Future<void> _consumePendingNfcRequest() async {
    if (_isHandlingNfcRequest || !mounted) {
      return;
    }
    final NfcScanRequest? request = _deepLinks.takePending();
    if (request == null) {
      return;
    }
    final AppLocalizations l10n = context.l10n;

    final String? currentUserId = _authService.currentUserId;
    if (currentUserId == null || !_authService.isRegularUser) {
      return;
    }

    if (request.hasUserIdMismatch) {
      await _showIosRescanPrompt(
        expectedUserId: request.expectedUserId!,
        mismatch: true,
      );
      return;
    }

    if (request.userId == currentUserId) {
      _returnToCollectionRoute();
      await _selectTab(1);
      return;
    }

    if (request.physicalUid.isEmpty) {
      switch (request.launchEvidence) {
        case NfcLaunchEvidence.directLink:
          await _recordPhishing(request.userId);
        case NfcLaunchEvidence.unknown:
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            await _showIosRescanPrompt(
              expectedUserId: request.userId,
              reportDirectLinkOnDecline: true,
            );
          } else {
            _showNfcMessage(l10n.tr('nfcUidMissing'));
          }
        case NfcLaunchEvidence.physicalTag:
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            await _showIosRescanPrompt(expectedUserId: request.userId);
          } else {
            _showNfcMessage(l10n.tr('nfcUidMissing'));
          }
      }
      return;
    }

    _isHandlingNfcRequest = true;
    _returnToCollectionRoute();
    try {
      final Map<String, dynamic>? scanResult = await _authService
          .scanCollection(
            targetUserId: request.userId,
            scannedNfcUid: request.physicalUid,
          );
      if (scanResult == null) {
        _showNfcMessage(l10n.tr('collectionFailed'));
        return;
      }
      final Map<String, dynamic> scanData = Map<String, dynamic>.from(
        scanResult['data'] as Map? ?? <String, dynamic>{},
      );
      final bool firstTimeCollected =
          scanData['first_time_collected'] as bool? ?? false;

      await _localStore.saveScanResult(
        userId: currentUserId,
        scannedUid: request.physicalUid,
        scanResult: scanResult,
      );
      final Future<Map<String, dynamic>?> collectionFuture = _authService
          .fetchCollectionRecords();
      final Future<Map<String, dynamic>?> stampMissionFuture = _authService
          .fetchStampMission();
      final Map<String, dynamic>? collection = await collectionFuture;
      final Map<String, dynamic>? stampMission = await stampMissionFuture;
      if (collection != null) {
        await _localStore.saveCollectionIndex(
          userId: currentUserId,
          collection: collection,
        );
      }
      final List<Map<String, dynamic>> cards = await _localStore.loadCards(
        currentUserId,
      );
      int cardIndex = cards.indexWhere((Map<String, dynamic> card) {
        final String owner =
            (card['owner'] as String? ?? card['user_id'] as String? ?? '')
                .trim();
        return owner == request.userId;
      });
      if (cardIndex < 0) {
        cardIndex = cards.indexWhere(
          (Map<String, dynamic> card) =>
              (card['physical_uid'] as String? ?? '').toUpperCase() ==
              request.physicalUid.toUpperCase(),
        );
      }
      if (cardIndex < 0 || !mounted) {
        _showNfcMessage(l10n.tr('collectionPreviewFailed'));
        return;
      }

      setState(() {
        _collectionData = collection ?? _collectionData;
        _stampMission = stampMission ?? _stampMission;
        _localCards = cards;
      });
      await _selectTab(0);
      await WidgetsBinding.instance.endOfFrame;
      await _scrollCardIntoView(cardIndex);
      if (mounted) {
        await _openScannedCard(
          cards[cardIndex],
          cardIndex,
          playRevealEffect: firstTimeCollected,
        );
      }
    } finally {
      _isHandlingNfcRequest = false;
      if (_deepLinks.hasPending) {
        unawaited(_consumePendingNfcRequest());
      }
    }
  }

  Future<void> _showIosRescanPrompt({
    required String expectedUserId,
    bool mismatch = false,
    bool reportDirectLinkOnDecline = false,
  }) async {
    if (!mounted) {
      return;
    }
    final bool? shouldScan = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _NfcRescanDialog(
        mismatch: mismatch,
        showDirectLinkChoice: reportDirectLinkOnDecline,
      ),
    );
    if (shouldScan == true) {
      await _deepLinks.requestPhysicalRescan(expectedUserId);
    } else {
      _deepLinks.cancelPhysicalRescan();
      if (reportDirectLinkOnDecline) {
        await _recordPhishing(expectedUserId);
      }
    }
  }

  Future<void> _recordPhishing(String attackerUserId) async {
    if (_isHandlingNfcRequest) {
      return;
    }
    _isHandlingNfcRequest = true;
    _returnToCollectionRoute();
    try {
      final bool recorded = await _authService.recordPhishing(
        attackerUserId: attackerUserId,
      );
      if (!mounted) {
        return;
      }
      _showNfcMessage(
        context.l10n.tr(recorded ? 'phishingRecorded' : 'phishingRecordFailed'),
      );
    } finally {
      _isHandlingNfcRequest = false;
      if (_deepLinks.hasPending) {
        unawaited(_consumePendingNfcRequest());
      }
    }
  }

  void _returnToCollectionRoute() {
    Navigator.of(context).popUntil(
      (Route<dynamic> route) =>
          route.settings.name == '/collection' || route.isFirst,
    );
  }

  void _showNfcMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scrollCardIntoView(int index) async {
    if (!_collectionScrollController.hasClients || !mounted) {
      return;
    }
    final double availableWidth = MediaQuery.sizeOf(context).width - 32;
    final double cardWidth = availableWidth / 3;
    final double cardHeight = cardWidth / (53.98 / 85.60);
    final int row = index ~/ 3;
    final double targetOffset = (210 + row * (cardHeight + 10) - 90).clamp(
      0.0,
      _collectionScrollController.position.maxScrollExtent,
    );
    if ((_collectionScrollController.offset - targetOffset).abs() < 8) {
      return;
    }
    await _collectionScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _openScannedCard(
    Map<String, dynamic> card,
    int index, {
    required bool playRevealEffect,
  }) {
    final String uid = card['physical_uid'] as String? ?? '';
    return _openCardDetail(
      heroTag: 'card-$index',
      title: _titleForCard(card),
      attributeEmoji: _attributeEmojiForCard(card),
      attributeLabel: _attributeLabelForCard(card),
      link: (card['link'] as String? ?? '').trim(),
      description:
          card['bio'] as String? ?? card['description'] as String? ?? '',
      uid: uid,
      collectedAt: card['collected_at'] as String? ?? '',
      cardColor: _cardColorForCard(card, index),
      imageAsset: _PixelCard.imageAssetForIndex(index),
      imageBase64: card['pixel_avatar_base64'] as String?,
      playRevealEffect: playRevealEffect,
    );
  }

  Future<void> _openCardDetail({
    required String heroTag,
    required String title,
    required String attributeEmoji,
    required String attributeLabel,
    required String link,
    required String description,
    required String uid,
    required String collectedAt,
    required Color cardColor,
    required String imageAsset,
    String? imageBase64,
    bool playRevealEffect = false,
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
            description: description,
            uid: uid,
            collectedAt: collectedAt,
            cardColor: cardColor,
            imageAsset: imageAsset,
            imageBase64: imageBase64,
            playRevealEffect: playRevealEffect,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin<_KeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}

/// 英雄區塊 - 顯示進度和統計
class _NtagPairingReminderDialog extends StatelessWidget {
  const _NtagPairingReminderDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(color: PixelTheme.accent, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(6, 6)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.tr('ntagPairingTitle'),
              style: TextStyle(
                color: PixelTheme.accent,
                fontFamily: 'Unifont',
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.tr('ntagPairingReminder'),
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontFamily: 'Unifont',
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PixelButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    label: context.l10n.tr('later'),
                    fullWidth: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PixelButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    label: context.l10n.tr('goPair'),
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NfcRescanDialog extends StatelessWidget {
  const _NfcRescanDialog({
    required this.mismatch,
    required this.showDirectLinkChoice,
  });

  final bool mismatch;
  final bool showDirectLinkChoice;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(
            color: mismatch ? PixelTheme.warning : PixelTheme.accent,
            width: 3,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(6, 6)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.tr(
                mismatch ? 'cardMismatchTitle' : 'scanAgainTitle',
              ),
              style: TextStyle(
                color: mismatch ? PixelTheme.warning : PixelTheme.accent,
                fontFamily: 'Unifont',
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.tr(mismatch ? 'cardMismatchBody' : 'iosRescanBody'),
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontFamily: 'Unifont',
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PixelButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    label: context.l10n.tr(
                      showDirectLinkChoice ? 'openedLink' : 'cancel',
                    ),
                    fullWidth: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PixelButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    label: context.l10n.tr('startScan'),
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
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

class _PixelThemeIcon extends StatelessWidget {
  const _PixelThemeIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: CustomPaint(painter: _PixelThemeIconPainter(color: color)),
    );
  }
}

class _PixelThemeIconPainter extends CustomPainter {
  const _PixelThemeIconPainter({required this.color});

  final Color color;

  static const List<String> _outline = <String>[
    '00001111100000',
    '00011111111000',
    '00111111111100',
    '0111AA11111110',
    '1111AA11BB1111',
    '11111111BB1111',
    '111CC111111111',
    '111CC111111111',
    '01111111100110',
    '00111111000010',
    '00011111000110',
    '00001111111100',
    '00000111111000',
    '00000011100000',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final int columns = _outline.first.length;
    final int rows = _outline.length;
    final double cell = size.shortestSide / columns;
    final double left = (size.width - cell * columns) / 2;
    final double top = (size.height - cell * rows) / 2;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int y = 0; y < _outline.length; y += 1) {
      for (int x = 0; x < _outline[y].length; x += 1) {
        final String pixel = _outline[y][x];
        if (pixel == '0') {
          continue;
        }
        paint.color = switch (pixel) {
          'A' => PixelTheme.warning,
          'B' => PixelTheme.accentBlue,
          'C' => PixelTheme.textWhite,
          _ => color,
        };
        canvas.drawRect(
          Rect.fromLTWH(left + x * cell, top + y * cell, cell, cell),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PixelThemeIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

enum _PixelNavIconType { collection, edit, trophy }

class _PixelNavIcon extends StatelessWidget {
  const _PixelNavIcon({required this.type, required this.color});

  final _PixelNavIconType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: CustomPaint(
        painter: _PixelNavIconPainter(type: type, color: color),
      ),
    );
  }
}

class _PixelNavSelectedIcon extends StatelessWidget {
  const _PixelNavSelectedIcon({required this.type});

  final _PixelNavIconType type;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-2, -2),
      child: Container(
        width: 38,
        height: 34,
        decoration: BoxDecoration(
          color: PixelTheme.bgDark,
          border: Border.all(color: PixelTheme.accent, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
          ],
        ),
        alignment: Alignment.center,
        child: _PixelNavIcon(type: type, color: PixelTheme.accent),
      ),
    );
  }
}

class _PixelNavIconPainter extends CustomPainter {
  const _PixelNavIconPainter({required this.type, required this.color});

  final _PixelNavIconType type;
  final Color color;

  static const Map<_PixelNavIconType, List<String>> _patterns =
      <_PixelNavIconType, List<String>>{
        _PixelNavIconType.collection: <String>[
          '01110000',
          '01000000',
          '01011100',
          '01010000',
          '00010111',
          '00010101',
          '00000101',
          '00000111',
        ],
        _PixelNavIconType.edit: <String>[
          '00111100',
          '01111110',
          '01000010',
          '01011010',
          '01011010',
          '01000010',
          '01111110',
          '00111100',
        ],
        _PixelNavIconType.trophy: <String>[
          '00111100',
          '11111111',
          '10111101',
          '10111101',
          '01111110',
          '00111100',
          '00011000',
          '00111100',
        ],
      };

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final List<String> pattern = _patterns[type]!;
    final int columns = pattern.first.length;
    final int rows = pattern.length;
    final double cell = size.shortestSide / columns;
    final double top = (size.height - rows * cell) / 2;
    final double left = (size.width - columns * cell) / 2;

    for (int y = 0; y < pattern.length; y += 1) {
      for (int x = 0; x < pattern[y].length; x += 1) {
        if (pattern[y][x] != '1') {
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
  bool shouldRepaint(_PixelNavIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.totalCollected,
    required this.sponsorCollected,
    required this.communityCollected,
    required this.prizeRequirement,
    required this.isComplete,
    required this.onRedeem,
  });

  final int totalCollected;
  final int sponsorCollected;
  final int communityCollected;
  final int prizeRequirement;
  final bool isComplete;
  final VoidCallback? onRedeem;

  @override
  Widget build(BuildContext context) {
    final double progress = prizeRequirement <= 0
        ? 0
        : (totalCollected / prizeRequirement).clamp(0.0, 1.0);

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr('collectionHeader'),
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
                      context.l10n.tr(isComplete ? 'complete' : 'inProgress'),
                      style: TextStyle(
                        color: isComplete
                            ? PixelTheme.success
                            : PixelTheme.accentBlue,
                        fontFamily: 'Unifont',
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PixelButton(
                onPressed: onRedeem,
                label: context.l10n.tr(isComplete ? 'redeem' : 'locked'),
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
                _StatItem(
                  label: context.l10n.tr('sponsorStamps'),
                  value: '$sponsorCollected',
                ),
                _StatItem(
                  label: context.l10n.tr('communityStamps'),
                  value: '$communityCollected',
                ),
                _StatItem(
                  label: context.l10n.tr('need'),
                  value: '$prizeRequirement',
                ),
                _StatItem(
                  label: context.l10n.tr('remain'),
                  value: '${(prizeRequirement - totalCollected).clamp(0, 999)}',
                ),
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
            isComplete
                ? context.l10n.tr('prizeReady')
                : context.l10n.tr('collectMoreStamps', <String, Object?>{
                    'count': (prizeRequirement - totalCollected).clamp(0, 999),
                  }),
            style: TextStyle(
              color: isComplete ? PixelTheme.success : PixelTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Unifont',
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
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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
      ),
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
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
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 0,
                      offset: Offset(3, 3),
                    ),
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
                        booth['icon'] ?? '*',
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
    required this.cardColor,
    required this.imageBase64,
    required this.attributeEmoji,
    required this.attributeLabel,
    required this.heroTag,
    required this.onTap,
  });

  final String title;
  final String uid;
  final String collectedAt;
  final int index;
  final Color cardColor;
  final String? imageBase64;
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

  static String imageAssetForIndex(int seed) {
    const List<String> assets = <String>[
      'assets/images/mock_card_circuit.png',
      'assets/images/mock_card_chip.png',
      'assets/images/mock_card_portal.png',
      'assets/images/mock_card_lock.png',
      'assets/images/mock_card_satellite.png',
      'assets/images/mock_card_skull.png',
      'assets/images/mock_card_terminal.png',
      'assets/images/mock_card_badge.png',
    ];
    return assets[seed % assets.length];
  }

  @override
  State<_PixelCard> createState() => _PixelCardState();
}

class _PixelCardState extends State<_PixelCard> {
  bool _showText = true;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = _decodeImageBytes(widget.imageBase64);
  }

  @override
  void didUpdateWidget(covariant _PixelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBase64 != widget.imageBase64) {
      _imageBytes = _decodeImageBytes(widget.imageBase64);
    }
  }

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
    final Widget image = _cardImage();
    final Widget cardBody = PixelCardFace(
      title: widget.title,
      attributeEmoji: widget.attributeEmoji,
      attributeLabel: widget.attributeLabel,
      cardColor: widget.cardColor,
      showText: _showText,
      titleFontSize: 11,
      titleFontWeight: FontWeight.w900,
      attributeMaxLines: 3,
      stackAttributePairs: true,
      watermarkScale: 1.6,
      image: image,
    );

    return GestureDetector(
      onTap: _handleTap,
      child: Hero(
        tag: widget.heroTag,
        flightShuttleBuilder: pixelCardFlightShuttleBuilder(
          title: widget.title,
          attributeEmoji: widget.attributeEmoji,
          attributeLabel: widget.attributeLabel,
          cardColor: widget.cardColor,
          imageBuilder: _cardImage,
        ),
        child: Material(color: Colors.transparent, child: cardBody),
      ),
    );
  }

  Widget _cardImage() {
    final Uint8List? bytes = _imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
        gaplessPlayback: true,
      );
    }
    return Container(
      color: PixelTheme.bgDark,
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: PixelTheme.accent, size: 28),
    );
  }

  Uint8List? _decodeImageBytes(String? raw) {
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
}

/// 獎品面板
/// 像素風按鈕
class _PixelButton extends StatefulWidget {
  const _PixelButton({
    required this.onPressed,
    required this.label,
    this.fullWidth = false,
  });

  final VoidCallback? onPressed;
  final String label;
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
    final Color bgColor = enabled
        ? PixelTheme.bgDark
        : PixelTheme.bgMid.withValues(alpha: 0.5);

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
        message: widget.label,
        child: Container(
          height: widget.fullWidth ? 44 : 36,
          width: widget.fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              if (_pressed && enabled)
                const BoxShadow(
                  color: Colors.black,
                  blurRadius: 0,
                  offset: Offset(1, 1),
                )
              else if (enabled)
                const BoxShadow(
                  color: Colors.black,
                  blurRadius: 0,
                  offset: Offset(3, 3),
                ),
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
  const _PixelFloatingButton({required this.onPressed, required this.label});

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
              const BoxShadow(
                color: Colors.black,
                blurRadius: 0,
                offset: Offset(1, 1),
              )
            else if (enabled)
              const BoxShadow(
                color: Colors.black,
                blurRadius: 0,
                offset: Offset(6, 6),
              ),
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
