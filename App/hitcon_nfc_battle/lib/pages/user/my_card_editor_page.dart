import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

import '../../l10n/app_localizations.dart';
import '../../widgets/pixel_loading_overlay.dart';
import 'pixel_theme.dart';
import 'pixel_card_face.dart';
import 'pixel_link_dialog.dart';
import 'pixel_link_icon.dart';
import 'emoji_catalog.dart';
import 'https_link_input.dart';
import 'ntag_pairing_page.dart';
import '../../services/auth_service.dart';
import '../../services/local_collection_store.dart';
import '../../services/local_profile_store.dart';

typedef PixelGrid = List<List<Color?>>;

class CardImageCropResult {
  const CardImageCropResult({
    required this.bytes,
    required this.sourceName,
    required this.sourceFormat,
    required this.usedBackgroundColor,
  });

  final Uint8List bytes;
  final String sourceName;
  final String sourceFormat;
  final bool usedBackgroundColor;
}

Future<CardImageCropResult?> openCardImageCropper(BuildContext context) async {
  const int maxSourceImageBytes = 20 * 1024 * 1024;
  final ImagePicker picker = ImagePicker();
  final XFile? picked = await picker.pickImage(source: ImageSource.gallery);

  if (picked == null) {
    return null;
  }
  final int sourceImageBytes = await picked.length();
  if (!context.mounted) {
    return null;
  }
  if (sourceImageBytes > maxSourceImageBytes) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.tr('imageTooLarge'))));
    return null;
  }
  final String readingLabel = context.l10n.tr('readingImage');

  final Uint8List bytes = await runWithPixelLoadingOverlay<Uint8List>(
    context,
    label: readingLabel,
    action: picked.readAsBytes,
  );

  final String detectedFormat = _detectImageFormat(bytes);

  if (!context.mounted) {
    return null;
  }

  final _ImagePreprocessResult? preprocessed = await Navigator.of(context)
      .push<_ImagePreprocessResult>(
        MaterialPageRoute<_ImagePreprocessResult>(
          builder: (_) => _ImagePreprocessScreen(
            sourceBytes: bytes,
            sourceName: picked.name,
            sourceFormat: detectedFormat,
          ),
        ),
      );

  if (preprocessed == null) {
    return null;
  }

  return CardImageCropResult(
    bytes: preprocessed.bytes,
    sourceName: preprocessed.sourceName,
    sourceFormat: preprocessed.sourceFormat,
    usedBackgroundColor: preprocessed.usedBackgroundColor,
  );
}

Future<Uint8List?> openBlankCardPixelEditor(
  BuildContext context, {
  required Color cardColor,
  int canvasSize = 48,
}) {
  return _openCardPixelEditorWithGrid(
    context,
    initialPixels: _createEmptyGrid(canvasSize),
    cardColor: cardColor,
    canvasSize: canvasSize,
  );
}

Future<Uint8List?> openImportedCardPixelEditor(
  BuildContext context, {
  required Color cardColor,
  int canvasSize = 48,
}) async {
  final CardImageCropResult? cropped = await openCardImageCropper(context);
  if (cropped == null || !context.mounted) {
    return null;
  }

  final PixelGrid? pixels = await runWithPixelLoadingOverlay<PixelGrid?>(
    context,
    label: context.l10n.tr('pixelatingImage'),
    action: () => _pixelGridFromImageBytes(cropped.bytes, canvasSize),
  );
  if (pixels == null || !context.mounted) {
    return null;
  }

  return _openCardPixelEditorWithGrid(
    context,
    initialPixels: pixels,
    cardColor: cardColor,
    canvasSize: canvasSize,
  );
}

Future<Uint8List?> _openCardPixelEditorWithGrid(
  BuildContext context, {
  required PixelGrid initialPixels,
  required Color cardColor,
  required int canvasSize,
}) async {
  final _PixelEditResult? result = await Navigator.of(context)
      .push<_PixelEditResult>(
        MaterialPageRoute<_PixelEditResult>(
          builder: (_) => _PixelEditorScreen(
            initialPixels: initialPixels,
            cardColor: cardColor,
            canvasSize: canvasSize,
          ),
        ),
      );

  if (result == null) {
    return null;
  }

  return encodePixelGridPng(result.pixels);
}

Uint8List encodePixelGridPng(
  PixelGrid pixels, {
  int outputSize = 512,
  Color backgroundColor = const Color(0xFF001933),
}) {
  final img.Image output = img.Image(width: outputSize, height: outputSize);
  final _Rgba bg = _rgba(backgroundColor);
  img.fill(output, color: img.ColorRgba8(bg.r, bg.g, bg.b, bg.a));

  final int cellCount = pixels.length;
  final double cellSize = outputSize / cellCount;
  for (int y = 0; y < cellCount; y += 1) {
    for (int x = 0; x < cellCount; x += 1) {
      final Color? color = pixels[y][x];
      if (color == null) {
        continue;
      }
      _fillRect(
        output,
        (x * cellSize).floor(),
        (y * cellSize).floor(),
        cellSize.ceil(),
        cellSize.ceil(),
        _rgba(color),
      );
    }
  }

  return Uint8List.fromList(img.encodePng(output, level: 6));
}

Widget _withUnifont(BuildContext context, Widget child) {
  final ThemeData base = Theme.of(context);
  return Theme(
    data: base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Unifont'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Unifont'),
      dialogTheme: base.dialogTheme.copyWith(
        titleTextStyle: (base.textTheme.titleLarge ?? const TextStyle())
            .copyWith(fontFamily: 'Unifont'),
        contentTextStyle: (base.textTheme.bodyMedium ?? const TextStyle())
            .copyWith(fontFamily: 'Unifont'),
      ),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Unifont'),
      child: child,
    ),
  );
}

enum _EditorTool {
  brush('brush'),
  eraser('eraser'),
  bucket('fill'),
  picker('pickColor');

  const _EditorTool(this.labelKey);
  final String labelKey;
}

class MyCardEditorPage extends StatefulWidget {
  const MyCardEditorPage({super.key, this.scheme, this.onBackupRestored});

  final PixelScheme? scheme;
  final Future<void> Function()? onBackupRestored;

  @override
  State<MyCardEditorPage> createState() => _MyCardEditorPageState();
}

class _MyCardEditorPageState extends State<MyCardEditorPage> {
  static const int _canvasSize = 48;

