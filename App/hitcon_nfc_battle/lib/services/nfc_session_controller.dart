import 'dart:async';

import 'package:flutter/foundation.dart';

enum NfcSessionOwner { appWideScanner, ntagReader, badgePairing }

extension NfcSessionOwnerLabel on NfcSessionOwner {
  String get label {
    switch (this) {
      case NfcSessionOwner.appWideScanner:
        return '全域遊戲掃描';
      case NfcSessionOwner.ntagReader:
        return 'NTag 讀寫工具';
      case NfcSessionOwner.badgePairing:
        return 'Badge 配對';
    }
  }

  int get priority {
    switch (this) {
      case NfcSessionOwner.appWideScanner:
        return 0;
      case NfcSessionOwner.ntagReader:
      case NfcSessionOwner.badgePairing:
        return 10;
    }
  }
}

typedef NfcSessionCleanup = FutureOr<void> Function();

class NfcSessionController {
  NfcSessionController._();

  static final NfcSessionController instance = NfcSessionController._();

  NfcSessionLease? _activeLease;
  Future<void> _mutation = Future<void>.value();

  NfcSessionOwner? get activeOwner => _activeLease?.owner;

  @visibleForTesting
  void resetForTest() {
    _activeLease?._markReleased();
    _activeLease = null;
    _mutation = Future<void>.value();
  }

  Future<NfcSessionLease?> acquire(
    NfcSessionOwner owner, {
    bool preemptExisting = false,
    NfcSessionCleanup? onPreempt,
  }) {
    return _locked(() async {
      final NfcSessionLease? current = _activeLease;
      if (current != null && current.isActive) {
        if (!preemptExisting || owner.priority < current.owner.priority) {
          return null;
        }

        _activeLease = null;
        current._markReleased();
        await current._notifyPreempted();
      }

      final NfcSessionLease lease = NfcSessionLease._(
        controller: this,
        owner: owner,
        onPreempt: onPreempt,
      );
      _activeLease = lease;
      return lease;
    });
  }

  void release(NfcSessionLease lease) {
    if (identical(_activeLease, lease)) {
      _activeLease = null;
    }
    lease._markReleased();
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();

    _mutation = _mutation
        .then((_) async {
          try {
            completer.complete(await action());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((_) {
          // Keep the lock chain alive even when a caller observes an error.
        });

    return completer.future;
  }
}

class NfcSessionLease {
  NfcSessionLease._({
    required NfcSessionController controller,
    required this.owner,
    NfcSessionCleanup? onPreempt,
  }) : _controller = controller,
       _onPreempt = onPreempt;

  final NfcSessionController _controller;
  final NfcSessionOwner owner;
  final NfcSessionCleanup? _onPreempt;

  bool _released = false;

  bool get isActive => !_released && identical(_controller._activeLease, this);

  void release() {
    _controller.release(this);
  }

  void _markReleased() {
    _released = true;
  }

  Future<void> _notifyPreempted() async {
    final NfcSessionCleanup? callback = _onPreempt;
    if (callback == null) {
      return;
    }

    try {
      await Future<void>.sync(callback);
    } catch (_) {
      // The new owner still gets a chance to start; if the platform session is
      // actually busy, that flow will surface the concrete startSession error.
    }
  }
}
