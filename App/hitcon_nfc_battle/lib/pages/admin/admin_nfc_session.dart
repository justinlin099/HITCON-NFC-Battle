import 'dart:async';

import 'package:nfc_manager/nfc_manager.dart';

import '../../services/nfc_session_controller.dart';

class AdminNfcSession {
  AdminNfcSession({this.owner = NfcSessionOwner.ntagReader});

  final NfcSessionOwner owner;
  NfcSessionLease? _lease;

  Future<NfcSessionLease?> acquire({
    required NfcSessionCleanup onPreempt,
  }) async {
    late final NfcSessionLease? lease;
    lease = await NfcSessionController.instance.acquire(
      owner,
      preemptExisting: true,
      onPreempt: () async {
        if (identical(_lease, lease)) {
          _lease = null;
        }
        await _stopNfcSessionQuietly();
        await Future<void>.sync(onPreempt);
      },
    );
    if (lease == null || !lease.isActive) {
      return null;
    }

    _lease = lease;
    await _stopNfcSessionQuietly();
    if (!lease.isActive) {
      lease.release();
      if (identical(_lease, lease)) {
        _lease = null;
      }
      return null;
    }
    return lease;
  }

  Future<void> stop([NfcSessionLease? expectedLease]) async {
    if (expectedLease != null && !identical(_lease, expectedLease)) {
      return;
    }

    final NfcSessionLease? lease = _lease;
    _lease = null;
    if (lease == null || !lease.isActive) {
      lease?.release();
      return;
    }

    try {
      await _stopNfcSessionQuietly();
    } finally {
      lease.release();
    }
  }

  void dispose() {
    unawaited(stop());
  }
}

Future<void> _stopNfcSessionQuietly() async {
  try {
    await NfcManager.instance.stopSession();
  } catch (_) {
    // The platform session may already be closed.
  }
}