  final AuthService _authService = AuthService();
  final LocalCollectionStore _localCollectionStore = LocalCollectionStore();
  final LocalProfileStore _localProfileStore = LocalProfileStore();
  String _name = '';
  String _link = 'https://';
  String _emoji = '\u2728';
  String _description = '';
  Color _cardColor = const Color(0xFFFFD700);
  PixelGrid _pixels = _createEmptyGrid(_canvasSize);
  String? _pairedUid;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.isEmpty) {
      _name = context.l10n.tr('myCardDefaultName');
    }
    if (_description.isEmpty) {
      _description = context.l10n.tr('myCardDefaultBio');
    }
  }

  Future<void> _loadProfile() async {
    final String? userId = _authService.currentUserId;
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _authService.fetchUserProfile(),
      userId == null
          ? Future<Map<String, dynamic>>.value(<String, dynamic>{})
          : _localProfileStore.load(userId),
    ]);
    final Map<String, dynamic>? apiProfile =
        results[0] as Map<String, dynamic>?;
    final Map<String, dynamic> localProfile =
        results[1] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> profile = <String, dynamic>{
      if (apiProfile != null) ...apiProfile,
      ...localProfile,
    };

    if (!mounted) {
      return;
    }

    if (profile.isEmpty) {
      setState(() {
        _isLoadingProfile = false;
      });
      return;
    }

    final PixelGrid? loadedPixels = _decodePixelAvatar(
      profile['pixel_avatar_base64'] as String?,
    );
    final Object? rawColor = profile['card_color'];

    setState(() {
      _name = _profileString(profile, 'display_name', _name);
      final String loadedLink = _profileString(profile, 'link', _link);
      _link = validateHttpsLink(loadedLink) == null
          ? buildHttpsLink(loadedLink)
          : '';
      _emoji = _profileString(profile, 'attribute_emoji', _emoji);
      _description = _profileString(profile, 'bio', _description);
      _pairedUid = _profileString(profile, 'paired_ntag_uid', _pairedUid ?? '');
      if (_pairedUid != null && _pairedUid!.trim().isEmpty) {
        _pairedUid = null;
      }
      if (rawColor is int) {
        _cardColor = Color(rawColor);
      }
      if (loadedPixels != null) {
        _pixels = loadedPixels;
      }
      _isLoadingProfile = false;
    });
  }

  String _profileString(
    Map<String, dynamic> profile,
    String key,
    String fallback,
  ) {
    final String? value = profile[key] as String?;
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return value;
  }

  PixelGrid? _decodePixelAvatar(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final img.Image? decoded = img.decodeImage(base64Decode(raw));
      if (decoded == null) {
        return null;
      }
      return _imageToPixelGridSimple(decoded, _canvasSize);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (validateHttpsLink(_link) != null) {
      if (mounted) {
        _showEditorSnack(context.l10n.tr('invalidHttpsLink'));
      }
      return;
    }
    final Map<String, dynamic> updates = <String, dynamic>{
      'display_name': _name,
      'bio': _description,
      'attribute_emoji': _emoji,
      'attribute_label': emojiNameLabelForValue(_emoji),
      'card_color': _colorInt(_cardColor),
      'pixel_avatar_base64': base64Encode(encodePixelGridPng(_pixels)),
      'link': _link,
      if (_pairedUid != null) 'paired_ntag_uid': _pairedUid,
    };

    final String? userId = _authService.currentUserId;
    if (userId != null) {
      await _localProfileStore.save(userId, updates);
    }
    await _authService.updateUserProfile(updates);
  }

  int _colorInt(Color color) {
    final int alpha = (color.a * 255).round() & 0xFF;
    final int red = (color.r * 255).round() & 0xFF;
    final int green = (color.g * 255).round() & 0xFF;
    final int blue = (color.b * 255).round() & 0xFF;
    return alpha << 24 | red << 16 | green << 8 | blue;
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
          children: <Widget>[
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _PokemonStyleCard(
                  name: _name,
                  link: _link,
                  emoji: _emoji,
                  description: _description,
                  cardColor: _cardColor,
                  pixels: _pixels,
                  onEditImage: _openPixelEditor,
                  onEditName: () => _openTextEditor('name'),
                  onEditEmoji: () => _openTextEditor('emoji'),
                  onEditLink: () => _openTextEditor('link'),
                  onTestLink: () => confirmAndOpenLink(context, _link),
                  onEditDescription: () => _openTextEditor('description'),
                ),
                const SizedBox(height: 12),
                _EditorActionButton(
                  label: context.l10n.tr('chooseCardColor'),
                  onTap: _openColorEditor,
                  color: PixelTheme.textWhite,
                  leading: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _cardColor,
                      border: Border.all(color: PixelTheme.textWhite, width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _EditorActionButton(
                  label: _pairedUid == null
                      ? context.l10n.tr('pairNtag')
                      : context.l10n.tr('repairNtag'),
                  subtitle: _pairedUid == null ? null : 'UID: $_pairedUid',
                  onTap: _openNtagScanPage,
                  color: PixelTheme.textWhite,
                  icon: Icons.nfc_rounded,
                  opacity: 1,
                ),
                const SizedBox(height: 12),
                _EditorActionButton(
                  label: context.l10n.tr('unlockNtag'),
                  subtitle: context.l10n.tr(
                    _pairedUid == null ? 'pairFirst' : 'removeWriteProtection',
                  ),
                  onTap: _openNtagUnlockPage,
                  color: _pairedUid == null
                      ? PixelTheme.textGray
                      : PixelTheme.warning,
                  icon: Icons.lock_open_rounded,
                  opacity: _pairedUid == null ? 0.55 : 1,
                ),
                const SizedBox(height: 12),
                _EditorActionButton(
                  label: context.l10n.tr('printCard'),
                  onTap: _openPrintPreview,
                  color: PixelTheme.accent,
                  icon: Icons.print_rounded,
                ),
                const SizedBox(height: 12),
                _EditorActionButton(
                  label: context.l10n.tr('backupRestore'),
                  subtitle: context.l10n.tr('backupRestoreHint'),
                  onTap: _openBackupMenu,
                  color: PixelTheme.accentBlue,
                  icon: Icons.inventory_2_outlined,
                ),
              ],
            ),
            if (_isLoadingProfile)
              PixelLoadingOverlay(label: context.l10n.tr('loadingCardProfile')),
          ],
        ),
      ),
    );
  }

  Future<void> _openBackupMenu() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _BackupActionDialog(
          onExportFile: () {
            Navigator.of(context).pop();
            _exportBackupToFile();
          },
          onExportClipboard: () {
            Navigator.of(context).pop();
            _exportBackupToClipboard();
          },
          onImportFile: () {
            Navigator.of(context).pop();
            _importBackupFromFile();
          },
          onImportClipboard: () {
            Navigator.of(context).pop();
            _importBackupFromClipboard();
          },
        );
      },
    );
  }

  Future<String?> _localBackupJson() async {
    final String? userId = _authService.currentUserId;
    if (userId == null) {
      _showEditorSnack(context.l10n.tr('noUserDataToExport'));
      return null;
    }
    return _localCollectionStore.exportJson(userId);
  }

  Future<void> _exportBackupToClipboard() async {
    final String? userId = _authService.currentUserId;
    final String? exportText = await _localBackupJson();
    if (userId == null || exportText == null) {
      return;
    }

    await _localCollectionStore.copyExportToClipboard(userId);
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _PixelBackupDialog(
          title: context.l10n.tr('localBackup'),
          body: context.l10n.tr('backupCopied'),
          content: exportText,
        );
      },
    );
  }

  Future<void> _exportBackupToFile() async {
    final AppLocalizations l10n = context.l10n;
    final String? exportText = await _localBackupJson();
    if (exportText == null) {
      return;
    }

    final String fileName =
        'hitcon_nfc_battle_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: l10n.tr('exportBackupDialogTitle'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      bytes: Uint8List.fromList(utf8.encode(exportText)),
    );
    if (!mounted || path == null) {
      return;
    }
    _showEditorSnack(context.l10n.tr('backupExported'));
  }

  Future<void> _restoreBackupText(String backupText) async {
    final String? userId = _authService.currentUserId;
    if (userId == null) {
      _showEditorSnack(context.l10n.tr('noUserDataToRestore'));
      return;
    }
    if (backupText.trim().isEmpty) {
      return;
    }

    try {
      await _localCollectionStore.importJson(userId, backupText);
      await widget.onBackupRestored?.call();
      if (!mounted) {
        return;
      }
      _showEditorSnack(context.l10n.tr('backupRestored'));
    } on FormatException {
      _showEditorSnack(context.l10n.tr('invalidBackup'));
    } catch (_) {
      _showEditorSnack(context.l10n.tr('restoreFailed'));
    }
  }

  Future<void> _importBackupFromClipboard() async {
    final String? backupText = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _BackupImportDialog(),
    );
    if (backupText == null) {
      return;
    }
    await _restoreBackupText(backupText);
  }

  Future<void> _importBackupFromFile() async {
    final AppLocalizations l10n = context.l10n;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.tr('importBackupDialogTitle'),
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    if (result.files.single.size > LocalCollectionStore.maxBackupBytes) {
      _showEditorSnack(l10n.tr('invalidBackup'));
      return;
    }

    final Uint8List? bytes = result.files.single.bytes;
    if (bytes == null) {
      _showEditorSnack(l10n.tr('backupFileUnreadable'));
      return;
    }
    await _restoreBackupText(utf8.decode(bytes));
  }

  void _showEditorSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPrintPreview() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _CardPrintPreviewScreen(
          name: _name,
          link: _link,
          emoji: _emoji,
          description: _description,
          cardColor: _cardColor,
          pixels: _cloneGrid(_pixels),
        ),
      ),
    );
  }

  Future<void> _openTextEditor(String editType) async {
    final _TextEditResult? result = await Navigator.of(context)
        .push<_TextEditResult>(
          MaterialPageRoute<_TextEditResult>(
            builder: (_) => _TextEditorScreen(
              editType: editType,
              name: _name,
              link: _link,
              emoji: _emoji,
              description: _description,
            ),
          ),
        );

    if (result == null) {
      return;
    }

    setState(() {
      _name = result.name;
      _link = result.link;
      _emoji = result.emoji;
      _description = result.description;
    });
    await _saveProfile();
  }

  Future<void> _openColorEditor() async {
    final Color? result = await Navigator.of(context).push<Color>(
      MaterialPageRoute<Color>(
        builder: (_) => _ColorEditorScreen(initialColor: _cardColor),
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _cardColor = result;
    });
    await _saveProfile();
  }

  Future<void> _openPixelEditor() async {
    final _PixelEditResult? result = await Navigator.of(context)
        .push<_PixelEditResult>(
          MaterialPageRoute<_PixelEditResult>(
            builder: (_) => _PixelEditorScreen(
              initialPixels: _pixels,
              cardColor: _cardColor,
              canvasSize: _canvasSize,
            ),
          ),
        );

    if (result == null) {
      return;
    }

    setState(() {
      _pixels = result.pixels;
    });
    await _saveProfile();
  }

  Future<void> _openNtagScanPage() async {
    final String? result = await openNtagPairingScanPage(context);
    if (result != null && mounted) {
      setState(() {
        _pairedUid = result;
      });
      await _saveProfile();
    }
  }

  Future<void> _openNtagUnlockPage() async {
    if (_pairedUid == null || _pairedUid!.trim().isEmpty) {
      _showEditorSnack(context.l10n.tr('pairFirst'));
      return;
    }

    final bool? unlocked = await openNtagUnlockPage(context);
    if (unlocked == true && mounted) {
      _showEditorSnack(context.l10n.tr('ntagUnlocked'));
    }
  }
}

class _PokemonStyleCard extends StatelessWidget {
  const _PokemonStyleCard({
    required this.name,
    required this.link,
    required this.emoji,
    required this.description,
    required this.cardColor,
    required this.pixels,
    required this.onEditImage,
    required this.onEditName,
    required this.onEditEmoji,
    required this.onEditLink,
    required this.onTestLink,
    required this.onEditDescription,
  });

  final String name;
  final String link;
  final String emoji;
  final String description;
  final Color cardColor;
  final PixelGrid pixels;
  final VoidCallback onEditImage;
  final VoidCallback onEditName;
  final VoidCallback onEditEmoji;
  final VoidCallback onEditLink;
  final VoidCallback onTestLink;
  final VoidCallback onEditDescription;

