import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NfcLaunchEvidence { physicalTag, directLink, unknown }

class NfcScanRequest {
  const NfcScanRequest({
    required this.userId,
    this.physicalUid = '',
    this.expectedUserId,
    this.launchEvidence = NfcLaunchEvidence.unknown,
  });

  final String userId;
  final String physicalUid;
  final String? expectedUserId;
  final NfcLaunchEvidence launchEvidence;

  bool get hasUserIdMismatch =>
      expectedUserId != null && expectedUserId != userId;
}

class NfcDeepLinkService {
  NfcDeepLinkService._();

  static final NfcDeepLinkService instance = NfcDeepLinkService._();
  static const MethodChannel _nativeNfcLaunch = MethodChannel(
    'hitcon_nfc_battle/nfc_intent',
  );

  final AppLinks _appLinks = AppLinks();
  final StreamController<NfcScanRequest> _requests =
      StreamController<NfcScanRequest>.broadcast();

  NfcScanRequest? _pending;
  NfcScanRequest? _lastPublishedRequest;
  String? _expectedRescanUserId;
  Future<void> Function()? _startInAppScan;
  String _lastRequestKey = '';
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastAcceptedUri = '';
  DateTime _lastAcceptedUriAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _tagMaintenanceDepth = 0;
  DateTime _suppressTagRequestsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _initialized = false;

  Stream<NfcScanRequest> get requests => _requests.stream;
  bool get hasPending => _pending != null;

  void registerInAppScanStarter(Future<void> Function() startScan) {
    _startInAppScan = startScan;
  }

  Future<void> requestManualCollectionScan() async {
    _expectedRescanUserId = null;
    await _startInAppScan?.call();
  }

  Future<void> requestPhysicalRescan(String expectedUserId) async {
    final String normalized = expectedUserId.trim();
    if (normalized.isEmpty) {
      return;
    }
    _expectedRescanUserId = normalized;
    await _startInAppScan?.call();
  }

  void cancelPhysicalRescan() {
    _expectedRescanUserId = null;
  }

  Future<void> beginTagMaintenance() async {
    final bool shouldSuspendNativeDispatch = _tagMaintenanceDepth == 0;
    _tagMaintenanceDepth += 1;
    if (shouldSuspendNativeDispatch) {
      await _setNativeTagMaintenanceMode(true);
    }
  }

  Future<void> endTagMaintenance({
    Duration cooldown = const Duration(seconds: 3),
  }) async {
    if (_tagMaintenanceDepth > 0) {
      _tagMaintenanceDepth -= 1;
    }
    if (_tagMaintenanceDepth == 0) {
      final DateTime until = DateTime.now().add(cooldown);
      if (until.isAfter(_suppressTagRequestsUntil)) {
        _suppressTagRequestsUntil = until;
      }
      await _setNativeTagMaintenanceMode(false);
    }
  }

  Future<void> _setNativeTagMaintenanceMode(bool enabled) async {
    try {
      await _nativeNfcLaunch.invokeMethod<void>(
        'setTagMaintenanceMode',
        <String, Object?>{'enabled': enabled},
      );
    } on MissingPluginException {
      // Native foreground dispatch is Android-only.
    } on PlatformException {
      // NFC reader sessions remain usable on platforms without this bridge.
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _appLinks.uriLinkStream.listen((Uri uri) {
      unawaited(acceptUri(uri));
    });
    try {
      final Uri? initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        await acceptUri(initialLink);
      }
    } on PlatformException {
      // A foreground NFC session can still deliver the scan request.
    }
  }

