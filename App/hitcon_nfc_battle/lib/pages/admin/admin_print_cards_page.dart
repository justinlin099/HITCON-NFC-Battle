import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../user/pixel_theme.dart';
import 'admin_pixel_widgets.dart';

class AdminPrintCardsPage extends StatefulWidget {
  const AdminPrintCardsPage({super.key});

  @override
  State<AdminPrintCardsPage> createState() => _AdminPrintCardsPageState();
}

class _AdminPrintCardsPageState extends State<AdminPrintCardsPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _tokenController = TextEditingController();

  Uint8List? _imageBytes;
  bool _isLoading = false;
  String _status = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('staffPrintScanPrompt');
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final String? token = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext context) => const _PrintTokenScannerPage(),
      ),
    );
    if (!mounted || token == null) {
      return;
    }
    _tokenController.text = token;
    await _download();
  }

  Future<void> _download() async {
    if (_isLoading) {
      return;
    }
    final String token = _tokenController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{8,32}$').hasMatch(token)) {
      setState(() {
        _status = context.l10n.tr('staffPrintTokenInvalid');
        _imageBytes = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = context.l10n.tr('staffPrintDownloading');
      _imageBytes = null;
    });
    final Uint8List? bytes = await _authService.downloadStaffPrintCard(token);
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _imageBytes = bytes;
      _status = context.l10n.tr(
        bytes == null ? 'staffPrintDownloadFailed' : 'staffPrintReady',
      );
    });
  }

  Future<void> _save() async {
    final Uint8List? bytes = _imageBytes;
    if (bytes == null) {
      return;
    }
    final String token = _tokenController.text.trim();
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.tr('staffPrintSaveDialog'),
      fileName: 'hitcon-print-card-$token.png',
      type: FileType.custom,
      allowedExtensions: const <String>['png'],
      bytes: bytes,
    );
    if (!mounted || path == null) {
      return;
    }
    setState(() {
      _status = context.l10n.tr('staffPrintSaved');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        AdminPixelPanel(
          title: context.l10n.tr('staffPrintCards'),
          children: <Widget>[
            Text(
              context.l10n.tr('staffPrintDescription'),
              style: TextStyle(
                color: PixelTheme.textGray,
                fontFamily: 'Unifont',
                fontSize: 11,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            AdminPixelTextField(
              controller: _tokenController,
              label: context.l10n.tr('staffPrintToken'),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                LengthLimitingTextInputFormatter(32),
              ],
              onSubmitted: (_) => _download(),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: AdminPixelButton(
                    label: context.l10n.tr('scanBarcode'),
                    icon: Icons.qr_code_scanner_rounded,
                    onPressed: _isLoading ? null : _scanBarcode,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AdminPixelButton(
                    label: context.l10n.tr('downloadPrintCard'),
                    icon: Icons.download_rounded,
                    color: PixelTheme.accentBlue,
                    onPressed: _isLoading ? null : _download,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdminStatusLine(label: context.l10n.tr('status'), value: _status),
          ],
        ),
        if (_imageBytes != null) ...<Widget>[
          const SizedBox(height: 14),
          AdminPixelPanel(
            title: context.l10n.tr('printPreview'),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image.memory(
                    _imageBytes!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AdminPixelButton(
                label: context.l10n.tr('savePng'),
                icon: Icons.save_alt_rounded,
                color: PixelTheme.success,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PrintTokenScannerPage extends StatefulWidget {
  const _PrintTokenScannerPage();

  @override
  State<_PrintTokenScannerPage> createState() => _PrintTokenScannerPageState();
}

class _PrintTokenScannerPageState extends State<_PrintTokenScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.code128],
  );
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final Barcode barcode in capture.barcodes) {
      final String token = (barcode.rawValue ?? '').trim();
      if (!RegExp(r'^[A-Za-z0-9_-]{8,32}$').hasMatch(token)) {
        continue;
      }
      _handled = true;
      Navigator.of(context).pop(token);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: PixelTheme.bgMid,
        foregroundColor: PixelTheme.accent,
        title: Text(
          context.l10n.tr('scanPrintBarcode'),
          style: const TextStyle(fontFamily: 'Unifont'),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.tr('flash'),
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on_rounded),
          ),
          IconButton(
            tooltip: context.l10n.tr('switchCamera'),
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(controller: _controller, onDetect: _handleDetect),
          Center(
            child: Container(
              width: 300,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: PixelTheme.accent, width: 4),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: PixelTheme.bgMid.withValues(alpha: 0.94),
              child: Text(
                context.l10n.tr('scanPrintBarcodeHint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: PixelTheme.textWhite,
                  fontFamily: 'Unifont',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
