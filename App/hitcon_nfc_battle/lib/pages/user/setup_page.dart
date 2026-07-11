import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/local_profile_store.dart';
import '../../services/setup_service.dart';
import 'emoji_catalog.dart';
import 'https_link_input.dart';
import 'my_card_editor_page.dart';
import 'ntag_pairing_page.dart';
import 'pixel_card_face.dart';
import 'pixel_theme.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final AuthService _authService = AuthService();
  final LocalProfileStore _localProfileStore = LocalProfileStore();
  final SetupService _setupService = SetupService();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();

  static const int _maxEmojiSelection = 3;
  static const List<Color> _colorOptions = <Color>[
    Color(0xFFFFD700),
    Color(0xFFFFAA00),
    Color(0xFFE63946),
    Color(0xFFFF0099),
    Color(0xFF9D4EDD),
    Color(0xFF5E7BFF),
    Color(0xFF29ADFF),
    Color(0xFF00E436),
    Color(0xFF80FFDB),
    Color(0xFFF4A261),
    Color(0xFF6B7280),
    Color(0xFFFFFFFF),
  ];

  int _stepIndex = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isScanning = false;
  bool _tagPaired = false;
  String _status = '';
  String _tagUid = '';
  String _attributeEmoji = '\u2728\uD83D\uDCBB\uD83D\uDD25';
  String _attributeLabel = 'MAGIC / TECH / FIRE';
  Color _cardColor = const Color(0xFFFFD700);
  Uint8List? _avatarBytes;
  String? _avatarBase64;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_refreshPreview);
    _bioController.addListener(_refreshPreview);
    _linkController.addListener(_refreshPreview);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final Map<String, dynamic>? profile = await _authService.fetchUserProfile();
    if (!mounted) {
      return;
    }

    final String displayName = profile?['display_name'] as String? ?? '';
    _displayNameController.text = _isGeneratedMockName(displayName)
        ? ''
        : displayName;
    _bioController.text = profile?['bio'] as String? ?? '';
    final String loadedLink = profile?['link'] as String? ?? '';
    _linkController.text = validateHttpsLink(loadedLink) == null
        ? httpsLinkBody(loadedLink)
        : '';
    _attributeEmoji = profile?['attribute_emoji'] as String? ?? _attributeEmoji;
    _attributeLabel = _attributeNamesForEmoji(_attributeEmoji);
    _avatarBase64 = profile?['pixel_avatar_base64'] as String?;
    _avatarBytes = _decodeAvatar(_avatarBase64);

    final Object? rawColor = profile?['card_color'];
    if (rawColor is int) {
      _cardColor = Color(rawColor);
    }

    setState(() {
      _isLoading = false;
      _status = context.l10n.tr('setupStarted');
    });
  }

  Uint8List? _decodeAvatar(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  bool _isGeneratedMockName(String value) {
    final String normalized = value.trim().toLowerCase();
    return normalized == 'player_test' ||
        normalized == 'admin_test' ||
        normalized == 'staff_test';
  }

  bool get _hasName => _displayNameController.text.trim().isNotEmpty;

  void _refreshPreview() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _drawImage() async {
    final Uint8List? bytes = await openBlankCardPixelEditor(
      context,
      cardColor: _cardColor,
    );
    if (bytes == null || !mounted) {
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarBase64 = base64Encode(bytes);
      _status = context.l10n.tr('imageUpdated');
    });
  }

  Future<void> _importImage() async {
    final Uint8List? bytes = await openImportedCardPixelEditor(
      context,
      cardColor: _cardColor,
    );
    if (bytes == null || !mounted) {
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarBase64 = base64Encode(bytes);
      _status = context.l10n.tr('imageImported');
    });
  }

  Future<bool> _saveProfile({bool quiet = false}) async {
    if (_isSaving) {
      return false;
    }

    if (validateHttpsLink(_linkController.text) != null) {
      final String message = context.l10n.tr('invalidHttpsLink');
      setState(() {
        _status = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontFamily: 'Unifont')),
          backgroundColor: PixelTheme.warning,
        ),
      );
      return false;
    }

    setState(() {
      _isSaving = true;
      _status = quiet ? _status : context.l10n.tr('savingProfile');
    });

    final Map<String, dynamic> updates = <String, dynamic>{
      'display_name': _displayNameController.text.trim(),
      'bio': _bioController.text.trim(),
      'link': buildHttpsLink(_linkController.text),
      'attribute_emoji': _attributeEmoji,
      'attribute_label': _attributeLabel,
      'card_color': _colorInt(_cardColor),
      if (_avatarBase64 != null) 'pixel_avatar_base64': _avatarBase64,
      if (_tagPaired && _tagUid.isNotEmpty) 'paired_ntag_uid': _tagUid,
    };

    final String? userId = _authService.currentUserId;
    if (userId != null) {
      await _localProfileStore.save(userId, updates);
    }

    final bool success = await _authService.updateUserProfile(updates);

    if (!mounted) {
      return true;
    }

    setState(() {
      _isSaving = false;
      _status = context.l10n.tr(success ? 'profileSaved' : 'profileSaveFailed');
    });
    return true;
  }

  Future<void> _startPairing() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
      _status = context.l10n.tr('openingPairing');
    });

    final String? uid = await openNtagPairingScanPage(context);
    if (!mounted) {
      return;
    }

    setState(() {
      _isScanning = false;
      if (uid == null || uid.isEmpty) {
        _status = context.l10n.tr('pairingIncomplete');
        return;
      }
      _tagUid = uid;
      _tagPaired = true;
      _status = context.l10n.tr('pairingComplete');
    });
  }

  Future<void> _finishSetup() async {
    if (!_hasName) {
      setState(() {
        _stepIndex = _SetupStep.name.index;
        _status = context.l10n.tr('nameRequired');
      });
      return;
    }

    if (!await _saveProfile(quiet: true)) {
      return;
    }
    final String? userId = _authService.currentUserId;
    if (userId != null) {
      await _setupService.markComplete(userId);
    }

    if (!mounted) {
      return;
    }
    unawaited(
      Navigator.of(
        context,
      ).pushReplacementNamed('/collection', arguments: <String, int>{'tab': 1}),
    );
  }

  Future<void> _nextStep() async {
    if (_SetupStep.values[_stepIndex] == _SetupStep.name && !_hasName) {
      setState(() {
        _status = context.l10n.tr('nameRequired');
      });
      return;
    }

    if (!await _saveProfile(quiet: true)) {
      return;
    }
    if (!mounted) {
      return;
    }

    if (_stepIndex < _SetupStep.values.length - 1) {
      setState(() {
        _stepIndex += 1;
        _status = context.l10n.tr(_SetupStep.values[_stepIndex].hintKey);
      });
    } else {
      unawaited(_finishSetup());
    }
  }

  void _previousStep() {
    if (_stepIndex == 0) {
      return;
    }
    setState(() {
      _stepIndex -= 1;
      _status = context.l10n.tr(_SetupStep.values[_stepIndex].hintKey);
    });
  }

  void _toggleEmoji(EmojiOption option) {
    final List<EmojiOption> selected = _selectedEmojiOptions();
    final bool exists = selected.any(
      (EmojiOption current) => current.emoji == option.emoji,
    );
    if (exists) {
      selected.removeWhere(
        (EmojiOption current) => current.emoji == option.emoji,
      );
    } else {
      if (selected.length >= _maxEmojiSelection) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.tr('maxThreeAttributes')),
            backgroundColor: PixelTheme.bgMid,
            duration: const Duration(milliseconds: 1400),
          ),
        );
        return;
      }
      selected.add(option);
    }

    setState(() {
      _attributeEmoji = selected.map((EmojiOption item) => item.emoji).join();
      _attributeLabel = _attributeNamesForEmoji(_attributeEmoji);
    });
  }

  List<EmojiOption> _selectedEmojiOptions() {
    final List<String> selectedValues = selectedEmojiValuesFromCatalog(
      _attributeEmoji,
    ).take(_maxEmojiSelection).toList(growable: false);
    final List<EmojiOption> selected = <EmojiOption>[];
    for (final String value in selectedValues) {
      final String label = emojiNameFor(value);
      selected.add(EmojiOption(value, label));
    }
    return selected;
  }

  String _attributeNamesForEmoji(String value) {
    final List<String> names = selectedEmojiValuesFromCatalog(
      value,
    ).take(_maxEmojiSelection).map(emojiNameFor).toList(growable: false);
    return names.isEmpty ? 'EMOJI' : names.join(' / ');
  }

  int _colorInt(Color color) {
    final int alpha = (color.a * 255).round() & 0xFF;
    final int red = (color.r * 255).round() & 0xFF;
    final int green = (color.g * 255).round() & 0xFF;
    final int blue = (color.b * 255).round() & 0xFF;
    return alpha << 24 | red << 16 | green << 8 | blue;
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_refreshPreview);
    _bioController.removeListener(_refreshPreview);
    _linkController.removeListener(_refreshPreview);
    _displayNameController.dispose();
    _bioController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    final ThemeData theme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
    );
    final _SetupStep step = _SetupStep.values[_stepIndex];
    final bool isNameStep = step == _SetupStep.name;
    final bool canLeaveStep = !isNameStep || _hasName;
    final String nextLabel = context.l10n.tr(
      step == _SetupStep.pairTag && !_tagPaired ? 'skip' : 'next',
    );

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          title: Text(context.l10n.tr('setupTitle')),
          centerTitle: true,
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          elevation: 0,
        ),
        body: _isLoading
            ? Center(
                child: Text(
                  context.l10n.tr('loading'),
                  style: TextStyle(
                    color: PixelTheme.accent,
                    fontFamily: 'Unifont',
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : SafeArea(
                child: Column(
                  children: [
                    _ProgressHeader(
                      step: _stepIndex + 1,
                      total: _SetupStep.values.length,
                      title: context.l10n.tr(step.titleKey),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: SingleChildScrollView(
                          key: ValueKey<_SetupStep>(step),
                          padding: const EdgeInsets.all(16),
                          child: _buildStep(step),
                        ),
                      ),
                    ),
                    _FooterControls(
                      status: _status,
                      canGoBack: _stepIndex > 0,
                      canGoNext: canLeaveStep,
                      nextLabel: nextLabel,
                      onBack: _previousStep,
                      onNext: () => unawaited(_nextStep()),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStep(_SetupStep step) {
    switch (step) {
      case _SetupStep.name:
        return _PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIntro(
                label: context.l10n.tr('name'),
                title: context.l10n.tr('setupName'),
              ),
              const SizedBox(height: 16),
              _PixelTextField(
                controller: _displayNameController,
                label: context.l10n.tr('displayName'),
                maxLength: 24,
              ),
            ],
          ),
        );
      case _SetupStep.image:
        return _PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIntro(
                label: context.l10n.tr('image'),
                title: context.l10n.tr('setupImage'),
              ),
              if (_avatarBytes != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: SizedBox.square(
                    dimension: 220,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: PixelTheme.bgDark,
                        border: Border.all(color: _cardColor, width: 3),
                      ),
                      child: _avatarImage(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _PixelButton(
                      label: context.l10n.tr('drawImage'),
                      onPressed: _drawImage,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PixelButton(
                      label: context.l10n.tr('importImage'),
                      onPressed: _importImage,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case _SetupStep.bio:
        return _PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIntro(
                label: context.l10n.tr('bio'),
                title: context.l10n.tr('setupBio'),
              ),
              const SizedBox(height: 16),
              _PixelTextField(
                controller: _bioController,
                label: context.l10n.tr('bio'),
                maxLines: 5,
                maxLength: 100,
              ),
            ],
          ),
        );
      case _SetupStep.link:
        return _PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIntro(
                label: context.l10n.tr('link'),
                title: context.l10n.tr('setupLink'),
              ),
              const SizedBox(height: 16),
              _PixelTextField(
                controller: _linkController,
                label: context.l10n.tr('url'),
                maxLines: 1,
                maxLength: 120,
                prefixText: httpsLinkPrefix,
                keyboardType: TextInputType.url,
                inputFormatters: const <TextInputFormatter>[
                  HttpsLinkInputFormatter(),
                ],
              ),
            ],
          ),
        );
      case _SetupStep.attribute:
        final List<EmojiOption> selected = _selectedEmojiOptions();
        return _PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIntro(
                label: context.l10n.tr('attribute'),
                title: context.l10n.tr('setupAttribute'),
              ),
              const SizedBox(height: 12),
              _SelectedEmojiBar(selected: selected, onRemove: _toggleEmoji),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: emojiOptionsCatalog
                    .map((EmojiOption option) {
                      final bool isSelected = selected.any(
                        (EmojiOption item) => item.emoji == option.emoji,
                      );
                      return _EmojiChoice(
                        option: option,
                        selected: isSelected,
                        onTap: () => _toggleEmoji(option),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        );
      case _SetupStep.color:
        return _PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIntro(
                label: context.l10n.tr('color'),
                title: context.l10n.tr('setupColor'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colorOptions
                    .map((Color color) {
                      return _ColorSwatch(
                        color: color,
                        selected: color == _cardColor,
                        onTap: () => setState(() => _cardColor = color),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        );
      case _SetupStep.preview:
        return Column(
          children: [_buildCardPreview(large: true, tiltable: true)],
        );
      case _SetupStep.pairTag:
        return _PixelPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIntro(
                label: context.l10n.tr('nfcTag'),
                title: context.l10n.tr('setupPairTag'),
              ),
              const SizedBox(height: 14),
              Text(
                _tagUid.isEmpty
                    ? context.l10n.tr('pairTagOptional')
                    : 'UID: $_tagUid',
                style: TextStyle(
                  color: PixelTheme.textWhite,
                  fontFamily: 'Unifont',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              _PixelButton(
                label: context.l10n.tr(_isScanning ? 'scanning' : 'pairTag'),
                onPressed: _isScanning ? null : _startPairing,
              ),
              if (_tagPaired) ...[
                const SizedBox(height: 14),
                Text(
                  context.l10n.tr('tagPairedReady'),
                  style: TextStyle(
                    color: PixelTheme.success,
                    fontFamily: 'Unifont',
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }

  Widget _buildCardPreview({bool large = false, bool tiltable = false}) {
    final String title = _displayNameController.text.trim().isEmpty
        ? context.l10n.tr('defaultPlayerName')
        : _displayNameController.text.trim();
    final String bio = _bioController.text.trim().isEmpty
        ? context.l10n.tr('defaultPlayerBio')
        : _bioController.text.trim();

    final double width = large ? 280 : 240;
    final double height = width / (53.98 / 85.60);
    final Widget card = PixelCardFace(
      title: title,
      attributeEmoji: _attributeEmoji,
      attributeLabel: _attributeLabel,
      cardColor: _cardColor,
      showText: true,
      titleFontSize: large ? 20 : 17,
      titleFontWeight: FontWeight.w900,
      attributeFontSize: large ? 11 : 10,
      emojiFontSize: large ? 15 : 13,
      titleMaxLines: 2,
      attributeMaxLines: 3,
      stackAttributePairs: true,
      watermarkScale: 1.6,
      imageToTitleSpacing: 10,
      extraContentSpacing: 10,
      image: _avatarImage(),
      extraContent: Text(
        bio,
        style: TextStyle(
          color: PixelTheme.textWhite,
          fontFamily: 'Unifont',
          fontSize: large ? 11 : 10,
          height: 1.35,
        ),
      ),
    );

    return Align(
      alignment: Alignment.center,
      child: tiltable
          ? _TiltableSetupPreview(width: width, height: height, child: card)
          : SizedBox(width: width, height: height, child: card),
    );
  }

  Widget _avatarImage() {
    if (_avatarBytes != null) {
      return Image.memory(
        _avatarBytes!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
      );
    }
    return _SetupCardAvatar(color: _cardColor, emoji: _attributeEmoji);
  }
}

class _TiltableSetupPreview extends StatefulWidget {
  const _TiltableSetupPreview({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  State<_TiltableSetupPreview> createState() => _TiltableSetupPreviewState();
}

class _TiltableSetupPreviewState extends State<_TiltableSetupPreview>
    with SingleTickerProviderStateMixin {
  double _tiltX = 0;
  double _tiltY = 0;
  Offset? _dragStart;
  double _startTiltX = 0;
  double _startTiltY = 0;
  late final AnimationController _returnController;
  late Animation<double> _returnX;
  late Animation<double> _returnY;

  @override
  void initState() {
    super.initState();
    _returnController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 420),
        )..addListener(() {
          setState(() {
            _tiltX = _returnX.value;
            _tiltY = _returnY.value;
          });
        });
    _returnX = const AlwaysStoppedAnimation<double>(0);
    _returnY = const AlwaysStoppedAnimation<double>(0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (DragDownDetails details) =>
          _startTilt(details.globalPosition),
      onPanUpdate: (DragUpdateDetails details) =>
          _updateTilt(details.globalPosition),
      onPanEnd: (_) => _resetTilt(),
      onPanCancel: _resetTilt,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0018)
          ..rotateX(_tiltX)
          ..rotateY(_tiltY),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.child,
        ),
      ),
    );
  }

  void _startTilt(Offset globalPosition) {
    _returnController.stop();
    setState(() {
      _dragStart = globalPosition;
      _startTiltX = _tiltX;
      _startTiltY = _tiltY;
    });
  }

  void _updateTilt(Offset globalPosition) {
    final Offset start = _dragStart ?? globalPosition;
    final Offset delta = globalPosition - start;
    final double dx = (delta.dx / widget.width).clamp(-1.0, 1.0);
    final double dy = (delta.dy / widget.height).clamp(-1.0, 1.0);

    setState(() {
      _tiltY = (_startTiltY - dx * 0.62).clamp(-0.44, 0.44);
      _tiltX = (_startTiltX + dy * 0.62).clamp(-0.44, 0.44);
    });
  }

  void _resetTilt() {
    setState(() {
      _dragStart = null;
    });
    _returnX = Tween<double>(begin: _tiltX, end: 0).animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOutCubic),
    );
    _returnY = Tween<double>(begin: _tiltY, end: 0).animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOutCubic),
    );
    _returnController.forward(from: 0);
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }
}

enum _SetupStep {
  name('name', 'setupName'),
  image('image', 'setupImageHint'),
  bio('bio', 'setupBio'),
  link('link', 'setupLink'),
  attribute('attribute', 'setupAttribute'),
  color('color', 'setupColor'),
  preview('preview', 'setupPreview'),
  pairTag('nfcTag', 'setupPairTag');

  const _SetupStep(this.titleKey, this.hintKey);

  final String titleKey;
  final String hintKey;
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.step,
    required this.total,
    required this.title,
  });

  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PixelTheme.bgMid,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$step / $total',
                style: TextStyle(
                  color: PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: PixelTheme.textWhite,
                    fontFamily: 'Unifont',
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            minHeight: 8,
            value: step / total,
            backgroundColor: PixelTheme.bgDark,
            valueColor: AlwaysStoppedAnimation<Color>(PixelTheme.accent),
          ),
        ],
      ),
    );
  }
}