  @override
  Widget build(BuildContext context) {
    const double ratio = 53.98 / 85.60;
    final double cardWidth = MediaQuery.of(context).size.width - 24;
    final double cardHeight = cardWidth / ratio;
    final double scale = (cardWidth / 320).clamp(0.85, 1.1);
    double s(double value) => value * scale;
    final String displayLink = link.trim().isEmpty
        ? 'https://hitcon.org'
        : link;
    final String attributeLabel = emojiLabel(emoji).toUpperCase();

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: PixelCardFace(
        title: name,
        attributeEmoji: '',
        attributeLabel: attributeLabel,
        cardColor: cardColor,
        showText: true,
        titleFontSize: s(22),
        titleFontWeight: FontWeight.w900,
        attributeFontSize: s(12),
        emojiFontSize: s(16),
        titleMaxLines: 2,
        watermarkScale: 1.6,
        imageToTitleSpacing: s(8),
        extraContentSpacing: s(8),
        onTapTitle: onEditName,
        onTapAttribute: onEditEmoji,
        titleSuffix: Icon(
          Icons.edit_rounded,
          size: s(14),
          color: PixelTheme.textWhite,
        ),
        attributeSuffix: Icon(
          Icons.edit_rounded,
          size: s(12),
          color: PixelTheme.textWhite,
        ),
        image: GestureDetector(
          onTap: onEditImage,
          behavior: HitTestBehavior.opaque,
          child: _hasAnyPixel(pixels)
              ? CustomPaint(
                  painter: _PixelCanvasPainter(pixels: pixels, showGrid: false),
                  child: const SizedBox.expand(),
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._emojiPreviewRows(emoji).map(
                        (String rowEmoji) => Text(
                          rowEmoji,
                          style: TextStyle(
                            fontSize: s(32),
                            height: 1.0,
                            color: PixelTheme.textWhite,
                            fontFamily: 'Roboto',
                            fontFamilyFallback: const <String>[
                              'Segoe UI Emoji',
                              'Apple Color Emoji',
                              'Noto Color Emoji',
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: s(6)),
                      Text(
                        context.l10n.tr('tapEditImage'),
                        style: TextStyle(
                          color: PixelTheme.textWhite,
                          fontSize: s(12),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        fixedContent: _EditorLinkRow(
          link: displayLink,
          onEditLink: onEditLink,
          onTestLink: onTestLink,
          fontSize: s(10),
        ),
        extraContent: _EditorDescription(
          description: description,
          onTap: onEditDescription,
          fontSize: s(13),
        ),
      ),
    );
  }

  List<String> _emojiPreviewRows(String value) {
    final List<String> rows = value.characters
        .where(_containsEmoji)
        .take(3)
        .toList(growable: false);
    return rows.isEmpty ? <String>[value] : rows;
  }

  bool _containsEmoji(String value) {
    for (final int rune in value.runes) {
      if ((rune >= 0x1F000 && rune <= 0x1FAFF) ||
          (rune >= 0x2600 && rune <= 0x27BF)) {
        return true;
      }
    }
    return false;
  }

  static String emojiLabel(String value) {
    return emojiLabelForValue(value);
  }
}

class _EditorLinkRow extends StatelessWidget {
  const _EditorLinkRow({
    required this.link,
    required this.onEditLink,
    required this.onTestLink,
    required this.fontSize,
  });

  final String link;
  final VoidCallback onEditLink;
  final VoidCallback onTestLink;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEditLink,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          GestureDetector(
            onTap: onTestLink,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: PixelTheme.bgDark,
                border: Border.all(color: PixelTheme.textWhite, width: 2),
              ),
              child: PixelLinkIcon(
                size: fontSize + 8,
                color: PixelTheme.textWhite,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              link,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontSize: fontSize,
                fontFamily: 'Unifont',
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.edit_rounded,
            size: fontSize + 3,
            color: PixelTheme.textWhite,
          ),
        ],
      ),
    );
  }
}

class _EditorDescription extends StatelessWidget {
  const _EditorDescription({
    required this.description,
    required this.onTap,
    required this.fontSize,
  });

  final String description;
  final VoidCallback onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.edit_rounded,
              size: fontSize - 1,
              color: PixelTheme.textWhite,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontSize: fontSize,
                height: 1.25,
                fontFamily: 'Unifont',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorActionButton extends StatelessWidget {
  const _EditorActionButton({
    required this.label,
    required this.onTap,
    required this.color,
    this.icon,
    this.leading,
    this.subtitle,
    this.opacity = 1,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: PixelTheme.bgMid,
            border: Border.all(color: color, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                blurRadius: 0,
                offset: Offset(4, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child:
                      leading ??
                      (icon == null
                          ? const SizedBox.shrink()
                          : Icon(icon, color: color, size: 20)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Unifont',
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontFamily: 'Unifont',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupActionDialog extends StatelessWidget {
  const _BackupActionDialog({
    required this.onExportFile,
    required this.onExportClipboard,
    required this.onImportFile,
    required this.onImportClipboard,
  });

  final VoidCallback onExportFile;
  final VoidCallback onExportClipboard;
  final VoidCallback onImportFile;
  final VoidCallback onImportClipboard;

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
              context.l10n.tr('backup'),
              style: TextStyle(
                color: PixelTheme.accent,
                fontFamily: 'Unifont',
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _EditorActionButton(
              label: context.l10n.tr('exportJsonFile'),
              subtitle: context.l10n.tr('exportJsonFileHint'),
              onTap: onExportFile,
              color: PixelTheme.accentBlue,
              icon: Icons.file_upload_outlined,
            ),
            const SizedBox(height: 10),
            _EditorActionButton(
              label: context.l10n.tr('copyToClipboard'),
              subtitle: context.l10n.tr('copyToClipboardHint'),
              onTap: onExportClipboard,
              color: PixelTheme.accentBlue,
              icon: Icons.content_copy_rounded,
            ),
            const SizedBox(height: 10),
            _EditorActionButton(
              label: context.l10n.tr('restoreJsonFile'),
              subtitle: context.l10n.tr('restoreJsonFileHint'),
              onTap: onImportFile,
              color: PixelTheme.textWhite,
              icon: Icons.file_download_outlined,
            ),
            const SizedBox(height: 10),
            _EditorActionButton(
              label: context.l10n.tr('restoreClipboard'),
              subtitle: context.l10n.tr('restoreClipboardHint'),
              onTap: onImportClipboard,
              color: PixelTheme.textWhite,
              icon: Icons.content_paste_rounded,
            ),
            const SizedBox(height: 10),
            _EditorActionButton(
              label: context.l10n.tr('cancel'),
              onTap: () => Navigator.of(context).pop(),
              color: PixelTheme.textWhite.withValues(alpha: 0.75),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelBackupDialog extends StatelessWidget {
  const _PixelBackupDialog({
    required this.title,
    required this.body,
    required this.content,
  });

  final String title;
  final String body;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 560),
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
              title,
              style: TextStyle(
                color: PixelTheme.accent,
                fontFamily: 'Unifont',
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontFamily: 'Unifont',
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: PixelTheme.bgDark,
                  border: Border.all(color: PixelTheme.border, width: 2),
                ),
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: TextStyle(
                      color: PixelTheme.textWhite,
                      fontFamily: 'Courier New',
                      fontSize: 10,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _EditorActionButton(
              label: context.l10n.tr('ok'),
              onTap: () => Navigator.of(context).pop(),
              color: PixelTheme.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupImportDialog extends StatefulWidget {
  const _BackupImportDialog();

  @override
  State<_BackupImportDialog> createState() => _BackupImportDialogState();
}

class _BackupImportDialogState extends State<_BackupImportDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    if (!mounted) {
      return;
    }
    _controller.text = data?.text ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 560),
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
              context.l10n.tr('restoreBackup'),
              style: TextStyle(
                color: PixelTheme.accent,
                fontFamily: 'Unifont',
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tr('restoreBackupWarning'),
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontFamily: 'Unifont',
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: TextField(
                controller: _controller,
                minLines: 8,
                maxLines: 12,
                style: TextStyle(
                  color: PixelTheme.textWhite,
                  fontFamily: 'Courier New',
                  fontSize: 10,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: PixelTheme.bgDark,
                  hintText: '{ "schema": 1, ... }',
                  hintStyle: TextStyle(
                    color: PixelTheme.textWhite.withValues(alpha: 0.45),
                    fontFamily: 'Courier New',
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: PixelTheme.border, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: PixelTheme.accent, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _EditorActionButton(
              label: context.l10n.tr('pasteFromClipboard'),
              onTap: _pasteFromClipboard,
              color: PixelTheme.textWhite,
              icon: Icons.content_paste_rounded,
            ),
            const SizedBox(height: 10),
            _EditorActionButton(
              label: context.l10n.tr('restore'),
              onTap: () => Navigator.of(context).pop(_controller.text),
              color: PixelTheme.accent,
              icon: Icons.restore_rounded,
            ),
            const SizedBox(height: 10),
            _EditorActionButton(
              label: context.l10n.tr('cancel'),
              onTap: () => Navigator.of(context).pop(),
              color: PixelTheme.textWhite.withValues(alpha: 0.75),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrintOrder {
  const _PrintOrder({
    required this.id,
    required this.barcodeValue,
    required this.fileName,
    required this.format,
  });

  final String id;
  final String barcodeValue;
  final String fileName;
  final String format;
}

class _CardPrintPreviewScreen extends StatefulWidget {
  const _CardPrintPreviewScreen({
    required this.name,
    required this.link,
    required this.emoji,
    required this.description,
    required this.cardColor,
    required this.pixels,
  });

  final String name;
  final String link;
  final String emoji;
  final String description;
  final Color cardColor;
  final PixelGrid pixels;

  @override
  State<_CardPrintPreviewScreen> createState() =>
      _CardPrintPreviewScreenState();
}

class _CardPrintPreviewScreenState extends State<_CardPrintPreviewScreen> {
  final AuthService _authService = AuthService();
  _PrintOrder? _order;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: Text(context.l10n.tr('printCard')),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double ratio = 53.98 / 85.60;
              final double cardWidth = (constraints.maxWidth - 32).clamp(
                240.0,
                360.0,
              );
              final double cardHeight = cardWidth / ratio;
              final double scale = (cardWidth / 320).clamp(0.82, 1.08);
              double s(double value) => value * scale;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: _TiltablePrintableCardPreview(
                        width: cardWidth,
                        height: cardHeight,
                        name: widget.name,
                        link: widget.link,
                        emoji: widget.emoji,
                        description: widget.description,
                        cardColor: widget.cardColor,
                        pixels: widget.pixels,
                        scale: scale,
                      ),
                    ),
                    SizedBox(height: s(18)),
                    _PrintInfoPanel(order: _order),
                    SizedBox(height: s(14)),
                    if (_order == null)
                      _EditorActionButton(
                        label: context.l10n.tr(
                          _isSubmitting ? 'submitting' : 'submitPrintOrder',
                        ),
                        color: PixelTheme.accent,
                        onTap: _isSubmitting ? () {} : _submitPrintOrder,
                      )
                    else ...[
                      _BarcodeCard(order: _order!),
                      SizedBox(height: s(12)),
                      _EditorActionButton(
                        label: context.l10n.tr('saveBarcode'),
                        color: PixelTheme.accent,
                        onTap: () => _openBarcodeSaveScreen(_order!),
                      ),
                      const SizedBox(height: 10),
                      _EditorActionButton(
                        label: context.l10n.tr('copyOrderNumber'),
                        color: PixelTheme.accentBlue,
                        onTap: () => _copyOrderId(_order!.id),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _submitPrintOrder() async {
    setState(() {
      _isSubmitting = true;
    });

    final Map<String, dynamic>? response =
        await runWithPixelLoadingOverlay<Map<String, dynamic>?>(
          context,
          label: context.l10n.tr('preparingPrintFile'),
          action: () async {
            final Uint8List artworkPng = _buildCr80PrintPng(
              name: widget.name,
              link: widget.link,
              emoji: widget.emoji,
              description: widget.description,
              cardColor: widget.cardColor,
              pixels: widget.pixels,
            );
            return _authService.submitCardPrintOrder(
              artworkPng: artworkPng,
              metadata: const <String, dynamic>{
                'format': 'EVOLIS_PRIMACY_CR80_300DPI_PNG',
                'width_px': 638,
                'height_px': 1011,
                'dpi': 300,
                'card_size': 'CR80 / ISO 7810 ID-1 / 53.98 x 85.60 mm',
                'printer': 'Evolis Primacy OEM',
                'orientation': 'portrait',
              },
            );
          },
        );

    if (!mounted) {
      return;
    }

    if (response == null) {
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('printRequestFailed'))),
      );
      return;
    }

    final String id = (response['order_id'] as String? ?? '').trim();
    final String barcodeValue = (response['barcode_value'] as String? ?? '')
        .trim();
    if (id.isEmpty || barcodeValue.isEmpty) {
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('printRequestFailed'))),
      );
      return;
    }
    setState(() {
      _isSubmitting = false;
      _order = _PrintOrder(
        id: id,
        barcodeValue: barcodeValue,
        fileName: response['file_name'] as String? ?? 'card-print-$id.png',
        format:
            response['format'] as String? ?? 'EVOLIS_PRIMACY_CR80_300DPI_PNG',
      );
    });
  }

  void _openBarcodeSaveScreen(_PrintOrder order) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => _BarcodeSaveScreen(order: order)),
    );
  }

  Future<void> _copyOrderId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.tr('orderIdCopied'))));
  }
}

class _PrintableCardPreview extends StatelessWidget {
  const _PrintableCardPreview({
    required this.width,
    required this.height,
    required this.name,
    required this.link,
    required this.emoji,
    required this.description,
    required this.cardColor,
    required this.pixels,
    required this.scale,
  });

  final double width;
  final double height;
  final String name;
  final String link;
  final String emoji;
  final String description;
  final Color cardColor;
  final PixelGrid pixels;
  final double scale;

  @override
  Widget build(BuildContext context) {
    double s(double value) => value * scale;
    final String displayLink = link.trim().isEmpty
        ? 'https://hitcon.org'
        : link;

    return ClipRRect(
      borderRadius: BorderRadius.circular(width * 0.06),
      child: SizedBox(
        width: width,
        height: height,
        child: PixelCardFace(
          title: name,
          attributeEmoji: '',
          attributeLabel: _printEmojiLabel(emoji),
          cardColor: cardColor,
          showText: true,
          showOuterFrame: false,
          showDropShadow: false,
          watermarkScale: 1.6,
          titleFontSize: s(22),
          titleFontWeight: FontWeight.w900,
          attributeFontSize: s(12),
          emojiFontSize: s(16),
          titleMaxLines: 2,
          imageToTitleSpacing: s(8),
          extraContentSpacing: s(8),
          image: _CardArtworkPreview(
            pixels: pixels,
            emoji: emoji,
            fontSize: s(32),
          ),
          fixedContent: _PrintLinkRow(link: displayLink, fontSize: s(10)),
          extraContent: _PrintDescription(
            description: description,
            fontSize: s(13),
          ),
        ),
      ),
    );
  }
}

class _TiltablePrintableCardPreview extends StatefulWidget {
  const _TiltablePrintableCardPreview({
    required this.width,
    required this.height,
    required this.name,
    required this.link,
    required this.emoji,
    required this.description,
    required this.cardColor,
    required this.pixels,
    required this.scale,
  });

  final double width;
  final double height;
  final String name;
  final String link;
  final String emoji;
  final String description;
  final Color cardColor;
  final PixelGrid pixels;
  final double scale;

  @override
  State<_TiltablePrintableCardPreview> createState() =>
      _TiltablePrintableCardPreviewState();
}

class _TiltablePrintableCardPreviewState
    extends State<_TiltablePrintableCardPreview>
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size(widget.width + 3, widget.height + 3),
              painter: _CardThicknessPainter(
                cardSize: Size(widget.width, widget.height),
                thickness: 2,
              ),
            ),
            _PrintableCardPreview(
              width: widget.width,
              height: widget.height,
              name: widget.name,
              link: widget.link,
              emoji: widget.emoji,
              description: widget.description,
              cardColor: widget.cardColor,
              pixels: widget.pixels,
              scale: widget.scale,
            ),
          ],
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

class _CardThicknessPainter extends CustomPainter {
  const _CardThicknessPainter({
    required this.cardSize,
    required this.thickness,
  });

  final Size cardSize;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint sidePaint = Paint()
      ..color = const Color(0xFFB8B8B8)
      ..style = PaintingStyle.fill;
    final Paint edgePaint = Paint()
      ..color = const Color(0xFF7A7A7A)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final double radius = cardSize.width * 0.06;
    final RRect back = RRect.fromLTRBR(
      thickness,
      thickness,
      cardSize.width + thickness,
      cardSize.height + thickness,
      Radius.circular(radius),
    );

    canvas.drawRRect(back, sidePaint);
    canvas.drawRRect(back, edgePaint);
  }

  @override
  bool shouldRepaint(_CardThicknessPainter oldDelegate) {
    return oldDelegate.cardSize != cardSize ||
        oldDelegate.thickness != thickness;
  }
}

class _CardArtworkPreview extends StatelessWidget {
  const _CardArtworkPreview({
    required this.pixels,
    required this.emoji,
    required this.fontSize,
  });

  final PixelGrid pixels;
  final String emoji;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (_hasAnyPixel(pixels)) {
      return CustomPaint(
        painter: _PixelCanvasPainter(pixels: pixels, showGrid: false),
        child: const SizedBox.expand(),
      );
    }

    final List<String> rows = emoji.characters.take(3).toList(growable: false);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows
            .map(
              (String value) => Text(
                value,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1,
                  fontFamily: 'Roboto',
                  fontFamilyFallback: const <String>[
                    'Segoe UI Emoji',
                    'Apple Color Emoji',
                    'Noto Color Emoji',
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PrintLinkRow extends StatelessWidget {
  const _PrintLinkRow({required this.link, required this.fontSize});

  final String link;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      link,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: PixelTheme.textWhite,
        fontSize: fontSize,
        fontFamily: 'Unifont',
      ),
    );
  }
}

class _PrintDescription extends StatelessWidget {
  const _PrintDescription({required this.description, required this.fontSize});

  final String description;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      description,
      style: TextStyle(
        color: PixelTheme.textWhite,
        fontSize: fontSize,
        height: 1.25,
        fontFamily: 'Unifont',
      ),
    );
  }
}

class _PrintInfoPanel extends StatelessWidget {
  const _PrintInfoPanel({required this.order});

  final _PrintOrder? order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.textWhite, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr(
              order == null ? 'printInstructions' : 'printSubmitted',
            ),
            style: TextStyle(
              color: PixelTheme.accent,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.tr(
              order == null ? 'printBeforeSubmit' : 'printAfterSubmit',
            ),
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeCard extends StatelessWidget {
  const _BarcodeCard({required this.order});

  final _PrintOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelTheme.textWhite,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        children: [
          Text(
            order.id,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              fontFamily: 'Unifont',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${order.format} - ${order.fileName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: 'Unifont',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            width: double.infinity,
            child: CustomPaint(
              painter: _PixelBarcodePainter(order.barcodeValue),
            ),
          ),
          Text(
            context.l10n.tr('barcodeInstruction'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              fontFamily: 'Unifont',
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeSaveScreen extends StatelessWidget {
  const _BarcodeSaveScreen({required this.order});

  final _PrintOrder order;

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: Text(context.l10n.tr('saveBarcode')),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Spacer(),
                _BarcodeCard(order: order),
                const SizedBox(height: 18),
                const Text(
                  'Save this barcode or copy the order ID. Show it to staff at the souvenir booth after payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                _EditorActionButton(
                  label: context.l10n.tr('copyOrderNumber'),
                  color: PixelTheme.accent,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: order.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.tr('orderIdCopied'))),
                    );
                  },
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelBarcodePainter extends CustomPainter {
  const _PixelBarcodePainter(this.value);

  final String value;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final List<int> modules = _modulesForValue(value);
    final double moduleWidth = size.width / modules.length;

    for (int i = 0; i < modules.length; i += 1) {
      if (modules[i] == 0) {
        continue;
      }
      canvas.drawRect(
        Rect.fromLTWH(i * moduleWidth, 0, moduleWidth, size.height),
        paint,
      );
    }
  }

  List<int> _modulesForValue(String value) {
    int hash = 0x13579BDF;
    for (final int unit in value.codeUnits) {
      hash = ((hash << 5) - hash + unit) & 0x7fffffff;
    }

    final List<int> modules = <int>[1, 0, 1, 0, 1, 0, 1];
    for (int i = 0; i < 72; i += 1) {
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      final int width = 1 + (hash % 3);
      final int bit = (hash & 0x08) == 0 ? 0 : 1;
      for (int j = 0; j < width; j += 1) {
        modules.add(bit);
      }
    }
    modules.addAll(<int>[1, 0, 1, 0, 1, 0, 1]);
    return modules;
  }

  @override
  bool shouldRepaint(_PixelBarcodePainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

String _printEmojiLabel(String value) {
  final String label = _PokemonStyleCard.emojiLabel(value);
  return label.trim().isEmpty ? 'Emoji' : label;
}

String _printEmojiTextForFile(String value) {
  final List<String> labels = _PokemonStyleCard.emojiLabel(value)
      .split(RegExp(r'\s{2,}'))
      .map((String item) => _asciiFallback(item))
      .where((String item) => item.isNotEmpty)
      .take(3)
      .toList(growable: false);
  return labels.isEmpty ? 'EMOJI' : labels.join('  ');
}

Uint8List _buildCr80PrintPng({
  required String name,
  required String link,
  required String emoji,
  required String description,
  required Color cardColor,
  required PixelGrid pixels,
}) {
  const int width = 638;
  const int height = 1011;
  const int pad = 38;
  const int imageSize = width - pad * 2;
  final img.Image output = img.Image(width: width, height: height);
  final _Rgba bgDark = _rgba(PixelTheme.bgDark);
  final _Rgba accent = _rgba(cardColor);
  final _Rgba white = _rgba(PixelTheme.textWhite);

  for (int y = 0; y < height; y += 1) {
    for (int x = 0; x < width; x += 1) {
      final double direction = ((x / width) + (y / height)) * 0.5;
      final double t = 0.18 + direction * 0.30;
      final int r = (bgDark.r * (1 - t) + accent.r * t).round();
      final int g = (bgDark.g * (1 - t) + accent.g * t).round();
      final int b = (bgDark.b * (1 - t) + accent.b * t).round();
      _setPixel(output, x, y, _Rgba(r, g, b, 255));
    }
  }

  _fillRect(output, pad, pad, imageSize, imageSize, bgDark);
  _strokeRect(output, pad, pad, imageSize, imageSize, accent, 6);

  if (_hasAnyPixel(pixels)) {
    final int gridSize = pixels.length;
    final double cell = (imageSize - 16) / gridSize;
    for (int y = 0; y < gridSize; y += 1) {
      for (int x = 0; x < gridSize; x += 1) {
        final Color? pixel = pixels[y][x];
        if (pixel == null) {
          continue;
        }
        _fillRect(
          output,
          pad + 8 + (x * cell).floor(),
          pad + 8 + (y * cell).floor(),
          cell.ceil(),
          cell.ceil(),
          _rgba(pixel),
        );
      }
    }
  } else {
    _drawAsciiText(
      output,
      _asciiFallback(emoji, fallback: 'EMOJI'),
      pad + 160,
      pad + 245,
      img.arial48,
      white,
    );
  }

  int y = pad + imageSize + 34;
  _drawAsciiText(
    output,
    _asciiFallback(name, fallback: 'MY CARD'),
    pad,
    y,
    img.arial24,
    white,
  );
  y += 44;
  _drawAsciiText(
    output,
    _printEmojiTextForFile(emoji),
    pad,
    y,
    img.arial24,
    accent,
  );
  y += 42;
  _drawAsciiText(
    output,
    _asciiFallback(link.trim().isEmpty ? 'https://hitcon.org' : link),
    pad,
    y,
    img.arial14,
    white,
  );
  y += 34;
  _fillRect(output, pad, y, width - pad * 2, 3, white);
  y += 24;
  for (final String line in _wrapAscii(
    _asciiFallback(description, fallback: 'HITCON NFC Battle card'),
    54,
  ).take(7)) {
    _drawAsciiText(output, line, pad, y, img.arial14, white);
    y += 24;
  }
  _drawAsciiText(
    output,
    'HITCON 2026',
    width - 214,
    height - 32,
    img.arial24,
    _Rgba(white.r, white.g, white.b, 46),
  );

  return Uint8List.fromList(img.encodePng(output, level: 6));
}

class _Rgba {
  const _Rgba(this.r, this.g, this.b, this.a);

  final int r;
  final int g;
  final int b;
  final int a;
}

_Rgba _rgba(Color color) {
  return _Rgba(
    (color.r * 255).round().clamp(0, 255),
    (color.g * 255).round().clamp(0, 255),
    (color.b * 255).round().clamp(0, 255),
    (color.a * 255).round().clamp(0, 255),
  );
}

void _setPixel(img.Image image, int x, int y, _Rgba color) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
    return;
  }
  image.setPixelRgba(x, y, color.r, color.g, color.b, color.a);
}

void _fillRect(
  img.Image image,
  int x,
  int y,
  int width,
  int height,
  _Rgba color,
) {
  for (int yy = y; yy < y + height; yy += 1) {
    for (int xx = x; xx < x + width; xx += 1) {
      _setPixel(image, xx, yy, color);
    }
  }
}

void _strokeRect(
  img.Image image,
  int x,
  int y,
  int width,
  int height,
  _Rgba color,
  int stroke,
) {
  _fillRect(image, x, y, width, stroke, color);
  _fillRect(image, x, y + height - stroke, width, stroke, color);
  _fillRect(image, x, y, stroke, height, color);
  _fillRect(image, x + width - stroke, y, stroke, height, color);
}

void _drawAsciiText(
  img.Image image,
  String text,
  int x,
  int y,
  img.BitmapFont font,
  _Rgba color,
) {
  img.drawString(
    image,
    text,
    font: font,
    x: x,
    y: y,
    color: img.ColorRgba8(color.r, color.g, color.b, color.a),
  );
}

String _asciiFallback(String value, {String fallback = ''}) {
  final String result = value
      .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return result.isEmpty ? fallback : result;
}

Iterable<String> _wrapAscii(String value, int maxChars) sync* {
  final List<String> words = value.split(' ');
  String line = '';
  for (final String word in words) {
    final String next = line.isEmpty ? word : '$line $word';
    if (next.length > maxChars && line.isNotEmpty) {
      yield line;
      line = word;
    } else {
      line = next;
    }
  }
  if (line.isNotEmpty) {
    yield line;
  }
}

class _TextEditorScreen extends StatefulWidget {
  const _TextEditorScreen({
    required this.editType,
    required this.name,
    required this.link,
    required this.emoji,
    required this.description,
  });

  final String editType;
  final String name;
  final String link;
  final String emoji;
  final String description;

  @override
  State<_TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<_TextEditorScreen> {
  static const int _maxEmojiSelection = 3;

  late final TextEditingController _nameController;
  late final TextEditingController _linkController;
  late final TextEditingController _emojiController;
  late final TextEditingController _descriptionController;
  static const List<EmojiOption> _emojiOptions = emojiOptionsCatalog;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _linkController = TextEditingController(text: httpsLinkBody(widget.link));
    _emojiController = TextEditingController(text: widget.emoji);
    _descriptionController = TextEditingController(text: widget.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _linkController.dispose();
    _emojiController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: Text(_getTitleForType()),
        ),
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Column(
              children: [
                if (widget.editType == 'emoji')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _buildSelectedEmojiBar(),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 24,
                      ),
                      child: Column(children: [..._buildFieldsForType()]),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saveAndClose,
                      style: FilledButton.styleFrom(
                        backgroundColor: PixelTheme.accent,
                        foregroundColor: PixelTheme.bgDark,
                      ),
                      child: Text(context.l10n.tr('save')),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _getTitleForType() {
    switch (widget.editType) {
      case 'name':
        return context.l10n.tr('editCardName');
      case 'emoji':
        return context.l10n.tr('chooseEmoji');
      case 'link':
        return context.l10n.tr('editLink');
      case 'description':
        return context.l10n.tr('editDescription');
      default:
        return context.l10n.tr('editCardInfo');
    }
  }

  List<Widget> _buildFieldsForType() {
    switch (widget.editType) {
      case 'name':
        return [
          TextField(
            controller: _nameController,
            style: TextStyle(color: PixelTheme.textWhite),
            decoration: _inputDecoration(context.l10n.tr('name')),
            autofocus: true,
          ),
        ];
      case 'emoji':
        return [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _emojiOptions.map((EmojiOption option) {
              final bool selected = _selectedEmojiValues().contains(
                option.emoji,
              );
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _toggleEmoji(option.emoji);
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? PixelTheme.accent : PixelTheme.bgMid,
                    border: Border.all(
                      color: selected
                          ? PixelTheme.textWhite
                          : PixelTheme.border,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    option.emoji,
                    style: TextStyle(
                      fontSize: 20,
                      color: selected
                          ? PixelTheme.bgDark
                          : PixelTheme.textWhite,
                      fontFamily: 'Roboto',
                      fontFamilyFallback: const <String>[
                        'Segoe UI Emoji',
                        'Apple Color Emoji',
                        'Noto Color Emoji',
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ];
      case 'link':
        return [
          TextField(
            controller: _linkController,
            style: TextStyle(color: PixelTheme.textWhite),
            decoration: _linkInputDecoration(),
            keyboardType: TextInputType.url,
            inputFormatters: const <TextInputFormatter>[
              HttpsLinkInputFormatter(),
            ],
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
          ),
        ];
      case 'description':
        return [
          TextField(
            controller: _descriptionController,
            style: TextStyle(color: PixelTheme.textWhite),
            decoration: _inputDecoration(context.l10n.tr('description')),
            maxLines: 5,
            minLines: 3,
            autofocus: true,
          ),
        ];
      default:
        return [
          TextField(
            controller: _nameController,
            style: TextStyle(color: PixelTheme.textWhite),
            decoration: _inputDecoration(context.l10n.tr('name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkController,
            style: TextStyle(color: PixelTheme.textWhite),
            decoration: _linkInputDecoration(),
            keyboardType: TextInputType.url,
            inputFormatters: const <TextInputFormatter>[
              HttpsLinkInputFormatter(),
            ],
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emojiController,
            maxLength: 12,
            style: TextStyle(color: PixelTheme.textWhite),
            decoration: _inputDecoration('Emoji'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            style: TextStyle(color: PixelTheme.textWhite),
            decoration: _inputDecoration(context.l10n.tr('description')),
            maxLines: 3,
            minLines: 2,
          ),
        ];
    }
  }

  Widget _buildSelectedEmojiBar() {
    final List<String> selected = _selectedEmojiValues();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.border, width: 2),
      ),
      child: selected.isEmpty
          ? Text(
              'No emoji selected',
              style: TextStyle(
                color: PixelTheme.textGray,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selected.map((String emoji) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: PixelTheme.bgDark,
                    border: Border.all(color: PixelTheme.accent, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        emoji,
                        style: const TextStyle(
                          fontSize: 20,
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
                        _emojiName(emoji),
                        style: TextStyle(
                          color: PixelTheme.textWhite,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _removeEmoji(emoji);
                          });
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: PixelTheme.textWhite,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  List<String> _selectedEmojiValues() {
    final String raw = _emojiController.text;
    return selectedEmojiValuesFromCatalog(
      raw,
    ).take(_maxEmojiSelection).toList(growable: true);
  }

  String _emojiName(String emoji) {
    return emojiNameFor(emoji);
  }

  void _toggleEmoji(String emoji) {
    final List<String> selected = _selectedEmojiValues();

    if (selected.contains(emoji)) {
      selected.remove(emoji);
    } else if (selected.length < _maxEmojiSelection) {
      selected.add(emoji);
    }

    final String nextValue = selected.join();
    _emojiController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  void _removeEmoji(String emoji) {
    final List<String> selected = _selectedEmojiValues()..remove(emoji);
    final String nextValue = selected.join();
    _emojiController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  void _saveAndClose() {
    final String link = buildHttpsLink(_linkController.text);
    if (validateHttpsLink(link) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr('invalidHttpsLink'),
            style: const TextStyle(fontFamily: 'Unifont'),
          ),
          backgroundColor: PixelTheme.warning,
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      _TextEditResult(
        name: _nameController.text.trim(),
        link: link,
        emoji: _emojiController.text.trim().isEmpty
            ? '\u2728'
            : _emojiController.text.trim(),
        description: _descriptionController.text.trim(),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: PixelTheme.textGray),
      filled: true,
      fillColor: PixelTheme.bgMid,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: PixelTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: PixelTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: PixelTheme.accent, width: 2),
      ),
    );
  }

  InputDecoration _linkInputDecoration() {
    return _inputDecoration(context.l10n.tr('link')).copyWith(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 12, right: 2),
        child: Text(
          httpsLinkPrefix,
          style: TextStyle(color: PixelTheme.accentBlue, fontFamily: 'Unifont'),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    );
  }
}

class _ColorEditorScreen extends StatefulWidget {
  const _ColorEditorScreen({required this.initialColor});

  final Color initialColor;

  @override
  State<_ColorEditorScreen> createState() => _ColorEditorScreenState();
}

class _ColorEditorScreenState extends State<_ColorEditorScreen> {
  late Color _selectedColor;

  final List<Color> _swatches = const <Color>[
    Color(0xFFFFD700),
    Color(0xFFFFE066),
    Color(0xFFFFB703),
    Color(0xFFFB8500),
    Color(0xFFE63946),
    Color(0xFFD00000),
    Color(0xFFFF006E),
    Color(0xFFFF4DFF),
    Color(0xFF9D4EDD),
    Color(0xFF7B2CBF),
    Color(0xFF5E60CE),
    Color(0xFF5E7BFF),
    Color(0xFF00D9FF),
    Color(0xFF29ADFF),
    Color(0xFF3A86FF),
    Color(0xFF80FFDB),
    Color(0xFFFF4DFF),
    Color(0xFF7CFFCB),
    Color(0xFF00E436),
    Color(0xFF38B000),
    Color(0xFFB7F171),
    Color(0xFFF1FA8C),
    Color(0xFFFF8A5B),
    Color(0xFFF4A261),
    Color(0xFFBC6C25),
    Color(0xFF9CA3AF),
    Color(0xFF6B7280),
    Color(0xFF2C2C2C),
    Color(0xFF111827),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: Text(context.l10n.tr('chooseCardColor')),
        ),
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 24,
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _swatches
                          .map(
                            (Color color) => GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedColor = color;
                                });
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: color,
                                  border: Border.all(
                                    color: _selectedColor == color
                                        ? PixelTheme.textWhite
                                        : PixelTheme.border,
                                    width: _selectedColor == color ? 3 : 1,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final Color? custom = await _showCustomColorDialog(
                            context,
                            initialColor: _selectedColor,
                            title: context.l10n.tr('customCardColor'),
                          );
                          if (custom == null) {
                            return;
                          }
                          setState(() {
                            _selectedColor = custom;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PixelTheme.accent,
                          side: BorderSide(color: PixelTheme.accent, width: 2),
                        ),
                        icon: const Icon(Icons.tune_rounded),
                        label: Text(context.l10n.tr('customColorRgb')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        border: Border.all(
                          color: PixelTheme.textWhite,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${context.l10n.tr('currentColor')}\n#${_hex6(_selectedColor)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedColor.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(_selectedColor),
                          style: FilledButton.styleFrom(
                            backgroundColor: PixelTheme.accent,
                            foregroundColor: PixelTheme.bgDark,
                          ),
                          child: Text(context.l10n.tr('applyColor')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PixelEditorScreen extends StatefulWidget {
  const _PixelEditorScreen({
    required this.initialPixels,
    required this.cardColor,
    required this.canvasSize,
  });

  final PixelGrid initialPixels;
  final Color cardColor;
  final int canvasSize;

  @override
  State<_PixelEditorScreen> createState() => _PixelEditorScreenState();
}

class _PixelEditorScreenState extends State<_PixelEditorScreen> {
  static const double _canvasViewSize = 360;

  final ScrollController _scrollController = ScrollController();
  late PixelGrid _pixels;
  late Color _brushColor;
  _EditorTool _tool = _EditorTool.brush;
  int _brushSize = 1;
  bool _showGrid = true;
  bool _strokeInProgress = false;
  ({int x, int y})? _lastPaintCell;
  final List<PixelGrid> _undoStack = <PixelGrid>[];
  final List<PixelGrid> _redoStack = <PixelGrid>[];
  String _status = '';

  final List<Color> _swatches = const <Color>[
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFF9CA3AF),
    Color(0xFF6B7280),
    Color(0xFFFF004D),
    Color(0xFFEF233C),
    Color(0xFFFFA300),
    Color(0xFFF77F00),
    Color(0xFFFFEC27),
    Color(0xFFF4D35E),
    Color(0xFF00E436),
    Color(0xFF2EC4B6),
    Color(0xFF29ADFF),
    Color(0xFF3A86FF),
    Color(0xFF83769C),
    Color(0xFF9D4EDD),
    Color(0xFFFF77A8),
    Color(0xFFFF006E),
    Color(0xFF4E5BFF),
  ];

  @override
  void initState() {
    super.initState();
    _pixels = _cloneGrid(widget.initialPixels);
    _brushColor = widget.cardColor;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('drawingReady');
    }
  }

  void _paintCell(int x, int y) {
    final int radius = _brushSize - 1;
    for (int yy = y - radius; yy <= y + radius; yy++) {
      for (int xx = x - radius; xx <= x + radius; xx++) {
        if (xx < 0 ||
            yy < 0 ||
            xx >= widget.canvasSize ||
            yy >= widget.canvasSize) {
          continue;
        }
        if ((xx - x).abs() + (yy - y).abs() > radius) {
          continue;
        }
        _pixels[yy][xx] = _tool == _EditorTool.eraser ? null : _brushColor;
      }
    }
  }

  void _paintLine(int x0, int y0, int x1, int y1) {
    int dx = (x1 - x0).abs();
    int dy = -(y1 - y0).abs();
    final int stepX = x0 < x1 ? 1 : -1;
    final int stepY = y0 < y1 ? 1 : -1;
    int error = dx + dy;
    int x = x0;
    int y = y0;

    while (true) {
      _paintCell(x, y);
      if (x == x1 && y == y1) {
        break;
      }
      final int twiceError = 2 * error;
      if (twiceError >= dy) {
        error += dy;
        x += stepX;
      }
      if (twiceError <= dx) {
        error += dx;
        y += stepY;
      }
    }
  }

  void _handleCanvasTouch(
    Offset localPosition,
    Size size, {
    required bool beginStroke,
  }) {
    final double cellSize = size.width / widget.canvasSize;
    final int x = (localPosition.dx / cellSize).floor();
    final int y = (localPosition.dy / cellSize).floor();
    if (x < 0 || y < 0 || x >= widget.canvasSize || y >= widget.canvasSize) {
      return;
    }

    if (beginStroke && !_strokeInProgress) {
      _pushHistory();
      _strokeInProgress = true;
    }

    switch (_tool) {
      case _EditorTool.brush:
      case _EditorTool.eraser:
        setState(() {
          final ({int x, int y})? lastPaintCell = _lastPaintCell;
          if (lastPaintCell == null) {
            _paintCell(x, y);
          } else {
            _paintLine(lastPaintCell.x, lastPaintCell.y, x, y);
          }
          _lastPaintCell = (x: x, y: y);
        });
        break;
      case _EditorTool.bucket:
        if (!beginStroke) {
          return;
        }
        setState(() {
          _bucketFill(x, y, _brushColor);
        });
        _strokeInProgress = false;
        _lastPaintCell = null;
        break;
      case _EditorTool.picker:
        if (!beginStroke) {
          return;
        }
        final Color? picked = _pixels[y][x];
        if (picked != null) {
          setState(() {
            _brushColor = picked;
            _tool = _EditorTool.brush;
            _status = context.l10n.tr('brushColorPicked');
          });
        }
        _strokeInProgress = false;
        _lastPaintCell = null;
        break;
    }
  }

  void _finishCanvasPointer() {
    if (!_strokeInProgress && _lastPaintCell == null) {
      return;
    }

    setState(() {
      _strokeInProgress = false;
      _lastPaintCell = null;
    });
  }

  void _clearCanvas() {
    _pushHistory();
    setState(() {
      _pixels = _createEmptyGrid(widget.canvasSize);
      _status = context.l10n.tr('unsupportedImage');
    });
  }

  Future<void> _importImage() async {
    final CardImageCropResult? cropped = await openCardImageCropper(context);
    if (cropped == null || !mounted) {
      return;
    }

    final PixelGrid? nextPixels = await runWithPixelLoadingOverlay<PixelGrid?>(
      context,
      label: context.l10n.tr('pixelatingImage'),
      action: () => _pixelGridFromImageBytes(cropped.bytes, widget.canvasSize),
    );
    if (nextPixels == null || !mounted) {
      return;
    }

    _pushHistory();
    setState(() {
      _pixels = nextPixels;
      _status = context.l10n.tr(
        cropped.usedBackgroundColor
            ? 'imageImportedFlattened'
            : 'imageImportedDetail',
        <String, Object?>{
          'name': cropped.sourceName,
          'format': cropped.sourceFormat,
        },
      );
    });
  }

  void _pushHistory() {
    _undoStack.add(_cloneGrid(_pixels));
    if (_undoStack.length > 40) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    setState(() {
      _redoStack.add(_cloneGrid(_pixels));
      _pixels = _undoStack.removeLast();
      _status = context.l10n.tr('undo');
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    setState(() {
      _undoStack.add(_cloneGrid(_pixels));
      _pixels = _redoStack.removeLast();
      _status = context.l10n.tr('redo');
    });
  }

  void _bucketFill(int sx, int sy, Color fillColor) {
    final Color? target = _pixels[sy][sx];
    if (target == fillColor) {
      return;
    }

    final List<Offset> queue = <Offset>[Offset(sx.toDouble(), sy.toDouble())];
    final Set<int> visited = <int>{};

    bool isTarget(Color? c) {
      if (target == null) {
        return c == null;
      }
      return c == target;
    }

    while (queue.isNotEmpty) {
      final Offset p = queue.removeLast();
      final int x = p.dx.toInt();
      final int y = p.dy.toInt();
      final int key = y * widget.canvasSize + x;
      if (visited.contains(key)) {
        continue;
      }
      visited.add(key);

      if (!isTarget(_pixels[y][x])) {
        continue;
      }

      _pixels[y][x] = fillColor;

      if (x > 0) {
        queue.add(Offset((x - 1).toDouble(), y.toDouble()));
      }
      if (x < widget.canvasSize - 1) {
        queue.add(Offset((x + 1).toDouble(), y.toDouble()));
      }
      if (y > 0) {
        queue.add(Offset(x.toDouble(), (y - 1).toDouble()));
      }
      if (y < widget.canvasSize - 1) {
        queue.add(Offset(x.toDouble(), (y + 1).toDouble()));
      }
    }

    _status = context.l10n.tr('canvasCleared');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: Text(context.l10n.tr('imageEditor')),
        ),
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double size = constraints.maxWidth < _canvasViewSize
                ? constraints.maxWidth
                : _canvasViewSize;
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 24,
                      ),
                      child: Column(
                        children: [
                          Center(
                            child: SizedBox(
                              width: size,
                              height: size,
                              child: RawGestureDetector(
                                behavior: HitTestBehavior.opaque,
                                gestures:
                                    <
                                      Type,
                                      GestureRecognizerFactory<
                                        GestureRecognizer
                                      >
                                    >{
                                      EagerGestureRecognizer:
                                          GestureRecognizerFactoryWithHandlers<
                                            EagerGestureRecognizer
                                          >(
                                            EagerGestureRecognizer.new,
                                            (
                                              EagerGestureRecognizer instance,
                                            ) {},
                                          ),
                                    },
                                child: Listener(
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: (PointerDownEvent details) {
                                    _handleCanvasTouch(
                                      details.localPosition,
                                      Size(size, size),
                                      beginStroke: true,
                                    );
                                  },
                                  onPointerMove: (PointerMoveEvent details) =>
                                      _handleCanvasTouch(
                                        details.localPosition,
                                        Size(size, size),
                                        beginStroke: false,
                                      ),
                                  onPointerUp: (_) => _finishCanvasPointer(),
                                  onPointerCancel: (_) =>
                                      _finishCanvasPointer(),
                                  child: CustomPaint(
                                    painter: _PixelCanvasPainter(
                                      pixels: _pixels,
                                      showGrid: _showGrid,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.tr('editorStatus', <String, Object?>{
                              'status': _status,
                              'tool': context.l10n.tr(_tool.labelKey),
                              'size': _brushSize,
                            }),
                            style: TextStyle(color: PixelTheme.accentBlue),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 86,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _PixelToolButton(
                                  iconPattern: _iconImport,
                                  label: context.l10n.tr('import'),
                                  onPressed: _importImage,
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconClear,
                                  label: context.l10n.tr('clear'),
                                  onPressed: _clearCanvas,
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconBrush,
                                  label: _tool == _EditorTool.brush
                                      ? '${context.l10n.tr('brush')} ON'
                                      : context.l10n.tr('brush'),
                                  selected: _tool == _EditorTool.brush,
                                  onPressed: () {
                                    setState(() {
                                      _tool = _EditorTool.brush;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconEraser,
                                  label: _tool == _EditorTool.eraser
                                      ? '${context.l10n.tr('eraser')} ON'
                                      : context.l10n.tr('eraser'),
                                  selected: _tool == _EditorTool.eraser,
                                  onPressed: () {
                                    setState(() {
                                      _tool = _EditorTool.eraser;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconBucket,
                                  label: _tool == _EditorTool.bucket
                                      ? '${context.l10n.tr('fill')} ON'
                                      : context.l10n.tr('fill'),
                                  selected: _tool == _EditorTool.bucket,
                                  onPressed: () {
                                    setState(() {
                                      _tool = _EditorTool.bucket;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconPicker,
                                  label: _tool == _EditorTool.picker
                                      ? '${context.l10n.tr('pickColor')} ON'
                                      : context.l10n.tr('pickColor'),
                                  selected: _tool == _EditorTool.picker,
                                  onPressed: () {
                                    setState(() {
                                      _tool = _EditorTool.picker;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconUndo,
                                  label: context.l10n.tr('undo'),
                                  onPressed: _undo,
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconRedo,
                                  label: context.l10n.tr('redo'),
                                  onPressed: _redo,
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconGrid,
                                  label: _showGrid
                                      ? context.l10n.tr('gridOn')
                                      : context.l10n.tr('gridOff'),
                                  selected: _showGrid,
                                  onPressed: () {
                                    setState(() {
                                      _showGrid = !_showGrid;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconMinus,
                                  label: context.l10n.tr('brushSmaller'),
                                  onPressed: () {
                                    setState(() {
                                      if (_brushSize > 1) {
                                        _brushSize--;
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                _PixelToolButton(
                                  iconPattern: _iconPlus,
                                  label: context.l10n.tr('brushLarger'),
                                  onPressed: () {
                                    setState(() {
                                      if (_brushSize < 3) {
                                        _brushSize++;
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 48,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _swatches.length + 1,
                              separatorBuilder:
                                  (BuildContext context, int index) =>
                                      const SizedBox(width: 8),
                              itemBuilder: (BuildContext context, int index) {
                                if (index == _swatches.length) {
                                  return GestureDetector(
                                    onTap: () async {
                                      final Color? custom =
                                          await _showCustomColorDialog(
                                            context,
                                            initialColor: _brushColor,
                                            title: context.l10n.tr(
                                              'customBrushColor',
                                            ),
                                          );
                                      if (custom == null) {
                                        return;
                                      }
                                      setState(() {
                                        _brushColor = custom;
                                        if (_tool == _EditorTool.eraser ||
                                            _tool == _EditorTool.picker) {
                                          _tool = _EditorTool.brush;
                                        }
                                        _status = context.l10n.tr(
                                          'colorSelected',
                                        );
                                      });
                                    },
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: PixelTheme.bgMid,
                                        border: Border.all(
                                          color: PixelTheme.accent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.add_rounded,
                                        color: PixelTheme.accent,
                                      ),
                                    ),
                                  );
                                }
                                final Color color = _swatches[index];
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _brushColor = color;
                                      if (_tool == _EditorTool.eraser ||
                                          _tool == _EditorTool.picker) {
                                        _tool = _EditorTool.brush;
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: color,
                                      border: Border.all(
                                        color:
                                            _brushColor == color &&
                                                _tool != _EditorTool.eraser
                                            ? PixelTheme.textWhite
                                            : PixelTheme.border,
                                        width:
                                            _brushColor == color &&
                                                _tool != _EditorTool.eraser
                                            ? 3
                                            : 1,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(
                          _PixelEditResult(
                            pixels: _cloneGrid(_pixels),
                            status:
                                'Image will be converted to ${widget.canvasSize}x${widget.canvasSize} pixels',
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: PixelTheme.accent,
                        foregroundColor: PixelTheme.bgDark,
                      ),
                      child: Text(context.l10n.tr('applyPixelArt')),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ImagePreprocessScreen extends StatefulWidget {
  const _ImagePreprocessScreen({
    required this.sourceBytes,
    required this.sourceName,
    required this.sourceFormat,
  });

  final Uint8List sourceBytes;
  final String sourceName;
  final String sourceFormat;

  @override
  State<_ImagePreprocessScreen> createState() => _ImagePreprocessScreenState();
}

class _ImagePreprocessScreenState extends State<_ImagePreprocessScreen> {
  static const double _previewSize = 300;

  late img.Image _workingImage;
  late img.Image _previewBaseImage;
  late Uint8List _workingPreviewBytes;
  late bool _hasTransparency;
  bool _isPreparing = true;
  bool _isProcessing = false;
  bool _decodeFailed = false;
  int _rotationQuarterTurns = 0;
  double _viewScale = 1.0;
  double _baseScale = 1.0;
  Offset _viewOffset = Offset.zero;
  Offset _baseOffset = Offset.zero;
  Offset _scaleStartFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _workingImage = img.Image(width: 1, height: 1);
    _previewBaseImage = img.Image(width: 1, height: 1);
    _workingPreviewBytes = Uint8List(0);
    _hasTransparency = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareImage();
    });
  }

  Future<void> _prepareImage() async {
    final Map<String, Object?> prepared = await compute(
      _prepareCropImage,
      widget.sourceBytes,
    );
    if (!mounted) {
      return;
    }
    final img.Image? image = prepared['image'] as img.Image?;
    final img.Image? preview = prepared['preview'] as img.Image?;
    final Uint8List? previewBytes = prepared['previewBytes'] as Uint8List?;
    if (image == null || preview == null || previewBytes == null) {
      setState(() {
        _isPreparing = false;
        _decodeFailed = true;
      });
      return;
    }
    setState(() {
      _workingImage = image;
      _previewBaseImage = preview;
      _workingPreviewBytes = previewBytes;
      _hasTransparency = prepared['hasTransparency'] as bool? ?? false;
      _isPreparing = false;
    });
  }

  int get _layoutPreviewWidth => _rotationQuarterTurns.isEven
      ? _previewBaseImage.width
      : _previewBaseImage.height;
  int get _layoutPreviewHeight => _rotationQuarterTurns.isEven
      ? _previewBaseImage.height
      : _previewBaseImage.width;

  _PlacedRectPx _computePlacedRectPx({
    required double boxSize,
    required int sourceWidth,
    required int sourceHeight,
    required double offsetScale,
  }) {
    final double fitScale = sourceWidth > sourceHeight
        ? boxSize / sourceWidth
        : boxSize / sourceHeight;
    final double effectiveScale = fitScale * _viewScale;
    double drawW = sourceWidth * effectiveScale;
    double drawH = sourceHeight * effectiveScale;
    if (drawW < 1) {
      drawW = 1;
    }
    if (drawH < 1) {
      drawH = 1;
    }

    final double dx = ((boxSize - drawW) / 2) + (_viewOffset.dx * offsetScale);
    final double dy = ((boxSize - drawH) / 2) + (_viewOffset.dy * offsetScale);
    return _PlacedRectPx(
      drawW: drawW.round().clamp(1, 1000000),
      drawH: drawH.round().clamp(1, 1000000),
      dx: dx.round(),
      dy: dy.round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: Text(
            context.l10n.tr('imageCropTitle', <String, Object?>{
              'name': widget.sourceName,
              'format': widget.sourceFormat,
            }),
          ),
        ),
        body: Stack(
          children: <Widget>[
            if (!_isPreparing && !_decodeFailed)
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: PixelTheme.bgMid,
                              border: Border.all(
                                color: PixelTheme.border,
                                width: 2,
                              ),
                            ),
                            child: const Text(
                              'Drag or pinch the image to choose the crop area.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              width: _previewSize,
                              height: _previewSize,
                              decoration: BoxDecoration(
                                color: _hasTransparency
                                    ? Colors.white
                                    : PixelTheme.bgMid,
                                border: Border.all(
                                  color: PixelTheme.border,
                                  width: 2,
                                ),
                              ),
                              child: GestureDetector(
                                onScaleStart: (ScaleStartDetails details) {
                                  _baseScale = _viewScale;
                                  _baseOffset = _viewOffset;
                                  _scaleStartFocalPoint =
                                      details.localFocalPoint;
                                },
                                onScaleUpdate: (ScaleUpdateDetails details) {
                                  setState(() {
                                    _viewScale = (_baseScale * details.scale)
                                        .clamp(0.2, 4.0);
                                    _viewOffset =
                                        _baseOffset +
                                        (details.localFocalPoint -
                                            _scaleStartFocalPoint);
                                  });
                                },
                                child: ClipRect(
                                  child: Center(
                                    child: SizedBox(
                                      width: _previewSize,
                                      height: _previewSize,
                                      child: Builder(
                                        builder: (BuildContext context) {
                                          final _PlacedRectPx
                                          rect = _computePlacedRectPx(
                                            boxSize: _previewSize,
                                            sourceWidth: _layoutPreviewWidth,
                                            sourceHeight: _layoutPreviewHeight,
                                            offsetScale: 1.0,
                                          );
                                          return Stack(
                                            children: [
                                              Positioned(
                                                left: rect.dx.toDouble(),
                                                top: rect.dy.toDouble(),
                                                width: rect.drawW.toDouble(),
                                                height: rect.drawH.toDouble(),
                                                child: RotatedBox(
                                                  quarterTurns:
                                                      _rotationQuarterTurns,
                                                  child: Image.memory(
                                                    _workingPreviewBytes,
                                                    fit: BoxFit.fill,
                                                    gaplessPlayback: true,
                                                    filterQuality:
                                                        FilterQuality.none,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ToolButton(
                                label: context.l10n.tr('rotateRight'),
                                onPressed: () {
                                  setState(() {
                                    _rotationQuarterTurns =
                                        (_rotationQuarterTurns + 3) % 4;
                                  });
                                },
                              ),
                              _ToolButton(
                                label: context.l10n.tr('rotateLeft'),
                                onPressed: () {
                                  setState(() {
                                    _rotationQuarterTurns =
                                        (_rotationQuarterTurns + 1) % 4;
                                  });
                                },
                              ),
                              _ToolButton(
                                label: context.l10n.tr('resetPosition'),
                                onPressed: () {
                                  setState(() {
                                    _viewScale = 1.0;
                                    _viewOffset = Offset.zero;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.tr('cropGestureHint'),
                            style: TextStyle(color: PixelTheme.accent),
                          ),
                          if (_hasTransparency) ...[
                            const SizedBox(height: 8),
                            Text(
                              context.l10n.tr('transparentImageHint'),
                              style: TextStyle(color: PixelTheme.accentBlue),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SafeArea(
                            top: false,
                            minimum: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _applyCrop,
                                style: FilledButton.styleFrom(
                                  backgroundColor: PixelTheme.accent,
                                  foregroundColor: PixelTheme.bgDark,
                                ),
                                child: Text(context.l10n.tr('applyCrop')),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            if (_isPreparing)
              PixelLoadingOverlay(label: context.l10n.tr('preparingImage')),
            if (_isProcessing)
              PixelLoadingOverlay(label: context.l10n.tr('processingCrop')),
            if (_decodeFailed)
              Positioned.fill(
                child: ColoredBox(
                  color: PixelTheme.bgDark,
                  child: Center(
                    child: Text(
                      context.l10n.tr('unsupportedImage'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PixelTheme.warning,
                        fontFamily: 'Unifont',
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyCrop() async {
    if (_isPreparing || _isProcessing || _decodeFailed) {
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    await WidgetsBinding.instance.endOfFrame;

    final Uint8List? bytes = await compute(_processCropImage, <String, Object>{
      'image': _workingImage,
      'rotation': _rotationQuarterTurns,
      'outputSize': 512,
      'previewSize': _previewSize,
      'previewWidth': _previewBaseImage.width,
      'previewHeight': _previewBaseImage.height,
      'scale': _viewScale,
      'offsetX': _viewOffset.dx,
      'offsetY': _viewOffset.dy,
    });
    if (!mounted) {
      return;
    }
    if (bytes == null) {
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('unsupportedImage'))),
      );
      return;
    }
    Navigator.of(context).pop(
      _ImagePreprocessResult(
        bytes: bytes,
        usedBackgroundColor: _hasTransparency,
        sourceName: widget.sourceName,
        sourceFormat: widget.sourceFormat,
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(color: PixelTheme.accent, width: 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: PixelTheme.accent,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PlacedRectPx {
  const _PlacedRectPx({
    required this.drawW,
    required this.drawH,
    required this.dx,
    required this.dy,
  });

  final int drawW;
  final int drawH;
  final int dx;
  final int dy;
}

class _PixelToolButton extends StatelessWidget {
  const _PixelToolButton({
    required this.iconPattern,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final List<String> iconPattern;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 90,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? PixelTheme.accent : PixelTheme.bgMid,
          border: Border.all(
            color: selected ? PixelTheme.textWhite : PixelTheme.border,
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(2, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CustomPaint(
                painter: _PixelPatternPainter(
                  pattern: iconPattern,
                  color: selected ? PixelTheme.bgDark : PixelTheme.accent,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? PixelTheme.bgDark : PixelTheme.textWhite,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelPatternPainter extends CustomPainter {
  _PixelPatternPainter({required this.pattern, required this.color});

  final List<String> pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (pattern.isEmpty) {
      return;
    }
    final int rows = pattern.length;
    final int cols = pattern.first.length;
    final double cellW = size.width / cols;
    final double cellH = size.height / rows;
    final Paint p = Paint()..color = color;

    for (int y = 0; y < rows; y++) {
      final String row = pattern[y];
      for (int x = 0; x < cols && x < row.length; x++) {
        if (row.codeUnitAt(x) == 49) {
          canvas.drawRect(Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelPatternPainter oldDelegate) {
    return oldDelegate.pattern != pattern || oldDelegate.color != color;
  }
}

class _PixelCanvasPainter extends CustomPainter {
  _PixelCanvasPainter({required this.pixels, required this.showGrid});

  final PixelGrid pixels;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final int cellCount = pixels.length;
    final double cellSize = size.width / cellCount;

    final Paint bgPaint = Paint()..color = PixelTheme.bgDark;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.25
      ..color = PixelTheme.bgLight.withValues(alpha: 0.8);

    for (int y = 0; y < cellCount; y++) {
      for (int x = 0; x < cellCount; x++) {
        final Color? color = pixels[y][x];
        if (color != null) {
          final Paint fillPaint = Paint()..color = color;
          canvas.drawRect(
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
            fillPaint,
          );
        }
        if (showGrid) {
          canvas.drawRect(
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
            gridPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelCanvasPainter oldDelegate) => true;
}

class _TextEditResult {
  const _TextEditResult({
    required this.name,
    required this.link,
    required this.emoji,
    required this.description,
  });

  final String name;
  final String link;
  final String emoji;
  final String description;
}

class _PixelEditResult {
  const _PixelEditResult({required this.pixels, required this.status});

  final PixelGrid pixels;
  final String status;
}

class _ImagePreprocessResult {
  const _ImagePreprocessResult({
    required this.bytes,
    required this.usedBackgroundColor,
    required this.sourceName,
    required this.sourceFormat,
  });

  final Uint8List bytes;
  final bool usedBackgroundColor;
  final String sourceName;
  final String sourceFormat;
}

Future<Color?> _showCustomColorDialog(
  BuildContext context, {
  required Color initialColor,
  required String title,
}) {
  return showDialog<Color>(
    context: context,
    builder: (BuildContext context) {
      return _RgbColorDialog(initialColor: initialColor, title: title);
    },
  );
}

class _RgbColorDialog extends StatefulWidget {
  const _RgbColorDialog({required this.initialColor, required this.title});

  final Color initialColor;
  final String title;

  @override
  State<_RgbColorDialog> createState() => _RgbColorDialogState();
}

class _RgbColorDialogState extends State<_RgbColorDialog> {
  late double _r;
  late double _g;
  late double _b;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _r = widget.initialColor.r * 255;
    _g = widget.initialColor.g * 255;
    _b = widget.initialColor.b * 255;
    _hexController = TextEditingController(text: _hex6(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _preview => Color.fromARGB(
    255,
    _r.round().clamp(0, 255),
    _g.round().clamp(0, 255),
    _b.round().clamp(0, 255),
  );

  Color get _previewTextColor =>
      _preview.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  Color get _previewInputBgColor => _preview.computeLuminance() > 0.5
      ? Colors.black.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.16);

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      AlertDialog(
        backgroundColor: PixelTheme.bgMid,
        title: Text(
          widget.title,
          style: TextStyle(color: PixelTheme.textWhite),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 108,
                decoration: BoxDecoration(
                  color: _preview,
                  border: Border.all(color: PixelTheme.textWhite, width: 2),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr('hexColor'),
                      style: TextStyle(
                        color: _previewTextColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: _previewInputBgColor,
                        border: Border.all(
                          color: _previewTextColor.withValues(alpha: 0.85),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _previewTextColor.withValues(alpha: 0.25),
                            blurRadius: 0,
                            offset: const Offset(2, 2),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _previewInputBgColor,
                          border: Border.all(
                            color: _previewTextColor.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '#',
                              style: TextStyle(
                                color: _previewTextColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _hexController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(6),
                                  FilteringTextInputFormatter.allow(
                                    RegExp('[0-9a-fA-F]'),
                                  ),
                                ],
                                style: TextStyle(
                                  color: _previewTextColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: _applyHexInput,
                                onSubmitted: _applyHexInput,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildSlider('R', _r, Colors.red, (double v) {
                setState(() {
                  _r = v;
                });
                _syncHexFromPreview();
              }),
              _buildSlider('G', _g, Colors.green, (double v) {
                setState(() {
                  _g = v;
                });
                _syncHexFromPreview();
              }),
              _buildSlider('B', _b, Colors.blue, (double v) {
                setState(() {
                  _b = v;
                });
                _syncHexFromPreview();
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_preview),
            style: FilledButton.styleFrom(
              backgroundColor: PixelTheme.accent,
              foregroundColor: PixelTheme.bgDark,
            ),
            child: Text(context.l10n.tr('confirm')),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    Color active,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(label, style: TextStyle(color: PixelTheme.textWhite)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              trackShape: const RectangularSliderTrackShape(),
              thumbShape: const _PixelSliderThumbShape(size: 18),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: active,
              inactiveTrackColor: PixelTheme.textWhite.withValues(alpha: 0.6),
              thumbColor: active,
            ),
            child: Slider(value: value, min: 0, max: 255, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: TextStyle(color: PixelTheme.textWhite),
          ),
        ),
      ],
    );
  }

  void _syncHexFromPreview() {
    final String next = _hex6(_preview);
    if (_hexController.text.toUpperCase() == next) {
      return;
    }
    _hexController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _applyHexInput(String raw) {
    final String normalized = raw.replaceAll('#', '').toUpperCase();
    if (normalized.length != 6) {
      return;
    }
    final int? rgb = int.tryParse(normalized, radix: 16);
    if (rgb == null) {
      return;
    }

    final int r = (rgb >> 16) & 0xFF;
    final int g = (rgb >> 8) & 0xFF;
    final int b = rgb & 0xFF;

    setState(() {
      _r = r.toDouble();
      _g = g.toDouble();
      _b = b.toDouble();
    });
  }
}

class _PixelSliderThumbShape extends SliderComponentShape {
  const _PixelSliderThumbShape({required this.size});

  final double size;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.square(size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Rect rect = Rect.fromCenter(
      center: center,
      width: size,
      height: size,
    );

    final Paint shadow = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawRect(rect.shift(const Offset(2, 2)), shadow);

    final Paint fill = Paint()
      ..color = sliderTheme.thumbColor ?? PixelTheme.accent;
    canvas.drawRect(rect, fill);

    final Paint border = Paint()
      ..color = PixelTheme.textWhite
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, border);
  }
}

String _hex6(Color color) {
  final int r = (color.r * 255).round().clamp(0, 255);
  final int g = (color.g * 255).round().clamp(0, 255);
  final int b = (color.b * 255).round().clamp(0, 255);
  return '${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

PixelGrid _createEmptyGrid(int size) {
  return List<List<Color?>>.generate(
    size,
    (_) => List<Color?>.filled(size, null),
  );
}

PixelGrid _cloneGrid(PixelGrid source) {
  return source
      .map((List<Color?> row) => List<Color?>.from(row))
      .toList(growable: false);
}

bool _hasAnyPixel(PixelGrid source) {
  for (final List<Color?> row in source) {
    for (final Color? c in row) {
      if (c != null) {
        return true;
      }
    }
  }
  return false;
}

Map<String, Object?> _prepareCropImage(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return <String, Object?>{};
  }
  final bool hasTransparency = _detectTransparency(decoded);
  final int maxSide = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final img.Image preview;
  if (maxSide <= 1024) {
    preview = decoded.clone();
  } else if (decoded.width >= decoded.height) {
    preview = img.copyResize(
      decoded,
      width: 1024,
      interpolation: img.Interpolation.linear,
    );
  } else {
    preview = img.copyResize(
      decoded,
      height: 1024,
      interpolation: img.Interpolation.linear,
    );
  }
  final img.Image flattenedPreview = _flattenImageOnWhite(preview);
  return <String, Object?>{
    'image': decoded,
    'preview': preview,
    'previewBytes': Uint8List.fromList(
      img.encodePng(flattenedPreview, level: 1),
    ),
    'hasTransparency': hasTransparency,
  };
}

Uint8List? _processCropImage(Map<String, Object> request) {
  final img.Image? original = request['image'] as img.Image?;
  if (original == null) {
    return null;
  }
  img.Image source = _flattenImageOnWhite(original);
  final int rotation = request['rotation'] as int;
  source = _rotateImageByQuarterTurns(source, rotation);

  final int outputSize = request['outputSize'] as int;
  final double previewSize = request['previewSize'] as double;
  final int basePreviewWidth = request['previewWidth'] as int;
  final int basePreviewHeight = request['previewHeight'] as int;
  final bool swapsDimensions = rotation.isOdd;
  final int sourceWidth = swapsDimensions
      ? basePreviewHeight
      : basePreviewWidth;
  final int sourceHeight = swapsDimensions
      ? basePreviewWidth
      : basePreviewHeight;
  final _PlacedRectPx previewRect = _placedRectForImage(
    boxSize: previewSize,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    viewScale: request['scale'] as double,
    offsetX: request['offsetX'] as double,
    offsetY: request['offsetY'] as double,
  );

  final double ratio = outputSize / previewSize;
  final int drawW = (previewRect.drawW * ratio).round().clamp(1, 1000000);
  final int drawH = (previewRect.drawH * ratio).round().clamp(1, 1000000);
  final img.Image resized = img.copyResize(
    source,
    width: drawW,
    height: drawH,
    interpolation: img.Interpolation.linear,
  );
  final img.Image output = img.Image(width: outputSize, height: outputSize);
  img.fill(output, color: img.ColorRgba8(255, 255, 255, 255));
  _compositeImageClipped(
    destination: output,
    source: resized,
    dstX: (previewRect.dx * ratio).round(),
    dstY: (previewRect.dy * ratio).round(),
  );
  return Uint8List.fromList(img.encodePng(output, level: 3));
}

Future<PixelGrid?> _pixelGridFromImageBytes(Uint8List bytes, int size) async {
  final List<int>? values = await compute(_pixelateImageBytes, <String, Object>{
    'bytes': bytes,
    'size': size,
  });
  if (values == null || values.length != size * size) {
    return null;
  }
  return List<List<Color?>>.generate(
    size,
    (int y) => List<Color?>.generate(
      size,
      (int x) => Color(values[y * size + x]),
      growable: false,
    ),
    growable: false,
  );
}

List<int>? _pixelateImageBytes(Map<String, Object> request) {
  final Uint8List bytes = request['bytes'] as Uint8List;
  final int size = request['size'] as int;
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }
  final img.Image flattened = _flattenImageOnWhite(decoded);
  final img.Image resized = img.copyResize(
    flattened,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  return List<int>.generate(size * size, (int index) {
    final img.Pixel pixel = resized.getPixel(index % size, index ~/ size);
    return 0xFF000000 |
        (_toByteChannel(pixel.r) << 16) |
        (_toByteChannel(pixel.g) << 8) |
        _toByteChannel(pixel.b);
  }, growable: false);
}

img.Image _flattenImageOnWhite(img.Image source) {
  final img.Image flattened = img.Image(
    width: source.width,
    height: source.height,
  );
  img.fill(flattened, color: img.ColorRgba8(255, 255, 255, 255));
  img.compositeImage(flattened, source);
  return flattened;
}

img.Image _rotateImageByQuarterTurns(img.Image source, int turns) {
  switch (((turns % 4) + 4) % 4) {
    case 1:
      return img.copyRotate(source, angle: 90);
    case 2:
      return img.copyRotate(source, angle: 180);
    case 3:
      return img.copyRotate(source, angle: -90);
    default:
      return source;
  }
}

_PlacedRectPx _placedRectForImage({
  required double boxSize,
  required int sourceWidth,
  required int sourceHeight,
  required double viewScale,
  required double offsetX,
  required double offsetY,
}) {
  final double fitScale = sourceWidth > sourceHeight
      ? boxSize / sourceWidth
      : boxSize / sourceHeight;
  final double effectiveScale = fitScale * viewScale;
  final double drawW = (sourceWidth * effectiveScale).clamp(1, 1000000);
  final double drawH = (sourceHeight * effectiveScale).clamp(1, 1000000);
  return _PlacedRectPx(
    drawW: drawW.round(),
    drawH: drawH.round(),
    dx: (((boxSize - drawW) / 2) + offsetX).round(),
    dy: (((boxSize - drawH) / 2) + offsetY).round(),
  );
}

void _compositeImageClipped({
  required img.Image destination,
  required img.Image source,
  required int dstX,
  required int dstY,
}) {
  int outX = dstX;
  int outY = dstY;
  int srcX = 0;
  int srcY = 0;
  int copyW = source.width;
  int copyH = source.height;
  if (outX < 0) {
    srcX = -outX;
    copyW -= srcX;
    outX = 0;
  }
  if (outY < 0) {
    srcY = -outY;
    copyH -= srcY;
    outY = 0;
  }
  if (outX + copyW > destination.width) {
    copyW = destination.width - outX;
  }
  if (outY + copyH > destination.height) {
    copyH = destination.height - outY;
  }
  if (copyW <= 0 || copyH <= 0) {
    return;
  }
  img.compositeImage(
    destination,
    source,
    dstX: outX,
    dstY: outY,
    srcX: srcX,
    srcY: srcY,
    srcW: copyW,
    srcH: copyH,
  );
}

bool _detectTransparency(img.Image source) {
  for (int y = 0; y < source.height; y++) {
    for (int x = 0; x < source.width; x++) {
      final img.Pixel p = source.getPixel(x, y);
      if (_toByteChannel(p.a) < 255) {
        return true;
      }
    }
  }
  return false;
}

PixelGrid _imageToPixelGridSimple(img.Image source, int size) {
  final img.Image flattened = img.Image(
    width: source.width,
    height: source.height,
  );
  img.fill(flattened, color: img.ColorRgba8(255, 255, 255, 255));
  img.compositeImage(flattened, source);

  final img.Image target = img.Image(width: size, height: size);
  img.fill(target, color: img.ColorRgba8(255, 255, 255, 255));

  final double fitScale = flattened.width > flattened.height
      ? size / flattened.width
      : size / flattened.height;
  int drawW = (flattened.width * fitScale).round();
  int drawH = (flattened.height * fitScale).round();
  if (drawW < 1) {
    drawW = 1;
  }
  if (drawH < 1) {
    drawH = 1;
  }

  final img.Image resized = img.copyResize(
    flattened,
    width: drawW,
    height: drawH,
    interpolation: img.Interpolation.average,
  );

  final int dstX = ((size - drawW) / 2).round();
  final int dstY = ((size - drawH) / 2).round();
  img.compositeImage(target, resized, dstX: dstX, dstY: dstY);

  final PixelGrid result = _createEmptyGrid(size);

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final img.Pixel p = target.getPixel(x, y);
      int r = _toByteChannel(p.r);
      int g = _toByteChannel(p.g);
      int b = _toByteChannel(p.b);

      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      result[y][x] = Color.fromARGB(255, r, g, b);
    }
  }

  return result;
}

int _toByteChannel(num value) {
  // Treat image package channel values as byte-like (0..255) to avoid
  // spuriously boosting low values (e.g., 1 -> 255), which creates color speckles.
  return value.toDouble().round().clamp(0, 255);
}

String _detectImageFormat(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpg';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    return 'gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return 'unknown';
}

const List<String> _iconImport = <String>[
  '111111111111',
  '100000000001',
  '100011000001',
  '100011000001',
  '100000011001',
  '100000111101',
  '100001110111',
  '100011100011',
  '101111111111',
  '100000000001',
  '100000000001',
  '111111111111',
];

const List<String> _iconClear = <String>[
  '000000000000',
  '000001100000',
  '001111111100',
  '000000000000',
  '001111111100',
  '001101101100',
  '001101101100',
  '001101101100',
  '001101101100',
  '001111111100',
  '000111111000',
  '000000000000',
];

const List<String> _iconBrush = <String>[
  '000000000111',
  '000000001111',
  '000000011110',
  '000000111100',
  '000001111000',
  '000011110000',
  '000111100000',
  '001111000000',
  '011110000000',
  '111100000000',
  '011000000000',
  '000000000000',
];

const List<String> _iconEraser = <String>[
  '000000111100',
  '000001111110',
  '000011111111',
  '000111111110',
  '001111111100',
  '011111111000',
  '111111110000',
  '111111100000',
  '011111000000',
  '001110000000',
  '000100000000',
  '000000000000',
];

const List<String> _iconBucket = <String>[
  '000000110000',
  '000001111000',
  '000011111100',
  '000111111110',
  '001111111111',
  '001111111111',
  '000111111110',
  '000011111100',
  '000001111000',
  '000000110000',
  '000000011000',
  '000000001100',
];

const List<String> _iconPicker = <String>[
  '110000000000',
  '111000000000',
  '011100000000',
  '001110000000',
  '000111111111',
  '000011111110',
  '000001111100',
  '000000111000',
  '000000011000',
  '000000011000',
  '000000001000',
  '000000000000',
];

const List<String> _iconUndo = <String>[
  '000000000000',
  '000011111000',
  '000000011000',
  '000000011000',
  '000000011000',
  '000000011000',
  '000000011000',
  '001111111100',
  '011000000000',
  '111000000000',
  '011000000000',
  '001100000000',
];

const List<String> _iconRedo = <String>[
  '000000000000',
  '000111110000',
  '000110000000',
  '000110000000',
  '000110000000',
  '000110000000',
  '000110000000',
  '001111111100',
  '000000000110',
  '000000000111',
  '000000000110',
  '000000001100',
];

const List<String> _iconGrid = <String>[
  '000000000000',
  '011111111110',
  '010010010010',
  '010010010010',
  '011111111110',
  '010010010010',
  '010010010010',
  '011111111110',
  '010010010010',
  '010010010010',
  '011111111110',
  '000000000000',
];

const List<String> _iconMinus = <String>[
  '000000000000',
  '000000000000',
  '000000000000',
  '000000000000',
  '001111111100',
  '001111111100',
  '000000000000',
  '000000000000',
  '000000000000',
  '000000000000',
  '000000000000',
  '000000000000',
];

const List<String> _iconPlus = <String>[
  '000000000000',
  '000000110000',
  '000000110000',
  '000000110000',
  '001111111100',
  '001111111100',
  '000000110000',
  '000000110000',
  '000000110000',
  '000000000000',
  '000000000000',
  '000000000000',
];
