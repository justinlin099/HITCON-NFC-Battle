import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/ntag_security_service.dart';
import '../../widgets/admin_mode_switch_button.dart';
import '../user/pixel_theme.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  @override
  void initState() {
    super.initState();
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    NfcManager.instance.stopSession();
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Unifont'),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: PixelTheme.bgDark,
          appBar: AppBar(
            backgroundColor: PixelTheme.bgMid,
            foregroundColor: PixelTheme.accent,
            leading: AdminModeSwitchButton(
              target: AdminModeTarget.gameplay,
              color: PixelTheme.accent,
            ),
            title: Text(context.l10n.tr('adminTools')),
            bottom: TabBar(
              indicatorColor: PixelTheme.accent,
              labelColor: PixelTheme.accent,
              unselectedLabelColor: PixelTheme.textGray,
              tabs: [
                Tab(text: context.l10n.tr('writeTag')),
                Tab(text: context.l10n.tr('confirmPrize')),
                Tab(text: context.l10n.tr('unlockTag')),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              AdminTagWriterPage(),
              AdminPrizeClaimPage(),
              AdminTagUnlockPage(),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminTagWriterPage extends StatefulWidget {
  const AdminTagWriterPage({super.key});

  @override
  State<AdminTagWriterPage> createState() => _AdminTagWriterPageState();
}

class _AdminTagWriterPageState extends State<AdminTagWriterPage> {
  static const String _blankAppUri = 'https://game.hitcon2026.online/b';

  String _status = '';
  String _lastUid = '-';
  bool _isWriting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('prepareWritableTag');
    }
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _writeTag() async {
    if (_isWriting) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
      });
      return;
    }

    setState(() {
      _isWriting = true;
      _status = l10n.tr('holdTagToWrite');
      _lastUid = '-';
    });

    await NfcManager.instance.stopSession();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String uid = _readTagId(tag);
        final Ndef? ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          await NfcManager.instance.stopSession();
          if (!mounted) {
            return;
          }
          setState(() {
            _isWriting = false;
            _lastUid = uid.isEmpty ? '-' : uid;
            _status = l10n.tr('tagNotWritable');
          });
          return;
        }

        try {
          await ndef.write(_buildTagMessage());
          await NfcManager.instance.stopSession();
          if (!mounted) {
            return;
          }
          setState(() {
            _isWriting = false;
            _lastUid = uid.isEmpty ? '-' : uid;
            _status = l10n.tr('writeComplete');
          });
        } catch (error) {
          await NfcManager.instance.stopSession();
          if (!mounted) {
            return;
          }
          setState(() {
            _isWriting = false;
            _lastUid = uid.isEmpty ? '-' : uid;
            _status = l10n.tr('writeFailed', <String, Object?>{'error': error});
          });
        }
      },
      onError: (dynamic error) async {
        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }
        setState(() {
          _isWriting = false;
          _status = l10n.tr('nfcError', <String, Object?>{'error': error});
        });
      },
    );
  }

  NdefMessage _buildTagMessage() {
    return NdefMessage(<NdefRecord>[_buildUriRecord(_blankAppUri)]);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: context.l10n.tr('fixedAppUrl'),
            children: [
              _StatusLine(
                label: context.l10n.tr('purpose'),
                value: context.l10n.tr('blankUrlPurpose'),
              ),
              _StatusLine(
                label: context.l10n.tr('notice'),
                value: context.l10n.tr('pairingUrlNotice'),
              ),
              _StatusLine(label: 'URL', value: _blankAppUri),
            ],
          ),
          const SizedBox(height: 12),
          _PixelPanel(
            title: context.l10n.tr('writeStatus'),
            children: [
              _StatusLine(label: context.l10n.tr('status'), value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(label: 'Landing URL', value: _previewLandingUrl),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: context.l10n.tr(
              _isWriting ? 'waitingForTagShort' : 'writeTag',
            ),
            color: PixelTheme.accent,
            onTap: _writeTag,
          ),
        ],
      ),
    );
  }

  String get _previewLandingUrl {
    return _blankAppUri;
  }
}

class AdminPrizeClaimPage extends StatefulWidget {
  const AdminPrizeClaimPage({super.key});

  @override
  State<AdminPrizeClaimPage> createState() => _AdminPrizeClaimPageState();
}