class _FooterControls extends StatelessWidget {
  const _FooterControls({
    required this.status,
    required this.canGoBack,
    required this.canGoNext,
    required this.nextLabel,
    required this.onBack,
    required this.onNext,
  });

  final String status;
  final bool canGoBack;
  final bool canGoNext;
  final String nextLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PixelTheme.bgMid,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              color: PixelTheme.accentBlue,
              fontFamily: 'Unifont',
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PixelButton(
                  label: context.l10n.tr('back'),
                  muted: true,
                  onPressed: canGoBack ? onBack : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PixelButton(
                  label: nextLabel,
                  onPressed: canGoNext ? onNext : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepIntro extends StatelessWidget {
  const _StepIntro({required this.label, required this.title});

  final String label;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: PixelTheme.accent,
            fontFamily: 'Unifont',
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            color: PixelTheme.textWhite,
            fontFamily: 'Unifont',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _SelectedEmojiBar extends StatelessWidget {
  const _SelectedEmojiBar({required this.selected, required this.onRemove});

  final List<EmojiOption> selected;
  final ValueChanged<EmojiOption> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PixelTheme.bgDark,
        border: Border.all(color: PixelTheme.border, width: 2),
      ),
      padding: const EdgeInsets.all(8),
      child: selected.isEmpty
          ? Text(
              context.l10n.tr('noAttributeSelected'),
              style: TextStyle(
                color: PixelTheme.textGray,
                fontFamily: 'Unifont',
                fontSize: 11,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selected
                  .map((EmojiOption option) {
                    return GestureDetector(
                      onTap: () => onRemove(option),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: PixelTheme.bgMid,
                          border: Border.all(
                            color: PixelTheme.accent,
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              option.emoji,
                              style: const TextStyle(
                                fontSize: 18,
                                fontFamily: 'Roboto',
                                fontFamilyFallback: <String>[
                                  'Segoe UI Emoji',
                                  'Apple Color Emoji',
                                  'Noto Color Emoji',
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              option.label,
                              style: TextStyle(
                                color: PixelTheme.textWhite,
                                fontFamily: 'Unifont',
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: PixelTheme.textWhite,
                            ),
                          ],
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final EmojiOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? PixelTheme.accent : PixelTheme.bgDark,
          border: Border.all(
            color: selected ? PixelTheme.textWhite : PixelTheme.border,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Text(
          option.emoji,
          style: const TextStyle(
            fontSize: 26,
            height: 1,
            fontFamily: 'Roboto',
            fontFamilyFallback: <String>[
              'Segoe UI Emoji',
              'Apple Color Emoji',
              'Noto Color Emoji',
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: selected ? PixelTheme.textWhite : PixelTheme.bgDark,
            width: selected ? 4 : 2,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(4, 4),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }
}

class _SetupCardAvatar extends StatelessWidget {
  const _SetupCardAvatar({required this.color, required this.emoji});

  final Color color;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final List<String> rows = emoji.characters.take(3).toList(growable: false);
    return Container(
      color: PixelTheme.bgDark,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _SetupAvatarGridPainter(color)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: rows
                  .map(
                    (String item) => Text(
                      item,
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1.05,
                        fontFamily: 'Roboto',
                        fontFamilyFallback: <String>[
                          'Segoe UI Emoji',
                          'Apple Color Emoji',
                          'Noto Color Emoji',
                        ],
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

class _SetupAvatarGridPainter extends CustomPainter {
  const _SetupAvatarGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const int cells = 6;
    final double step = size.width / cells;
    for (int i = 1; i < cells; i += 1) {
      final double offset = i * step;
      canvas.drawLine(Offset(offset, 0), Offset(offset, size.height), paint);
      canvas.drawLine(Offset(0, offset), Offset(size.width, offset), paint);
    }
  }

  @override
  bool shouldRepaint(_SetupAvatarGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _PixelPanel extends StatelessWidget {
  const _PixelPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.accent, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(5, 5)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _PixelTextField extends StatelessWidget {
  const _PixelTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.maxLength,
    this.prefixText,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int? maxLength;
  final String? prefixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      autocorrect: keyboardType != TextInputType.url,
      enableSuggestions: keyboardType != TextInputType.url,
      style: TextStyle(
        color: PixelTheme.textWhite,
        fontFamily: 'Unifont',
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: PixelTheme.accentBlue),
        floatingLabelBehavior: prefixText == null
            ? FloatingLabelBehavior.auto
            : FloatingLabelBehavior.always,
        prefixIcon: prefixText == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, right: 2),
                child: Text(
                  prefixText!,
                  style: TextStyle(
                    color: PixelTheme.accentBlue,
                    fontFamily: 'Unifont',
                    fontSize: 13,
                  ),
                ),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        counterStyle: TextStyle(color: PixelTheme.textGray),
        filled: true,
        fillColor: PixelTheme.bgDark,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelTheme.border, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelTheme.accent, width: 2),
        ),
      ),
    );
  }
}

class _PixelButton extends StatelessWidget {
  const _PixelButton({
    required this.label,
    required this.onPressed,
    this.muted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color color = muted ? PixelTheme.textGray : PixelTheme.accent;

    return GestureDetector(
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(color: color, width: 2),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 0,
                      offset: Offset(4, 4),
                    ),
                  ]
                : const [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'Unifont',
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
