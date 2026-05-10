import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'pixel_theme.dart';

typedef PixelGrid = List<List<Color?>>;

Widget _withUnifont(BuildContext context, Widget child) {
  final ThemeData base = Theme.of(context);
  return Theme(
    data: base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Unifont'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Unifont'),
      dialogTheme: base.dialogTheme.copyWith(
        titleTextStyle: (base.textTheme.titleLarge ?? const TextStyle()).copyWith(fontFamily: 'Unifont'),
        contentTextStyle: (base.textTheme.bodyMedium ?? const TextStyle()).copyWith(fontFamily: 'Unifont'),
      ),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Unifont'),
      child: child,
    ),
  );
}

enum _EditorTool {
  brush('畫筆'),
  eraser('橡皮擦'),
  bucket('油漆桶'),
  picker('吸管');

  const _EditorTool(this.label);
  final String label;
}

class MyCardEditorPage extends StatefulWidget {
  const MyCardEditorPage({super.key, this.scheme});

  final PixelScheme? scheme;

  @override
  State<MyCardEditorPage> createState() => _MyCardEditorPageState();
}

class _MyCardEditorPageState extends State<MyCardEditorPage> {
  static const int _canvasSize = 48;

  String _name = '我的卡片';
  String _link = 'https://';
  String _emoji = '✨';
  Color _cardColor = const Color(0xFFFFD700);
  PixelGrid _pixels = _createEmptyGrid(_canvasSize);
  String _pixelStatus = '尚未編輯點陣圖';

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(widget.scheme ?? PixelTheme.defaultScheme);

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
        primaryTextTheme: Theme.of(context).primaryTextTheme.apply(fontFamily: 'Unifont'),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Unifont'),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _OverviewCard(
              name: _name,
              link: _link,
              emoji: _emoji,
              cardColor: _cardColor,
              pixels: _pixels,
            ),
            const SizedBox(height: 12),
            _SettingButton(
              icon: Icons.badge_rounded,
              title: '名稱 / 連結 / Emoji',
              subtitle: '目前：$_name',
              onTap: _openTextEditor,
            ),
            const SizedBox(height: 10),
            _SettingButton(
              icon: Icons.palette_rounded,
              title: '卡片顏色',
              subtitle: '點擊進入顏色設定',
              trailing: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _cardColor,
                  border: Border.all(color: PixelTheme.textWhite),
                ),
              ),
              onTap: _openColorEditor,
            ),
            const SizedBox(height: 10),
            _SettingButton(
              icon: Icons.draw_rounded,
              title: '圖片 / 點陣圖編輯器',
              subtitle: _pixelStatus,
              onTap: _openPixelEditor,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PixelTheme.bgMid,
                border: Border.all(color: PixelTheme.border, width: 2),
              ),
              child: Text(
                '目前解析度：48x48。\n編輯固定使用 48x48，輸出顯示可放大到 128x128。',
                style: TextStyle(color: PixelTheme.textGray),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTextEditor() async {
    final _TextEditResult? result = await Navigator.of(context).push<_TextEditResult>(
      MaterialPageRoute<_TextEditResult>(
        builder: (_) => _TextEditorScreen(
          name: _name,
          link: _link,
          emoji: _emoji,
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
    });
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
  }

  Future<void> _openPixelEditor() async {
    final _PixelEditResult? result = await Navigator.of(context).push<_PixelEditResult>(
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
      _pixelStatus = result.status;
    });
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.name,
    required this.link,
    required this.emoji,
    required this.cardColor,
    required this.pixels,
  });

  final String name;
  final String link;
  final String emoji;
  final Color cardColor;
  final PixelGrid pixels;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: PixelTheme.textWhite, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的卡片預覽',
            style: TextStyle(
              color: PixelTheme.bgDark,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: PixelTheme.bgDark,
                  border: Border.all(color: PixelTheme.textWhite),
                ),
                child: _hasAnyPixel(pixels)
                    ? CustomPaint(
                        painter: _PixelCanvasPainter(pixels: pixels, showGrid: false),
                        child: const SizedBox.expand(),
                      )
                    : Center(
                        child: Text(
                          emoji,
                          style: TextStyle(
                            fontSize: 32,
                            color: PixelTheme.textWhite,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: PixelTheme.textWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      link,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: PixelTheme.textWhite.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingButton extends StatelessWidget {
  const _SettingButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(color: PixelTheme.border, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(3, 3)),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: PixelTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: PixelTheme.textWhite,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: PixelTheme.textGray,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right_rounded, color: PixelTheme.accent),
          ],
        ),
      ),
    );
  }
}