  Future<void> acceptUri(Uri uri) async {
    final bool validTarget =
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.toLowerCase() == 'game.hitcon2026.online' &&
        !uri.hasPort &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        (uri.path == '/b' || uri.path == '/b/');
    final String userId = uri.queryParameters['u']?.trim() ?? '';
    final bool validUserId =
        userId.isNotEmpty &&
        userId.length <= 128 &&
        !userId.contains(RegExp(r'[\x00-\x1F\x7F]'));
    if (!validTarget || !validUserId) {
      return;
    }

    final DateTime now = DateTime.now();
    final String uriKey = uri.toString();
    if (uriKey == _lastAcceptedUri &&
        now.difference(_lastAcceptedUriAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastAcceptedUri = uriKey;
    _lastAcceptedUriAt = now;

    final _NfcLaunchData launch = await _takeNativeLaunchData();
    publish(
      NfcScanRequest(
        userId: userId,
        physicalUid: launch.uid,
        launchEvidence: launch.evidence,
      ),
    );
  }

  void publish(NfcScanRequest request) {
    if (_isTagMaintenanceSuppressed) {
      return;
    }
    final String userId = request.userId.trim();
    if (userId.isEmpty) {
      return;
    }
    final String physicalUid = request.physicalUid.trim().toUpperCase();
    final String? expectedUserId = physicalUid.isEmpty
        ? null
        : _expectedRescanUserId;
    final NfcScanRequest normalized = NfcScanRequest(
      userId: userId,
      physicalUid: physicalUid,
      expectedUserId: expectedUserId,
      launchEvidence: physicalUid.isNotEmpty
          ? NfcLaunchEvidence.physicalTag
          : request.launchEvidence,
    );
    final DateTime now = DateTime.now();
    final NfcScanRequest? previous = _lastPublishedRequest;
    if (normalized.physicalUid.isEmpty &&
        previous != null &&
        previous.userId == normalized.userId &&
        previous.physicalUid.isNotEmpty &&
        now.difference(_lastRequestAt) < const Duration(seconds: 3)) {
      return;
    }
    if (expectedUserId == userId) {
      _expectedRescanUserId = null;
    }
    final String key =
        '${normalized.userId}|${normalized.physicalUid}|${normalized.expectedUserId ?? ''}|${normalized.launchEvidence.name}';
    if (key == _lastRequestKey &&
        now.difference(_lastRequestAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastRequestKey = key;
    _lastRequestAt = now;
    _lastPublishedRequest = normalized;
    _pending = normalized;
    _requests.add(normalized);
  }

  NfcScanRequest? takePending() {
    final NfcScanRequest? request = _pending;
    _pending = null;
    return request;
  }

  bool get _isTagMaintenanceSuppressed =>
      _tagMaintenanceDepth > 0 ||
      DateTime.now().isBefore(_suppressTagRequestsUntil);

  @visibleForTesting
  void resetTagMaintenanceForTest() {
    _tagMaintenanceDepth = 0;
    _suppressTagRequestsUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _pending = null;
    _lastPublishedRequest = null;
    _lastRequestKey = '';
    _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<_NfcLaunchData> _takeNativeLaunchData() async {
    try {
      final Map<Object?, Object?>? result = await _nativeNfcLaunch
          .invokeMapMethod<Object?, Object?>('takeNfcLaunch');
      final String uid = (result?['uid'] as String? ?? '').trim().toUpperCase();
      if (result?['hasEvidence'] != true) {
        return const _NfcLaunchData(
          uid: '',
          evidence: NfcLaunchEvidence.unknown,
        );
      }
      final bool isNfcIntent = result?['isNfcIntent'] == true;
      return _NfcLaunchData(
        uid: uid,
        evidence: isNfcIntent
            ? NfcLaunchEvidence.physicalTag
            : NfcLaunchEvidence.directLink,
      );
    } on MissingPluginException {
      return const _NfcLaunchData(uid: '', evidence: NfcLaunchEvidence.unknown);
    } on PlatformException {
      return const _NfcLaunchData(uid: '', evidence: NfcLaunchEvidence.unknown);
    }
  }
}

class _NfcLaunchData {
  const _NfcLaunchData({required this.uid, required this.evidence});

  final String uid;
  final NfcLaunchEvidence evidence;
}