class _AdminPrizeClaimPageState extends State<AdminPrizeClaimPage> {
  final AuthService _authService = AuthService();
  String _status = '';
  String _lastUid = '-';
  String _lastUserId = '-';
  String _claimCode = '-';
  bool _isScanning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('claimScanPrompt');
    }
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _status = l10n.tr('scanAttendeeTag');
      _lastUid = '-';
      _lastUserId = '-';
      _claimCode = '-';
    });

    await NfcManager.instance.stopSession();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String uid = _readTagId(tag);
        final Map<String, String> records = await _readTextRecords(tag);
        final String userId = records['user_id'] ?? records['owner'] ?? '';
        final Map<String, dynamic>? result = await _authService
            .confirmPrizeClaim(tagUid: uid, userId: userId);

        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }

        setState(() {
          _isScanning = false;
          _lastUid = uid.isEmpty ? '-' : uid;
          _lastUserId = userId.isEmpty ? l10n.tr('tagHasNoUserId') : userId;
          if (result == null) {
            _status = l10n.tr('claimFailed');
            _claimCode = '-';
            return;
          }
          final bool alreadyClaimed = result['already_claimed'] == true;
          _status = l10n.tr(
            alreadyClaimed ? 'alreadyClaimed' : 'claimComplete',
          );
          _claimCode = result['claim_code'] as String? ?? '-';
        });
      },
      onError: (dynamic error) async {
        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }
        setState(() {
          _isScanning = false;
          _status = l10n.tr('nfcError', <String, Object?>{'error': error});
        });
      },
    );
  }

  Future<void> _stopScan() async {
    await NfcManager.instance.stopSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _status = context.l10n.tr('scanStopped');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: context.l10n.tr('claimConfirmation'),
            children: [
              _StatusLine(label: context.l10n.tr('status'), value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(label: 'User ID', value: _lastUserId),
              _StatusLine(
                label: context.l10n.tr('claimCode'),
                value: _claimCode,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: context.l10n.tr(_isScanning ? 'stopScan' : 'startScan'),
            color: _isScanning ? PixelTheme.warning : PixelTheme.accent,
            onTap: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
    );
  }
}

class AdminTagUnlockPage extends StatefulWidget {
  const AdminTagUnlockPage({super.key});

  @override
  State<AdminTagUnlockPage> createState() => _AdminTagUnlockPageState();
}

class _AdminTagUnlockPageState extends State<AdminTagUnlockPage> {
  static const NtagSecurityService _security = NtagSecurityService();

  String _status = '';
  String _lastUid = '-';
  bool _isUnlocking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('scanTagToUnlock');
    }
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _unlockTag() async {
    if (_isUnlocking) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
      });
      return;
    }

    setState(() {
      _isUnlocking = true;
      _status = l10n.tr('holdTagToUnlock');
      _lastUid = '-';
    });

    await NfcManager.instance.stopSession();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String uid = _security.readTagId(tag);
        final NtagLockSecret? secret = await AuthService()
            .requestNtagLockSecret(uid: uid, purpose: 'unlock');
        final NtagSecurityResult result = secret == null
            ? NtagSecurityResult(
                success: false,
                messageKey: 'adminUnlockSecretFailed',
              )
            : await _security.unlockForRewrite(tag, secret);

        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }

        setState(() {
          _isUnlocking = false;
          _lastUid = uid.isEmpty ? '-' : uid;
          _status = l10n.tr(result.messageKey, result.values);
        });
      },
      onError: (dynamic error) async {
        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }
        setState(() {
          _isUnlocking = false;
          _status = l10n.tr('nfcError', <String, Object?>{'error': error});
        });
      },
    );
  }

  Future<void> _stopUnlock() async {
    await NfcManager.instance.stopSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isUnlocking = false;
      _status = context.l10n.tr('unlockStopped');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: context.l10n.tr('unlockTag'),
            children: [
              _StatusLine(label: context.l10n.tr('status'), value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(
                label: context.l10n.tr('description'),
                value: context.l10n.tr('unlockTagDescription'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: context.l10n.tr(
              _isUnlocking ? 'stopScan' : 'unlockTagForRewrite',
            ),
            color: _isUnlocking ? PixelTheme.warning : PixelTheme.accent,
            onTap: _isUnlocking ? _stopUnlock : _unlockTag,
          ),
        ],
      ),
    );
  }
}

class _PixelPanel extends StatelessWidget {
  const _PixelPanel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.textWhite, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: PixelTheme.accent,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: PixelTheme.textGray,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PixelButton extends StatelessWidget {
  const _PixelButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(color: color, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

String _readTagId(NfcTag tag) {
  final Map<String, dynamic> data = tag.data;
  final dynamic idBytes =
      data['nfca']?['identifier'] ??
      data['mifareclassic']?['identifier'] ??
      data['mifareultralight']?['identifier'];

  if (idBytes is! List) {
    return '';
  }
  return idBytes
      .whereType<int>()
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join(':')
      .toUpperCase();
}

Future<Map<String, String>> _readTextRecords(NfcTag tag) async {
  final Ndef? ndef = Ndef.from(tag);
  final NdefMessage? message = ndef?.cachedMessage;
  final Map<String, String> records = <String, String>{};
  if (message == null) {
    return records;
  }

  for (final NdefRecord record in message.records) {
    if (record.typeNameFormat != NdefTypeNameFormat.nfcWellknown ||
        record.type.isEmpty ||
        record.type.first != 0x54 ||
        record.payload.length <= 1) {
      continue;
    }
    final String key = utf8.decode(record.identifier, allowMalformed: true);
    if (key.isEmpty) {
      continue;
    }
    final int languageCodeLength = record.payload.first & 0x3F;
    final int textStart = 1 + languageCodeLength;
    if (record.payload.length <= textStart) {
      continue;
    }
    records[key] = utf8.decode(
      record.payload.sublist(textStart),
      allowMalformed: true,
    );
  }
  return records;
}

NdefRecord _buildUriRecord(String uri) {
  const List<String> prefixes = <String>[
    '',
    'http://www.',
    'https://www.',
    'http://',
    'https://',
  ];

  int prefixIndex = 0;
  String body = uri;
  for (int i = prefixes.length - 1; i >= 0; i -= 1) {
    if (prefixes[i].isNotEmpty && uri.startsWith(prefixes[i])) {
      prefixIndex = i;
      body = uri.substring(prefixes[i].length);
      break;
    }
  }

  return NdefRecord(
    typeNameFormat: NdefTypeNameFormat.nfcWellknown,
    type: Uint8List.fromList(<int>[0x55]),
    identifier: Uint8List(0),
    payload: Uint8List.fromList(<int>[prefixIndex, ...utf8.encode(body)]),
  );
}