class _TextEditorScreen extends StatefulWidget {
  const _TextEditorScreen({required this.name, required this.link, required this.emoji});

  final String name;
  final String link;
  final String emoji;

  @override
  State<_TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<_TextEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _linkController;
  late final TextEditingController _emojiController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _linkController = TextEditingController(text: widget.link);
    _emojiController = TextEditingController(text: widget.emoji);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _linkController.dispose();
    _emojiController.dispose();
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
        title: const Text('編輯卡片資訊'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(color: PixelTheme.textWhite),
              decoration: _inputDecoration('卡片名稱'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _linkController,
              style: TextStyle(color: PixelTheme.textWhite),
              decoration: _inputDecoration('超連結'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emojiController,
              maxLength: 4,
              style: TextStyle(color: PixelTheme.textWhite),
              decoration: _inputDecoration('emoji 屬性'),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    _TextEditResult(
                      name: _nameController.text.trim(),
                      link: _linkController.text.trim(),
                      emoji: _emojiController.text.trim().isEmpty ? '■' : _emojiController.text.trim(),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: PixelTheme.accent,
                  foregroundColor: PixelTheme.bgDark,
                ),
                child: const Text('儲存'),
              ),
            ),
          ],
        ),
      ),
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
        title: const Text('編輯卡片顏色'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
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
                            color: _selectedColor == color ? PixelTheme.textWhite : PixelTheme.border,
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
                    title: '自訂卡片顏色',
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
                label: const Text('自訂顏色 (RGB)'),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: _selectedColor,
                border: Border.all(color: PixelTheme.textWhite, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '預覽色塊\n#${_hex6(_selectedColor)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _selectedColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selectedColor),
                style: FilledButton.styleFrom(
                  backgroundColor: PixelTheme.accent,
                  foregroundColor: PixelTheme.bgDark,
                ),
                child: const Text('套用顏色'),
              ),
            ),
          ],
        ),
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

  late PixelGrid _pixels;
  late Color _brushColor;
  _EditorTool _tool = _EditorTool.brush;
  int _brushSize = 1;
  bool _showGrid = true;
  bool _strokeInProgress = false;
  final List<PixelGrid> _undoStack = <PixelGrid>[];
  final List<PixelGrid> _redoStack = <PixelGrid>[];
  String _status = '彩色點陣編輯器：可匯入圖片後繼續改。';

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

  void _paintCell(int x, int y) {
    final int radius = _brushSize - 1;
    for (int yy = y - radius; yy <= y + radius; yy++) {
      for (int xx = x - radius; xx <= x + radius; xx++) {
        if (xx < 0 || yy < 0 || xx >= widget.canvasSize || yy >= widget.canvasSize) {
          continue;
        }
        if ((xx - x).abs() + (yy - y).abs() > radius) {
          continue;
        }
        _pixels[yy][xx] = _tool == _EditorTool.eraser ? null : _brushColor;
      }
    }
  }

  void _handleCanvasTouch(Offset localPosition, Size size, {required bool beginStroke}) {
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
          _paintCell(x, y);
        });
        break;
      case _EditorTool.bucket:
        setState(() {
          _bucketFill(x, y, _brushColor);
        });
        _strokeInProgress = false;
        break;
      case _EditorTool.picker:
        final Color? picked = _pixels[y][x];
        if (picked != null) {
          setState(() {
            _brushColor = picked;
            _tool = _EditorTool.brush;
            _status = '已吸取顏色';
          });
        }
        _strokeInProgress = false;
        break;
    }
  }

  void _clearCanvas() {
    _pushHistory();
    setState(() {
      _pixels = _createEmptyGrid(widget.canvasSize);
      _status = '畫布已清空';
    });
  }

  Future<void> _importImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked == null) {
      return;
    }

    final Uint8List bytes = await picked.readAsBytes();

    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return;
    }

    final String detectedFormat = _detectImageFormat(bytes);

    if (!mounted) {
      return;
    }

    final _ImagePreprocessResult? preprocessed = await Navigator.of(context).push<_ImagePreprocessResult>(
      MaterialPageRoute<_ImagePreprocessResult>(
        builder: (_) => _ImagePreprocessScreen(
          sourceBytes: bytes,
          sourceName: picked.name,
          sourceFormat: detectedFormat,
        ),
      ),
    );

    if (preprocessed == null) {
      return;
    }

    final PixelGrid nextPixels = _imageToPixelGridSimple(
      preprocessed.image,
      widget.canvasSize,
    );

    _pushHistory();
    setState(() {
      _pixels = nextPixels;
      _status = preprocessed.usedBackgroundColor
          ? '已匯入「${preprocessed.sourceName}」(${preprocessed.sourceFormat})，旋轉/裁切並套用背景色後，轉成 ${widget.canvasSize}x${widget.canvasSize} 點陣圖'
          : '已匯入「${preprocessed.sourceName}」(${preprocessed.sourceFormat})，旋轉/裁切並轉成 ${widget.canvasSize}x${widget.canvasSize} 點陣圖';
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
      _status = '已復原';
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    setState(() {
      _undoStack.add(_cloneGrid(_pixels));
      _pixels = _redoStack.removeLast();
      _status = '已重做';
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

      if (x > 0) queue.add(Offset((x - 1).toDouble(), y.toDouble()));
      if (x < widget.canvasSize - 1) queue.add(Offset((x + 1).toDouble(), y.toDouble()));
      if (y > 0) queue.add(Offset(x.toDouble(), (y - 1).toDouble()));
      if (y < widget.canvasSize - 1) queue.add(Offset(x.toDouble(), (y + 1).toDouble()));
    }

    _status = '已填色';
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
        title: const Text('彩色點陣圖編輯器'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              height: 86,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PixelToolButton(iconPattern: _iconImport, label: '匯入', onPressed: _importImage),
                  const SizedBox(width: 8),
                  _PixelToolButton(iconPattern: _iconClear, label: '清空', onPressed: _clearCanvas),
                  const SizedBox(width: 8),
                  _PixelToolButton(
                    iconPattern: _iconBrush,
                    label: _tool == _EditorTool.brush ? '畫筆 ON' : '畫筆',
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
                    label: _tool == _EditorTool.eraser ? '橡皮擦 ON' : '橡皮擦',
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
                    label: _tool == _EditorTool.bucket ? '油漆桶 ON' : '油漆桶',
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
                    label: _tool == _EditorTool.picker ? '吸管 ON' : '吸管',
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
                    label: '復原',
                    onPressed: _undo,
                  ),
                  const SizedBox(width: 8),
                  _PixelToolButton(
                    iconPattern: _iconRedo,
                    label: '重做',
                    onPressed: _redo,
                  ),
                  const SizedBox(width: 8),
                  _PixelToolButton(
                    iconPattern: _iconGrid,
                    label: _showGrid ? '格線 ON' : '格線 OFF',
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
                    label: '筆刷-',
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
                    label: '筆刷+',
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
                separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  if (index == _swatches.length) {
                    return GestureDetector(
                      onTap: () async {
                        final Color? custom = await _showCustomColorDialog(
                          context,
                          initialColor: _brushColor,
                          title: '自訂筆刷顏色',
                        );
                        if (custom == null) {
                          return;
                        }
                        setState(() {
                          _brushColor = custom;
                          if (_tool == _EditorTool.eraser || _tool == _EditorTool.picker) {
                            _tool = _EditorTool.brush;
                          }
                          _status = '已設定自訂筆刷顏色';
                        });
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: PixelTheme.bgMid,
                          border: Border.all(color: PixelTheme.accent, width: 2),
                        ),
                        child: Icon(Icons.add_rounded, color: PixelTheme.accent),
                      ),
                    );
                  }
                  final Color color = _swatches[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _brushColor = color;
                        if (_tool == _EditorTool.eraser || _tool == _EditorTool.picker) {
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
                          color: _brushColor == color && _tool != _EditorTool.eraser ? PixelTheme.textWhite : PixelTheme.border,
                          width: _brushColor == color && _tool != _EditorTool.eraser ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double size = constraints.maxWidth < _canvasViewSize ? constraints.maxWidth : _canvasViewSize;
                    return SizedBox(
                      width: size,
                      height: size,
                      child: GestureDetector(
                        onPanDown: (DragDownDetails details) => _handleCanvasTouch(details.localPosition, Size(size, size), beginStroke: true),
                        onPanUpdate: (DragUpdateDetails details) => _handleCanvasTouch(details.localPosition, Size(size, size), beginStroke: false),
                        onPanEnd: (_) {
                          _strokeInProgress = false;
                        },
                        onTapDown: (TapDownDetails details) {
                          _handleCanvasTouch(details.localPosition, Size(size, size), beginStroke: true);
                          _strokeInProgress = false;
                        },
                        child: CustomPaint(
                          painter: _PixelCanvasPainter(pixels: _pixels, showGrid: _showGrid),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$_status | 工具: ${_tool.label} | 筆刷: $_brushSize',
              style: TextStyle(color: PixelTheme.accentBlue),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    _PixelEditResult(
                      pixels: _cloneGrid(_pixels),
                      status: '已更新彩色點陣圖（${widget.canvasSize}x${widget.canvasSize}）',
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: PixelTheme.accent,
                  foregroundColor: PixelTheme.bgDark,
                ),
                child: const Text('儲存點陣圖'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ImagePreprocessScreen extends StatefulWidget {
  const _ImagePreprocessScreen({required this.sourceBytes, required this.sourceName, required this.sourceFormat});

  final Uint8List sourceBytes;
  final String sourceName;
  final String sourceFormat;

  @override
  State<_ImagePreprocessScreen> createState() => _ImagePreprocessScreenState();
}

class _ImagePreprocessScreenState extends State<_ImagePreprocessScreen> {
  static const double _previewSize = 300;
  static const int _previewMaxSide = 1024;

  late img.Image _workingImage;
  late img.Image _previewBaseImage;
  late Uint8List _workingPreviewBytes;
  late bool _hasTransparency;
  int _rotationQuarterTurns = 0;
  double _viewScale = 1.0;
  double _baseScale = 1.0;
  Offset _viewOffset = Offset.zero;
  Offset _baseOffset = Offset.zero;
  Offset _scaleStartFocalPoint = Offset.zero;
  @override
  void initState() {
    super.initState();
    final img.Image? decoded = img.decodeImage(widget.sourceBytes);
    _workingImage = decoded ?? img.Image(width: 1, height: 1);
    _previewBaseImage = _buildPreviewBaseImage(_workingImage);
    _workingPreviewBytes = Uint8List(0);
    _hasTransparency = _detectTransparency(_workingImage);
    _refreshWorkingPreview();
  }

  void _refreshWorkingPreview() {
    img.Image preview = _previewBaseImage;
    if (_rotationQuarterTurns != 0) {
      preview = _rotateByQuarterTurns(preview, _rotationQuarterTurns);
    }
    preview = _flattenOnWhite(preview);
    _workingPreviewBytes = Uint8List.fromList(img.encodePng(preview, level: 1));
  }

  img.Image _buildPreviewBaseImage(img.Image source) {
    final int maxSide = source.width > source.height ? source.width : source.height;
    if (maxSide <= _previewMaxSide) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: _previewMaxSide, interpolation: img.Interpolation.linear);
    }
    return img.copyResize(source, height: _previewMaxSide, interpolation: img.Interpolation.linear);
  }

  img.Image _rotateByQuarterTurns(img.Image source, int turns) {
    final int normalized = ((turns % 4) + 4) % 4;
    switch (normalized) {
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

  int get _layoutPreviewWidth => _rotationQuarterTurns.isEven ? _previewBaseImage.width : _previewBaseImage.height;
  int get _layoutPreviewHeight => _rotationQuarterTurns.isEven ? _previewBaseImage.height : _previewBaseImage.width;

  _PlacedRectPx _computePlacedRectPx({
    required double boxSize,
    required int sourceWidth,
    required int sourceHeight,
    required double offsetScale,
  }) {
    final double fitScale = sourceWidth > sourceHeight ? boxSize / sourceWidth : boxSize / sourceHeight;
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
        title: Text('匯入前處理 - ${widget.sourceName} (${widget.sourceFormat})'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PixelTheme.bgMid,
                border: Border.all(color: PixelTheme.border, width: 2),
              ),
              child: const Text(
                '先調整旋轉與裁切，再進入點陣圖。\n此流程不會強制拉伸比例。',
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: _previewSize,
                height: _previewSize,
                decoration: BoxDecoration(
                  color: _hasTransparency ? Colors.white : PixelTheme.bgMid,
                  border: Border.all(color: PixelTheme.border, width: 2),
                ),
                child: GestureDetector(
                  onScaleStart: (ScaleStartDetails details) {
                    _baseScale = _viewScale;
                    _baseOffset = _viewOffset;
                    _scaleStartFocalPoint = details.localFocalPoint;
                  },
                  onScaleUpdate: (ScaleUpdateDetails details) {
                    setState(() {
                      _viewScale = (_baseScale * details.scale).clamp(0.2, 4.0);
                      _viewOffset = _baseOffset + (details.localFocalPoint - _scaleStartFocalPoint);
                    });
                  },
                  child: ClipRect(
                    child: Center(
                      child: SizedBox(
                        width: _previewSize,
                        height: _previewSize,
                        child: Builder(
                          builder: (BuildContext context) {
                            final _PlacedRectPx rect = _computePlacedRectPx(
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
                                  child: Image.memory(
                                    _workingPreviewBytes,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.none,
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
                  label: '左轉 90°',
                  onPressed: () {
                    setState(() {
                      _rotationQuarterTurns = (_rotationQuarterTurns + 3) % 4;
                      _refreshWorkingPreview();
                    });
                  },
                ),
                _ToolButton(
                  label: '右轉 90°',
                  onPressed: () {
                    setState(() {
                      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
                      _refreshWorkingPreview();
                    });
                  },
                ),
                _ToolButton(
                  label: '重置位置/縮放',
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
            Text('手勢操作：單指拖曳位置、雙指縮放（固定比例）', style: TextStyle(color: PixelTheme.accent)),
            if (_hasTransparency) ...[
              const SizedBox(height: 8),
              Text('偵測到透明背景，預覽與輸出都會以白色底處理。', style: TextStyle(color: PixelTheme.accentBlue)),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    _ImagePreprocessResult(
                      image: _buildProcessedSquare(outputSize: 512),
                      usedBackgroundColor: _hasTransparency,
                      sourceName: widget.sourceName,
                      sourceFormat: widget.sourceFormat,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: PixelTheme.accent,
                  foregroundColor: PixelTheme.bgDark,
                ),
                child: const Text('套用裁切並繼續'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  img.Image _flattenOnWhite(img.Image source) {
    final img.Image flattened = img.Image(width: source.width, height: source.height);
    img.fill(flattened, color: img.ColorRgba8(255, 255, 255, 255));
    img.compositeImage(flattened, source);
    return flattened;
  }

  img.Image _buildProcessedSquare({required int outputSize}) {
    img.Image source = _flattenOnWhite(_workingImage);
    if (_rotationQuarterTurns != 0) {
      source = _rotateByQuarterTurns(source, _rotationQuarterTurns);
    }
    final img.Image flattened = img.Image(width: outputSize, height: outputSize);
    img.fill(
      flattened,
      color: img.ColorRgba8(255, 255, 255, 255),
    );

    final _PlacedRectPx previewRect = _computePlacedRectPx(
      boxSize: _previewSize,
      sourceWidth: _layoutPreviewWidth,
      sourceHeight: _layoutPreviewHeight,
      offsetScale: 1.0,
    );

    final double ratio = outputSize / _previewSize;

    int drawW = (previewRect.drawW * ratio).round();
    int drawH = (previewRect.drawH * ratio).round();
    if (drawW < 1) {
      drawW = 1;
    }
    if (drawH < 1) {
      drawH = 1;
    }

    final img.Image resized = img.copyResize(
      source,
      width: drawW,
      height: drawH,
      interpolation: img.Interpolation.linear,
    );

    final int dstX = (previewRect.dx * ratio).round();
    final int dstY = (previewRect.dy * ratio).round();

    _compositeImageClipped(
      destination: flattened,
      source: resized,
      dstX: dstX,
      dstY: dstY,
    );
    return flattened;
  }

  // Keep export behavior consistent with preview clipping when image is moved outside bounds.
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
          style: TextStyle(color: PixelTheme.accent, fontWeight: FontWeight.w900),
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
          border: Border.all(color: selected ? PixelTheme.textWhite : PixelTheme.border, width: 2),
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
          canvas.drawRect(
            Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH),
            p,
          );
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
  const _TextEditResult({required this.name, required this.link, required this.emoji});

  final String name;
  final String link;
  final String emoji;
}

class _PixelEditResult {
  const _PixelEditResult({required this.pixels, required this.status});

  final PixelGrid pixels;
  final String status;
}

class _ImagePreprocessResult {
  const _ImagePreprocessResult({
    required this.image,
    required this.usedBackgroundColor,
    required this.sourceName,
    required this.sourceFormat,
  });

  final img.Image image;
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

  Color get _previewTextColor => _preview.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  Color get _previewInputBgColor =>
      _preview.computeLuminance() > 0.5 ? Colors.black.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.16);

  @override
  Widget build(BuildContext context) {
    return _withUnifont(
      context,
      AlertDialog(
      backgroundColor: PixelTheme.bgMid,
      title: Text(widget.title, style: TextStyle(color: PixelTheme.textWhite)),
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
                    'HEX 色碼 (#RRGGBB)',
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
                      border: Border.all(color: _previewTextColor.withValues(alpha: 0.85), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: _previewTextColor.withValues(alpha: 0.25),
                          blurRadius: 0,
                          offset: const Offset(2, 2),
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _previewInputBgColor,
                        border: Border.all(color: _previewTextColor.withValues(alpha: 0.45)),
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
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(6),
                                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_preview),
          style: FilledButton.styleFrom(
            backgroundColor: PixelTheme.accent,
            foregroundColor: PixelTheme.bgDark,
          ),
          child: const Text('套用'),
        ),
      ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, Color active, ValueChanged<double> onChanged) {
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
            child: Slider(
              value: value,
              min: 0,
              max: 255,
              onChanged: onChanged,
            ),
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
    final Rect rect = Rect.fromCenter(center: center, width: size, height: size);

    final Paint shadow = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawRect(rect.shift(const Offset(2, 2)), shadow);

    final Paint fill = Paint()..color = sliderTheme.thumbColor ?? PixelTheme.accent;
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
  return '${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
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
  final img.Image flattened = img.Image(width: source.width, height: source.height);
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
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
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
