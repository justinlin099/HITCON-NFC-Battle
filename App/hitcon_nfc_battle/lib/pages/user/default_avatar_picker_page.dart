import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'default_avatar_catalog.dart';
import 'pixel_theme.dart';

Future<DefaultAvatarOption?> openDefaultAvatarPicker(
  BuildContext context, {
  String? selectedAssetPath,
}) {
  return Navigator.of(context).push<DefaultAvatarOption>(
    MaterialPageRoute<DefaultAvatarOption>(
      builder: (_) =>
          DefaultAvatarPickerPage(selectedAssetPath: selectedAssetPath),
    ),
  );
}

class DefaultAvatarPickerPage extends StatefulWidget {
  const DefaultAvatarPickerPage({super.key, this.selectedAssetPath});

  final String? selectedAssetPath;

  @override
  State<DefaultAvatarPickerPage> createState() =>
      _DefaultAvatarPickerPageState();
}

class _DefaultAvatarPickerPageState extends State<DefaultAvatarPickerPage> {
  DefaultAvatarOption? _selected;

  @override
  void initState() {
    super.initState();
    for (final DefaultAvatarOption option in defaultAvatarCatalog) {
      if (option.assetPath == widget.selectedAssetPath) {
        _selected = option;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PixelTheme.bgDark,
      appBar: AppBar(
        title: Text(context.l10n.tr('defaultAvatars')),
        centerTitle: true,
        backgroundColor: PixelTheme.bgMid,
        foregroundColor: PixelTheme.accent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.tr('defaultAvatarHint'),
                  style: TextStyle(
                    color: PixelTheme.textGray,
                    fontFamily: 'Unifont',
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.78,
                ),
                itemCount: defaultAvatarCatalog.length,
                itemBuilder: (BuildContext context, int index) {
                  final DefaultAvatarOption option =
                      defaultAvatarCatalog[index];
                  return _DefaultAvatarTile(
                    option: option,
                    selected: _selected == option,
                    onTap: () => setState(() => _selected = option),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: PixelTheme.bgMid,
                border: Border(top: BorderSide(color: PixelTheme.border)),
              ),
              child: _PixelConfirmButton(
                label: context.l10n.tr('selectAvatar'),
                onPressed: _selected == null
                    ? null
                    : () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultAvatarTile extends StatelessWidget {
  const _DefaultAvatarTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DefaultAvatarOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String label = context.l10n.tr(option.labelKey);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(
              color: selected ? PixelTheme.textWhite : PixelTheme.border,
              width: selected ? 3 : 2,
            ),
            boxShadow: selected
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 0,
                      offset: Offset(3, 3),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Column(
            children: [
              Expanded(
                child: Image.asset(
                  option.assetPath,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                  gaplessPlayback: true,
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 28,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? PixelTheme.accent
                          : PixelTheme.textWhite,
                      fontFamily: 'Unifont',
                      fontSize: 10,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelConfirmButton extends StatelessWidget {
  const _PixelConfirmButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(color: PixelTheme.accent, width: 2),
            boxShadow: enabled
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 0,
                      offset: Offset(4, 4),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: PixelTheme.accent,
              fontFamily: 'Unifont',
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
