import 'dart:async';

import 'package:nfc_manager/nfc_manager.dart';

import 'nfc_session_controller.dart';

typedef CollectionNtagHandler = Future<void> Function(String uid);

class CollectionNtagScanner {
  CollectionNtagScanner({
    required CollectionNtagHandler onTagDiscovered,
    required String alertMessage,
    bool autoRestart = true,
  }) : _onTagDiscovered = onTagDiscovered,
       _alertMessage = alertMessage,
       _autoRestart = autoRestart;

  final CollectionNtagHandler _onTagDiscovered;
  final String _alertMessage;
  final bool _autoRestart;

  bool _isScanning = false;
  bool _isHandling = false;
  bool _isDisposed = false;
  bool _isStoppingSession = false;
  NfcSessionLease? _nfcLease;
  String _lastTagId = '';
  DateTime _lastReadTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (_isDisposed || _isScanning) {
      return;
    }

    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable || _isDisposed) {
      return;
    }

    final NfcSessionLease? lease = await NfcSessionController.instance.acquire(
      NfcSessionOwner.collectionScanner,
      onPreempt: _stopForPreempt,
    );
    if (lease == null) {
      await _restartLaterIfEnabled(const Duration(milliseconds: 800));
      return;
    }

    _nfcLease = lease;
    _isScanning = true;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        alertMessage: _alertMessage,
        onDiscovered: (NfcTag tag) async {
          if (!lease.isActive || _isHandling || _isDisposed) {
            return;
          }

          final String uid = _readTagId(tag);
          final DateTime now = DateTime.now();
          final bool isDuplicate =
              uid.isNotEmpty &&
              uid == _lastTagId &&
              now.difference(_lastReadTime).inMilliseconds < 1200;
          if (isDuplicate) {
            return;
          }

          _lastTagId = uid;
          _lastReadTime = now;
          _isHandling = true;

          try {
            _isStoppingSession = true;
            try {
              await NfcManager.instance.stopSession();
            } finally {
              _isStoppingSession = false;
              _isScanning = false;
              _releaseLease(lease);
            }

            try {
              await _onTagDiscovered(uid);
            } catch (_) {
              // Keep collection scanning alive even if pairing/fetching fails.
            }
          } finally {
            _isStoppingSession = false;
            _isHandling = false;
          }

          await _restartLaterIfEnabled(const Duration(milliseconds: 350));
        },
        onError: (_) async {
          if (_isStoppingSession || !lease.isActive || _isDisposed) {
            return;
          }

          await NfcManager.instance.stopSession();
          _isScanning = false;
          _releaseLease(lease);
          await _restartLaterIfEnabled(const Duration(milliseconds: 800));
        },
      );
    } catch (_) {
      _isScanning = false;
      _releaseLease(lease);
      await _restartLaterIfEnabled(const Duration(milliseconds: 800));
    }
  }

  void dispose() {
    _isDisposed = true;
    final NfcSessionLease? lease = _nfcLease;
    _nfcLease = null;
    unawaited(
      NfcManager.instance
          .stopSession()
          .catchError((_) {})
          .whenComplete(() => lease?.release()),
    );
  }

  Future<void> _stopForPreempt() async {
    _isScanning = false;
    _isHandling = false;
    _nfcLease = null;
    _isStoppingSession = true;
    try {
      await NfcManager.instance.stopSession();
    } finally {
      _isStoppingSession = false;
    }

    if (_autoRestart) {
      unawaited(_restartLater(const Duration(milliseconds: 800)));
    }
  }

  Future<void> _restartLaterIfEnabled(Duration delay) async {
    if (!_autoRestart) {
      return;
    }

    await _restartLater(delay);
  }

  Future<void> _restartLater(Duration delay) async {
    if (_isDisposed) {
      return;
    }

    await Future<void>.delayed(delay);
    await start();
  }

  void _releaseLease(NfcSessionLease lease) {
    if (identical(_nfcLease, lease)) {
      _nfcLease = null;
    }
    lease.release();
  }

  String _readTagId(NfcTag tag) {
    final Map<String, dynamic> data = tag.data;
    final dynamic idBytes =
        data['nfca']?['identifier'] ??
        data['mifare']?['identifier'] ??
        data['mifareclassic']?['identifier'] ??
        data['mifareultralight']?['identifier'] ??
        data['iso7816']?['identifier'] ??
        data['iso15693']?['identifier'];

    if (idBytes is! List) {
      return '';
    }

    final Iterable<int> values = idBytes.whereType<int>();
    return values
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }
}
