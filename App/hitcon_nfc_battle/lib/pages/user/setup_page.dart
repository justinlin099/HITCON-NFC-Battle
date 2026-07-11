import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/local_profile_store.dart';
import '../../services/setup_service.dart';
import 'emoji_catalog.dart';
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
  String _status = 'LOADING...';
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
    _linkController.text = profile?['link'] as String? ?? '';
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
      _status = '開始設定你的卡片。';
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
      _status = '圖片已更新。';
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
      _status = '圖片已匯入並轉成像素圖。';
    });
  }

  Future<void> _saveProfile({bool quiet = false}) async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
      _status = quiet ? _status : '\u6b63\u5728\u5132\u5b58\u8cc7\u6599...';
    });

    final Map<String, dynamic> updates = <String, dynamic>{
      'display_name': _displayNameController.text.trim(),
      'bio': _bioController.text.trim(),
      'link': _linkController.text.trim(),
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
      return;
    }

    setState(() {
      _isSaving = false;
      _status = success
          ? '\u8cc7\u6599\u5df2\u81ea\u52d5\u5132\u5b58\u3002'
          : '\u8cc7\u6599\u5132\u5b58\u5931\u6557\uff0c\u8acb\u7a0d\u5f8c\u518d\u8a66\u3002';
    });
  }

  Future<void> _startPairing() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
      _status = '\u6b63\u5728\u958b\u555f NTAG \u914d\u5c0d\u756b\u9762...';
    });

    final String? uid = await openNtagPairingScanPage(context);
    if (!mounted) {
      return;
    }

    setState(() {
      _isScanning = false;
      if (uid == null || uid.isEmpty) {
        _status =
            '\u914d\u5c0d\u672a\u5b8c\u6210\uff0c\u8acb\u91cd\u8a66\u3002';
        return;
      }
      _tagUid = uid;
      _tagPaired = true;
      _status =
          '\u5df2\u5beb\u5165 user_id \u4e26\u5b8c\u6210 NTAG \u914d\u5c0d\u3002';
    });
  }

  Future<void> _finishSetup() async {
    if (!_hasName) {
      setState(() {
        _stepIndex = _SetupStep.name.index;
        _status = '\u8acb\u5148\u8a2d\u5b9a\u4f60\u7684\u540d\u5b57\u3002';
      });
      return;
    }

    await _saveProfile(quiet: true);
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
        _status = '\u8acb\u5148\u8a2d\u5b9a\u4f60\u7684\u540d\u5b57\u3002';
      });
      return;
    }

    await _saveProfile(quiet: true);
    if (!mounted) {
      return;
    }

    if (_stepIndex < _SetupStep.values.length - 1) {
      setState(() {
        _stepIndex += 1;
        _status = _SetupStep.values[_stepIndex].hint;
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
      _status = _SetupStep.values[_stepIndex].hint;
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
            content: const Text(
              '\u6700\u591a\u53ea\u80fd\u9078\u4e09\u500b\u5c6c\u6027',
            ),
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
    final String nextLabel = step == _SetupStep.pairTag && !_tagPaired
        ? 'SKIP'
        : 'NEXT';

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          title: const Text('PLAYER SETUP'),
          centerTitle: true,
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          elevation: 0,
        ),
        body: _isLoading
            ? Center(
                child: Text(
                  'LOADING...',
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
                      title: step.title,
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
              const _StepIntro(label: 'NAME', title: '讓我們來設定你的名字吧'),
              const SizedBox(height: 16),
              _PixelTextField(
                controller: _displayNameController,
                label: 'DISPLAY NAME',
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
              const _StepIntro(
                label: 'IMAGE',
                title: '\u8a2d\u5b9a\u4f60\u7684\u5361\u7247\u5716\u7247',
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
                      label: '\u81ea\u5df1\u756b',
                      onPressed: _drawImage,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PixelButton(
                      label: '\u532f\u5165\u5716\u7247',
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
              const _StepIntro(
                label: 'BIO',
                title: '\u5beb\u4e00\u6bb5\u81ea\u6211\u4ecb\u7d39',
              ),
              const SizedBox(height: 16),
              _PixelTextField(
                controller: _bioController,
                label: 'BIO',
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
              const _StepIntro(
                label: 'LINK',
                title: '\u653e\u4e0a\u4f60\u60f3\u5206\u4eab\u7684\u7db2\u5740',
              ),
              const SizedBox(height: 16),
              _PixelTextField(
                controller: _linkController,
                label: 'URL',
                maxLines: 1,
                maxLength: 120,
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
              const _StepIntro(label: 'ATTRIBUTE', title: '選擇最多三個屬性'),
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
              const _StepIntro(label: 'COLOR', title: '挑個喜歡的顏色'),
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
              const _StepIntro(
                label: 'NFC TAG',
                title: '\u6383\u63cf NFC Tag \u914d\u5c0d',
              ),
              const SizedBox(height: 14),
              Text(
                _tagUid.isEmpty
                    ? '\u53ef\u4ee5\u6383\u63cf NFC Tag \u9032\u884c\u914d\u5c0d\uff0c\u4e5f\u53ef\u4ee5\u5148\u8df3\u904e\u3002'
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
                label: _isScanning ? 'SCANNING...' : 'PAIR TAG',
                onPressed: _isScanning ? null : _startPairing,
              ),
              if (_tagPaired) ...[
                const SizedBox(height: 14),
                Text(
                  'Tag \u5df2\u914d\u5c0d\uff0c\u53ef\u4ee5\u958b\u59cb\u6536\u96c6\u5361\u7247\u4e86\u3002',
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
        ? 'HITCON PLAYER'
        : _displayNameController.text.trim();
    final String bio = _bioController.text.trim().isEmpty
        ? 'Set up your card profile.'
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
  name(
    'NAME',
    '\u8b93\u6211\u5011\u4f86\u8a2d\u5b9a\u4f60\u7684\u540d\u5b57\u5427',
  ),
  image(
    'IMAGE',
    '\u81ea\u5df1\u756b\u6216\u532f\u5165\u5716\u7247\u5f8c\u9032\u5165\u5716\u7247\u7de8\u8f2f\u5668',
  ),
  bio('BIO', '\u5beb\u4e00\u6bb5\u81ea\u6211\u4ecb\u7d39'),
  link('LINK', '\u653e\u4e0a\u4f60\u60f3\u5206\u4eab\u7684\u7db2\u5740'),
  attribute('ATTRIBUTE', '\u9078\u64c7\u6700\u591a\u4e09\u500b\u5c6c\u6027'),
  color('COLOR', '\u6311\u500b\u559c\u6b61\u7684\u984f\u8272'),
  preview('PREVIEW', '\u6aa2\u8996\u6574\u5f35\u5361\u7247'),
  pairTag(
    'NFC TAG',
    '\u6383\u63cf NFC Tag \u914d\u5c0d\uff0c\u4e5f\u53ef\u4ee5\u5148\u8df3\u904e',
  );

  const _SetupStep(this.title, this.hint);

  final String title;
  final String hint;
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
                  label: 'BACK',
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
              '\u5c1a\u672a\u9078\u64c7\u5c6c\u6027',
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
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: TextStyle(
        color: PixelTheme.textWhite,
        fontFamily: 'Unifont',
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: PixelTheme.accentBlue),
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
