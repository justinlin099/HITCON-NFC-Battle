import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/mock_api_service.dart';
import '../../services/setup_service.dart';
import '../user/pixel_theme.dart';

class TestLoginPage extends StatefulWidget {
  const TestLoginPage({super.key});

  @override
  State<TestLoginPage> createState() => _TestLoginPageState();
}

class _TestLoginPageState extends State<TestLoginPage> {
  static const MethodChannel _appActionsChannel = MethodChannel(
    'hitcon_nfc_battle/app_actions',
  );

  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = false;
  String _status = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('loginPrompt');
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    final ThemeData base = Theme.of(context);
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double layoutTextScale = _layoutTextScale(mediaQuery.size);
    final double systemTextScale = mediaQuery.textScaler.scale(1);
    final MediaQueryData responsiveMediaQuery = mediaQuery.copyWith(
      textScaler: TextScaler.linear(
        (systemTextScale * layoutTextScale).clamp(0.8, 2.0),
      ),
    );
    final ThemeData pixelTheme = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Unifont'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Unifont'),
      scaffoldBackgroundColor: PixelTheme.bgDark,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PixelTheme.bgDark,
        hintStyle: TextStyle(color: PixelTheme.textGray),
        contentPadding: const EdgeInsets.all(12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelTheme.border, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelTheme.accentBlue, width: 3),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: PixelTheme.textGray, width: 2),
        ),
      ),
    );

    return MediaQuery(
      data: responsiveMediaQuery,
      child: Theme(
        data: pixelTheme,
        child: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: <Widget>[
                _LoginHeader(status: _status),
                const SizedBox(height: 18),
                _LoginPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _PixelSectionTitle(label: context.l10n.tr('loginToken')),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenController,
                        minLines: 3,
                        maxLines: 6,
                        cursorColor: PixelTheme.accent,
                        style: TextStyle(
                          color: PixelTheme.textWhite,
                          fontFamily: 'Unifont',
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          hintText: context.l10n.tr('loginTokenHint'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PixelLoginButton(
                        onPressed: _isLoading
                            ? null
                            : () => _loginWithRawToken(_tokenController.text),
                        icon: Icons.login_rounded,
                        label: context.l10n.tr(
                          _isLoading ? 'signingIn' : 'signIn',
                        ),
                        accent: PixelTheme.accent,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _PixelLoginButton(
                              onPressed: _isLoading ? null : _scanQrWithCamera,
                              icon: Icons.qr_code_scanner_rounded,
                              label: context.l10n.tr('scanQr'),
                              accent: PixelTheme.accentBlue,
                              compact: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PixelLoginButton(
                              onPressed: _isLoading ? null : _importQrImage,
                              icon: Icons.image_search_rounded,
                              label: context.l10n.tr('importQr'),
                              accent: PixelTheme.accentBlue,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _PixelLoginButton(
                        onPressed: _openGmail,
                        icon: Icons.mail_rounded,
                        label: context.l10n.tr('openGmail'),
                        accent: PixelTheme.textWhite,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PixelTheme.bgMid,
                    border: Border.all(color: PixelTheme.border, width: 2),
                  ),
                  child: Text(
                    context.l10n.tr('loginEmailHint'),
                    style: TextStyle(
                      color: PixelTheme.textGray,
                      fontFamily: 'Unifont',
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
                if (AppConfig.useMockServices) ...<Widget>[
                  const SizedBox(height: 18),
                  _LoginPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _PixelSectionTitle(label: context.l10n.tr('mockLogin')),
                        const SizedBox(height: 12),
                        _MockLoginButton(
                          label: context.l10n.tr('administrator'),
                          onPressed: _isLoading
                              ? null
                              : () => _handleLogin('ADMIN'),
                        ),
                        const SizedBox(height: 10),
                        _MockLoginButton(
                          label: context.l10n.tr('attendee'),
                          onPressed: _isLoading
                              ? null
                              : () => _handleLogin('USER'),
                        ),
                        const SizedBox(height: 10),
                        _MockLoginButton(
                          label: context.l10n.tr('staff'),
                          onPressed: _isLoading
                              ? null
                              : () => _handleLogin('EVENT_STAFF'),
                        ),
                        const SizedBox(height: 10),
                        _PixelLoginButton(
                          onPressed: _resetMockData,
                          icon: Icons.refresh_rounded,
                          label: context.l10n.tr('resetMockData'),
                          accent: PixelTheme.warning,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _layoutTextScale(Size size) {
    if (size.shortestSide >= 600 && size.height >= 700) {
      return 1.45;
    }
    if (size.width >= 360 && size.height >= 780) {
      return 1.3;
    }
    if (size.width >= 360 && size.height >= 680) {
      return 1.18;
    }
    return 1;
  }

  Future<void> _scanQrWithCamera() async {
    final String? value = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _QrScannerPage()),
    );
    if (value == null || value.trim().isEmpty) {
      return;
    }
    _tokenController.text = _extractToken(value);
    await _loginWithRawToken(value);
  }

  Future<void> _importQrImage() async {
    final AppLocalizations l10n = context.l10n;
    setState(() {
      _status = l10n.tr('readingQrImage');
    });

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final String? path = result?.files.single.path;
    if (path == null) {
      setState(() {
        _status = l10n.tr('importCanceled');
      });
      return;
    }

    final MobileScannerController controller = MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    );
    try {
      final BarcodeCapture? capture = await controller.analyzeImage(
        path,
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      );
      final String? value = capture?.barcodes
          .map((Barcode barcode) => barcode.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (value == null || value.trim().isEmpty) {
        _showError(l10n.tr('tokenQrNotFound'));
        return;
      }
      _tokenController.text = _extractToken(value);
      await _loginWithRawToken(value);
    } catch (error) {
      _showError(l10n.tr('qrReadFailed', <String, Object?>{'error': error}));
    } finally {
      unawaited(controller.dispose());
    }
  }

  Future<void> _openGmail() async {
    final Uri webUri = Uri.parse('https://mail.google.com/');
    if (await _openDefaultEmailApp()) {
      return;
    }
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  Future<bool> _openDefaultEmailApp() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await _appActionsChannel.invokeMethod<bool>('openEmailApp') ??
            false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }

    final Uri mailUri = Uri(scheme: 'mailto');
    if (!await canLaunchUrl(mailUri)) {
      return false;
    }
    return launchUrl(mailUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _loginWithRawToken(String raw) async {
    final AppLocalizations l10n = context.l10n;
    final String token = _extractToken(raw);
    if (token.isEmpty) {
      _showError(l10n.tr('tokenRequired'));
      return;
    }

    setState(() {
      _isLoading = true;
      _status = l10n.tr('signingIn');
    });

    try {
      final bool success = await AuthService().loginWithToken(token);
      if (!mounted) {
        return;
      }
      if (!success) {
        _showError(l10n.tr('loginFailedToken'));
        return;
      }
      await _goNext();
    } catch (error) {
      if (mounted) {
        _showError(l10n.tr('loginFailed', <String, Object?>{'error': error}));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogin(String userType) async {
    setState(() {
      _isLoading = true;
      _status = context.l10n.tr('mockSigningIn');
    });

    try {
      final bool success = await AuthService().login(userType);
      if (!mounted) {
        return;
      }
      if (!success) {
        _showError(context.l10n.tr('mockLoginFailed'));
        return;
      }
      await _goNext();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _goNext() async {
    final AuthService authService = AuthService();
    final String? userId = authService.currentUserId;
    final bool setupComplete =
        userId != null && await SetupService().isComplete(userId);
    if (!mounted) {
      return;
    }
    final String routeName = authService.isRegularUser
        ? (setupComplete ? '/collection' : '/setup')
        : '/admin';
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  String _extractToken(String raw) {
    final String trimmed = raw.trim();
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasQuery) {
      for (final String key in <String>[
        'token',
        'jwt',
        'access_token',
        'login_token',
      ]) {
        final String? value = uri.queryParameters[key];
        if (value != null && value.trim().isNotEmpty) {
          return _extractToken(value);
        }
      }
    }

    final RegExp bearer = RegExp(
      r'Bearer\s+([A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+)',
      caseSensitive: false,
    );
    final RegExp jwt = RegExp(
      r'([A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+)',
    );
    return bearer.firstMatch(trimmed)?.group(1) ??
        jwt.firstMatch(trimmed)?.group(1) ??
        trimmed;
  }

  void _showError(String message) {
    setState(() {
      _status = message;
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Unifont',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: PixelTheme.warning,
      ),
    );
  }

  void _resetMockData() {
    MockApiService.resetMockData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: PixelTheme.bgMid,
        content: Text(
          context.l10n.tr('mockDataReset'),
          style: TextStyle(
            color: PixelTheme.accent,
            fontFamily: 'Unifont',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    final ThemeData base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: 'Unifont'),
        primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Unifont'),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          titleTextStyle: TextStyle(
            color: PixelTheme.accent,
            fontFamily: 'Unifont',
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
          title: Text(context.l10n.tr('scanLoginQr')),
          actions: <Widget>[
            _PixelToolButton(
              onPressed: _controller.toggleTorch,
              icon: Icons.flash_on_rounded,
              tooltip: 'Flash',
            ),
            const SizedBox(width: 6),
            _PixelToolButton(
              onPressed: _controller.switchCamera,
              icon: Icons.cameraswitch_rounded,
              tooltip: 'Camera',
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: Stack(
          children: <Widget>[
            MobileScanner(controller: _controller, onDetect: _handleDetect),
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: PixelTheme.accent, width: 4),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: PixelTheme.accent.withValues(alpha: 0.25),
                      blurRadius: 0,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PixelTheme.bgMid.withValues(alpha: 0.92),
                  border: Border(
                    top: BorderSide(color: PixelTheme.accent, width: 3),
                  ),
                ),
                child: Text(
                  context.l10n.tr('qrFrameHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PixelTheme.textWhite,
                    fontFamily: 'Unifont',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    final String? value = capture.barcodes
        .map((Barcode barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null || value.trim().isEmpty) {
      return;
    }
    _handled = true;
    Navigator.of(context).pop(value);
  }
}

class _PixelToolButton extends StatelessWidget {
  const _PixelToolButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(color: PixelTheme.accent, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: PixelTheme.accent, size: 19),
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PixelTheme.accent,
                border: Border.all(color: PixelTheme.textWhite, width: 2),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(4, 4),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/app_icon/app_icon_master.png',
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'HITCON\nNFC BATTLE',
                style: TextStyle(
                  color: PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: PixelTheme.bgMid,
            border: Border(
              left: BorderSide(color: PixelTheme.accentBlue, width: 4),
            ),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontFamily: 'Unifont',
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _PixelSectionTitle extends StatelessWidget {
  const _PixelSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(width: 8, height: 8, color: PixelTheme.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontFamily: 'Unifont',
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.accent, width: 3),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(5, 5)),
        ],
      ),
      child: child,
    );
  }
}

class _MockLoginButton extends StatelessWidget {
  const _MockLoginButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _PixelLoginButton(
      onPressed: onPressed,
      icon: Icons.person_rounded,
      label: label,
      accent: PixelTheme.accentBlue,
    );
  }
}

class _PixelLoginButton extends StatefulWidget {
  const _PixelLoginButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.accent,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color accent;
  final bool compact;

  @override
  State<_PixelLoginButton> createState() => _PixelLoginButtonState();
}

class _PixelLoginButtonState extends State<_PixelLoginButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    final Color color = enabled ? widget.accent : PixelTheme.textGray;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: Transform.translate(
          offset: _pressed ? const Offset(3, 3) : Offset.zero,
          child: Container(
            height: widget.compact ? 46 : 48,
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12),
            decoration: BoxDecoration(
              color: enabled ? PixelTheme.bgDark : PixelTheme.bgLight,
              border: Border.all(color: color, width: 2),
              boxShadow: <BoxShadow>[
                if (!_pressed)
                  const BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(4, 4),
                  ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(widget.icon, color: color, size: 18),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontFamily: 'Unifont',
                      fontSize: widget.compact ? 10 : 12,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
