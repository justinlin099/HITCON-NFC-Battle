import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'card_bio_codec.dart';
import 'local_collection_store.dart';
import 'local_profile_store.dart';
import 'nfc_battle_api_client.dart';
import 'ntag_security_service.dart';
import 'user_profile_fields.dart';

enum UserRole { admin, user, eventStaff, unknown }

extension UserRoleCapabilities on UserRole {
  bool get canCollectCards =>
      this == UserRole.user || this == UserRole.eventStaff;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  static const String _jwtKey = 'auth_jwt_token';
  static const String _legacyJwtKey = 'staging_jwt_token';
  static const String _stagingUserIdKey = 'staging_user_id';
  static const String _roleKey = 'auth_user_role';

  final NfcBattleApiClient _api = const NfcBattleApiClient();
  final CardBioCodec _cardBioCodec = const CardBioCodec();
  final LocalCollectionStore _localCollectionStore = LocalCollectionStore();
  final LocalProfileStore _localProfileStore = LocalProfileStore();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _currentUserId;
  UserRole _currentRole = UserRole.unknown;
  String? _jwtToken;
  Map<String, dynamic>? _userProfile;
  String? _lastAuthError;
  String? _lastApiErrorCode;
  int? _lastAuthStatusCode;
  String? _lastNtagSecretError;

  Future<bool> loginWithToken(String token) async {
    _lastAuthError = null;
    _lastAuthStatusCode = null;
    final String normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      _lastAuthError = 'Token is empty.';
      return false;
    }

    try {
      final Map<String, dynamic> claims = _decodeJwtClaims(normalizedToken);
      final String? userId = claims['sub'] as String?;
      if (userId == null || userId.trim().isEmpty) {
        _lastAuthError = 'Token does not contain a valid subject.';
        return false;
      }

      final Object? expiresAt = claims['exp'];
      if (expiresAt is num &&
          expiresAt.toInt() <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        _lastAuthError = 'Token has expired.';
        return false;
      }

      // A token can replace an already authenticated account without first
      // calling logout. Never let the previous account's profile survive that
      // transition, especially its paired tag and NFC credential.
      _userProfile = null;
      _jwtToken = normalizedToken;
      _currentUserId = userId;
      _currentRole = UserRole.unknown;

      final Map<String, dynamic>? profile = await fetchUserProfile();
      if (profile == null) {
        _jwtToken = null;
        _currentUserId = null;
        _userProfile = null;
        _currentRole = UserRole.unknown;
        return false;
      }

      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await _secureStorage.write(key: _jwtKey, value: normalizedToken);
        await prefs.remove(_legacyJwtKey);
        await prefs.setString(_stagingUserIdKey, _currentUserId!);
        await prefs.setString(_roleKey, _roleStorageValue(_currentRole));
      } catch (e) {
        _log('Authenticated session could not be persisted securely: $e');
      }
      return true;
    } catch (e) {
      _lastAuthError = e.toString();
      _log('Token login error: $e');
      _jwtToken = null;
      _currentUserId = null;
      _userProfile = null;
      _currentRole = UserRole.unknown;
      return false;
    }
  }

  Future<bool> restoreSession() async {
    if (_ensureSession()) {
      return true;
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = await _secureStorage.read(key: _jwtKey);
      final String? legacyToken = prefs.getString(_legacyJwtKey);
      if (token == null && legacyToken != null) {
        token = legacyToken;
        await _secureStorage.write(key: _jwtKey, value: legacyToken);
        await prefs.remove(_legacyJwtKey);
      }
      final String? userId = prefs.getString(_stagingUserIdKey);
      if (token == null) {
        return false;
      }

      final Map<String, dynamic> claims = _decodeJwtClaims(token);
      final String? tokenUserId = claims['sub'] as String?;
      final String restoredUserId = (tokenUserId ?? userId ?? '').trim();
      if (restoredUserId.isEmpty) {
        await logout();
        return false;
      }

      final Object? expiresAt = claims['exp'];
      if (expiresAt is num &&
          expiresAt.toInt() <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        await logout();
        return false;
      }

      _jwtToken = token;
      _currentUserId = restoredUserId;
      _currentRole = UserRole.unknown;
      _setRoleFromString((claims['role'] ?? '').toString().toUpperCase());
      if (_currentRole == UserRole.unknown) {
        _setRoleFromString((prefs.getString(_roleKey) ?? '').toUpperCase());
      }

      final Map<String, dynamic>? profile = await fetchUserProfile();
      if (profile != null) {
        await prefs.setString(_stagingUserIdKey, _currentUserId!);
        await prefs.setString(_roleKey, _roleStorageValue(_currentRole));
        return true;
      }

      if (_lastAuthStatusCode == 401 || _lastAuthStatusCode == 403) {
        await logout();
        return false;
      }

      _log(
        'Keeping the stored session because profile restoration failed '
        'without an authentication rejection.',
      );
      return true;
    } catch (e) {
      _log('Restore session error: $e');
      if (e is FormatException) {
        await logout();
      }
      return false;
    }
  }

  Future<void> logout() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _secureStorage.delete(key: _jwtKey);
      await prefs.remove(_legacyJwtKey);
      await prefs.remove(_stagingUserIdKey);
      await prefs.remove(_roleKey);

      _currentUserId = null;
      _jwtToken = null;
      _userProfile = null;
      _currentRole = UserRole.unknown;
      _lastAuthStatusCode = null;
    } catch (e) {
      _log('Logout error: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchUserProfile({
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    _lastAuthStatusCode = null;
    try {
      final Map<String, dynamic> result = await _api.get(
        '/users/me',
        token: _jwtToken!,
      );
      _userProfile = _normalizeProfile(result['data']);
      _currentUserId = _userProfile?['user_id'] as String? ?? _currentUserId;
      _setRoleFromApiRole(_userProfile?['role'] as String?);
      await _cacheUserProfile(_userProfile!);
      await _cachePairingState(_userProfile!);
      return _userProfile;
    } catch (e) {
      onError?.call(e);
      _lastAuthError = e.toString();
      _lastAuthStatusCode = e is ApiException ? e.statusCode : null;
      _log('Error fetching user profile: $e');
    }

    return null;
  }

  Future<bool> updateUserProfile(Map<String, dynamic> updates) async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return false;
    }

    try {
      final Map<String, dynamic> body = _profileUpdateForApi(updates);
      if (body.isEmpty) {
        return true;
      }
      final Map<String, dynamic> result = await _api.patch(
        '/users/me',
        token: _jwtToken!,
        body: body,
      );
      _userProfile = _normalizeProfile(result['data']);
      await _cachePairingState(_userProfile!);
      return true;
    } catch (e) {
      _log('Error updating user profile: $e');
    }

    return false;
  }

  Future<bool> pairNfcTag(String uid) async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return false;
    }

    try {
      await _api.post(
        '/tags/pair',
        token: _jwtToken!,
        body: <String, dynamic>{'physical_id': uid},
      );
      await fetchUserProfile();
      return true;
    } catch (e) {
      if (e is ApiException && e.statusCode == 409) {
        final Map<String, dynamic>? profile =
            _userProfile ?? await fetchUserProfile();
        final String pairedUid =
            (profile?['paired_ntag_uid'] as String? ??
                    profile?['physical_id'] as String? ??
                    '')
                .trim();
        if (_samePhysicalId(pairedUid, uid)) {
          _log(
            'NFC tag is already paired to current user; treating as success.',
          );
          return true;
        }
      }
      _log('Error pairing NFC tag: $e');
      return false;
    }
  }

  Future<NtagLockSecret?> requestNtagLockSecret({
    required String uid,
    required String purpose,
    String? userId,
  }) async {
    _lastNtagSecretError = null;
    if (!_ensureSession()) {
      _setNtagSecretError('No authenticated session is available.');
      return null;
    }
    if (uid.trim().isEmpty) {
      _setNtagSecretError('The phone could not read the physical Tag UID.');
      return null;
    }

    try {
      final String targetUserId = (userId ?? '').trim();
      if (purpose == 'unlock' && (isAdmin || isEventStaff)) {
        if (targetUserId.isEmpty) {
          _setNtagSecretError(
            'The Tag URL does not contain a user_id, so the STAFF API cannot identify its owner.',
          );
          return null;
        }
        final Map<String, dynamic> result = await _api.post(
          '/staff/nfc-unlock-code',
          token: _jwtToken!,
          body: <String, dynamic>{'user_id': targetUserId, 'uid': uid},
        );
        final NtagLockSecret? secret = _secretFromNfcTagKey(
          _jsonMap(result['data'])['unlock_code'],
        );
        if (secret == null) {
          _setNtagSecretError(
            'The STAFF API response did not contain a valid 12-digit unlock_code.',
          );
        }
        return secret;
      }

      final Map<String, dynamic>? profile =
          _userProfile ?? await fetchUserProfile();
      if (profile == null) {
        _setNtagSecretError('The current user profile could not be loaded.');
        return null;
      }
      if (purpose == 'unlock') {
        final String pairedUid =
            (profile['paired_ntag_uid'] as String? ??
                    profile['physical_id'] as String? ??
                    '')
                .trim()
                .toUpperCase();
        if (pairedUid.isNotEmpty && pairedUid != uid.trim().toUpperCase()) {
          _setNtagSecretError(
            'The scanned Tag UID does not match the Tag paired to this account.',
          );
          return null;
        }
      }
      final NtagLockSecret? secret = _secretFromNfcTagKey(
        profile['nfc_tag_key'],
      );
      if (secret == null) {
        _setNtagSecretError(
          'The user profile does not contain a valid 6-byte nfc_tag_key.',
        );
      }
      return secret;
    } catch (e) {
      _setNtagSecretError(e.toString());
    }

    return null;
  }

  void _setNtagSecretError(String reason) {
    _lastNtagSecretError = reason;
    debugPrint('[NtagUnlock] $reason');
  }

  Future<Map<String, dynamic>?> fetchCollectionRecords({
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    try {
      Object? profileError;
      final Map<String, dynamic>? profile = await fetchUserProfile(
        onError: (Object error) {
          profileError = error;
          onError?.call(error);
        },
      );
      final List<String>? collectionIds = _stringList(profile?['collection']);
      if (profile != null && collectionIds != null) {
        if (collectionIds.isEmpty) {
          return _collectionFromUsers(owner: profile, users: const <dynamic>[]);
        }

        final List<Map<String, dynamic>> cachedCards =
            await _localCollectionStore.loadCards(_currentUserId!);
        final List<Map<String, dynamic>>? refreshed =
            await _batchRefreshCollectedUsers(
              collectionIds: collectionIds,
              cachedCards: cachedCards,
            );
        if (refreshed != null) {
          return <String, dynamic>{
            'owner_display_name':
                profile['display_name'] ?? profile['user_id'] ?? '',
            'total_collected': refreshed.length,
            'collection': refreshed,
            'collection_version': profile['collection_version'] ?? 0,
          };
        }
      }

      if (profileError != null && isNetworkConnectionError(profileError!)) {
        return null;
      }

      return _fetchCollectionBootstrap(onError: onError);
    } catch (e) {
      onError?.call(e);
      _log('Error fetching collection records: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> _fetchCollectionBootstrap({
    void Function(Object error)? onError,
  }) async {
    try {
      final Map<String, dynamic> result = await _api.get(
        '/users/me/bootstrap',
        token: _jwtToken!,
      );
      final Map<String, dynamic> data = _jsonMap(result['data']);
      final Map<String, dynamic> me = _normalizeProfile(data['me']);
      _userProfile = me;
      await _cacheUserProfile(me);
      await _cachePairingState(me);
      return _collectionFromUsers(
        owner: me,
        users: (data['collected_users'] as List<dynamic>? ?? <dynamic>[]),
      );
    } catch (e) {
      onError?.call(e);
      _log('Error bootstrapping collection records: $e');
    }

    return null;
  }

  Future<List<Map<String, dynamic>>?> _batchRefreshCollectedUsers({
    required List<String> collectionIds,
    required List<Map<String, dynamic>> cachedCards,
  }) async {
    final Map<String, Map<String, dynamic>> cachedByUserId =
        <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> card in cachedCards)
            if (_profileUserId(card).isNotEmpty) _profileUserId(card): card,
        };
    final Map<String, Map<String, dynamic>> refreshedByUserId =
        <String, Map<String, dynamic>>{};

    for (int offset = 0; offset < collectionIds.length; offset += 100) {
      final List<String> chunk = collectionIds
          .skip(offset)
          .take(100)
          .toList(growable: false);
      final List<Map<String, dynamic>> requests = chunk
          .map((String userId) {
            final Map<String, dynamic> cached =
                cachedByUserId[userId] ?? <String, dynamic>{};
            return <String, dynamic>{
              'user_id': userId,
              if (cached['profile_version'] is num)
                'profile_version': (cached['profile_version'] as num).toInt(),
              if (cached['collection_version'] is num)
                'collection_version': (cached['collection_version'] as num)
                    .toInt(),
            };
          })
          .toList(growable: false);

      final Map<String, dynamic> response = await _api.post(
        '/users/batch',
        token: _jwtToken!,
        body: <String, dynamic>{'users': requests},
      );
      final List<dynamic> results =
          _jsonMap(response['data'])['results'] as List<dynamic>? ??
          <dynamic>[];
      for (final Object? rawResult in results) {
        final Map<String, dynamic> result = _jsonMap(rawResult);
        final String userId = (result['user_id'] as String? ?? '').trim();
        if (userId.isEmpty) {
          continue;
        }
        final Map<String, dynamic>? cached = cachedByUserId[userId];
        if (result['unchanged'] == true && cached != null) {
          refreshedByUserId[userId] = cached;
          continue;
        }

        final Map<String, dynamic> profile = _normalizeVisibleProfile(
          _jsonMap(result['data']),
        );
        if (_profileUserId(profile).isEmpty) {
          continue;
        }
        refreshedByUserId[userId] = _mergeRefreshedCard(
          cached,
          _cardFromProfile(profile),
        );
      }
    }

    final List<Map<String, dynamic>> refreshed = <Map<String, dynamic>>[];
    for (final String userId in collectionIds) {
      final Map<String, dynamic>? card =
          refreshedByUserId[userId] ?? cachedByUserId[userId];
      if (card != null) {
        refreshed.add(card);
      }
    }
    return refreshed.length == collectionIds.length ? refreshed : null;
  }

  Future<Map<String, dynamic>?> fetchStampMission({
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.get(
        '/missions/stamp',
        token: _jwtToken!,
      );
      return _jsonMap(result['data']);
    } catch (e) {
      onError?.call(e);
      _log('Error fetching stamp mission: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchMyPrize({
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession()) {
      return null;
    }

    _lastApiErrorCode = null;
    try {
      final Map<String, dynamic> result = await _api.get(
        '/users/me/prize',
        token: _jwtToken!,
      );
      return _jsonMap(result['data']);
    } catch (e) {
      onError?.call(e);
      _lastApiErrorCode = e is ApiException ? e.code : null;
      _log('Error fetching prize result: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> scanCollection({
    required String targetUserId,
    required String scannedNfcUid,
  }) async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    final String normalizedTargetUserId = targetUserId.trim();
    if (normalizedTargetUserId.isEmpty) {
      _log('Cannot scan collection without user_id from tag URL.');
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.post(
        '/collection/scan',
        token: _jwtToken!,
        body: <String, dynamic>{
          'user_id': normalizedTargetUserId,
          'physical_id': scannedNfcUid,
        },
      );
      final Map<String, dynamic> data = _jsonMap(result['data']);
      final Map<String, dynamic> profile = _normalizeProfile(data['profile']);
      final Map<String, dynamic> targetInfo = _cardFromProfile(
        profile,
        physicalUid: scannedNfcUid,
      );
      return <String, dynamic>{
        'status': 'success',
        'type': 'user_card',
        'data': <String, dynamic>{
          ...data,
          'profile': profile,
          'target_info': targetInfo,
        },
      };
    } catch (e) {
      _log('Error scanning collection: $e');
    }

    return null;
  }

  Future<bool> recordPhishing({required String attackerUserId}) async {
    if (!_ensureSession()) {
      return false;
    }
    final String victim = _currentUserId?.trim() ?? '';
    final String attacker = attackerUserId.trim();
    if (victim.isEmpty || attacker.isEmpty || victim == attacker) {
      return false;
    }

    try {
      await _api.post(
        '/collection/phishing',
        token: _jwtToken!,
        body: <String, dynamic>{'victim': victim, 'attacker': attacker},
      );
      return true;
    } catch (e) {
      _log('Error recording phishing event: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchUserCollection(
    String targetUserId, {
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession()) {
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.get(
        '/users/$targetUserId/collection',
        token: _jwtToken!,
      );
      final Map<String, dynamic> data = _jsonMap(result['data']);
      return _collectionFromUsers(
        owner: <String, dynamic>{
          'user_id': data['user_id'] ?? targetUserId,
          'collection_version': data['collection_version'] ?? 0,
        },
        users: data['users'] as List<dynamic>? ?? <dynamic>[],
      );
    } catch (e) {
      onError?.call(e);
      _log('Error fetching user collection: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> fetchPublicUserProfile(
    String targetUserId, {
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession() || targetUserId.trim().isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.get(
        '/users/$targetUserId',
        token: _jwtToken!,
      );
      return _normalizeVisibleProfile(_jsonMap(result['data']));
    } catch (e) {
      onError?.call(e);
      _log('Error fetching public user profile: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> fetchScoreboard({
    int offset = 0,
    int limit = 50,
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession()) {
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.get(
        '/scoreboard',
        token: _jwtToken!,
        query: <String, String>{'offset': '$offset', 'limit': '$limit'},
      );
      return _jsonMap(result['data']);
    } catch (e) {
      onError?.call(e);
      _log('Error fetching scoreboard: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchMyScoreboardRank({
    void Function(Object error)? onError,
  }) async {
    if (!_ensureSession()) {
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.get(
        '/scoreboard/me',
        token: _jwtToken!,
      );
      return _jsonMap(result['data']);
    } catch (e) {
      onError?.call(e);
      _log('Error fetching current scoreboard rank: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> submitCardPrintOrder({
    required Uint8List artworkPng,
    required Map<String, dynamic> metadata,
  }) async {
    if (!_ensureSession()) {
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.postMultipartFile(
        '/print-cards',
        token: _jwtToken!,
        fieldName: 'image',
        fileName: 'hitcon-nfc-card.png',
        contentType: 'image/png',
        bytes: artworkPng,
      );
      final String shortToken =
          (_jsonMap(result['data'])['short_token'] as String? ?? '').trim();
      if (shortToken.isEmpty) {
        return null;
      }
      return <String, dynamic>{
        'order_id': shortToken,
        'barcode_value': shortToken,
        'file_name': 'hitcon-nfc-card-$shortToken.png',
        'format':
            metadata['format'] as String? ?? 'EVOLIS_PRIMACY_CR80_300DPI_PNG',
      };
    } catch (e) {
      _log('Error submitting card print order: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> confirmPrizeClaim({
    required String tagUid,
    required String userId,
  }) async {
    if (!_ensureSession()) {
      return null;
    }

    final String normalizedUid = tagUid.trim();
    final String normalizedUserId = userId.trim();
    if (normalizedUid.isEmpty || normalizedUserId.isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic> result = await _api.post(
        '/staff/prize-claims',
        token: _jwtToken!,
        body: <String, dynamic>{
          'user_id': normalizedUserId,
          'uid': normalizedUid,
        },
      );
      return <String, dynamic>{
        ..._jsonMap(result['data']),
        'already_claimed': false,
        'claim_code': _jsonMap(result['data'])['freeze_id'] as String? ?? '',
      };
    } catch (e) {
      if (e is ApiException && e.code == 'PRIZE_ALREADY_CLAIMED') {
        return <String, dynamic>{'already_claimed': true, 'claim_code': ''};
      }
      _log('Error claiming prize: $e');
      return null;
    }
  }

  Future<Uint8List?> downloadStaffPrintCard(String shortToken) async {
    if (!_ensureSession()) {
      return null;
    }
    final String token = shortToken.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{8,32}$').hasMatch(token)) {
      _lastAuthError = 'Invalid print-card token.';
      return null;
    }

    try {
      final Uint8List bytes = await _api.getBytes(
        '/staff/print-cards/${Uri.encodeComponent(token)}',
        token: _jwtToken!,
      );
      const List<int> pngSignature = <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ];
      if (bytes.length < pngSignature.length) {
        throw const FormatException('Downloaded print card is not a PNG.');
      }
      for (int index = 0; index < pngSignature.length; index += 1) {
        if (bytes[index] != pngSignature[index]) {
          throw const FormatException('Downloaded print card is not a PNG.');
        }
      }
      return bytes;
    } catch (e) {
      _lastAuthError = e.toString();
      _log('Error downloading staff print card: $e');
      return null;
    }
  }

  Future<bool> pairStaffUserTag({
    required String userId,
    required String uid,
  }) async {
    if (!_ensureSession()) {
      return false;
    }
    final String normalizedUserId = userId.trim();
    final String normalizedUid = uid.trim();
    if (normalizedUserId.isEmpty || normalizedUid.isEmpty) {
      return false;
    }

    try {
      await _api.post(
        '/staff/pair_user_tag',
        token: _jwtToken!,
        body: <String, dynamic>{
          'user_id': normalizedUserId,
          'physical_id': normalizedUid,
        },
      );
      return true;
    } catch (e) {
      _lastAuthError = e.toString();
      _log('Error pairing a staff-assigned user tag: $e');
      return false;
    }
  }

  Future<bool> unpairStaffUserTag({
    required String userId,
    required String uid,
  }) async {
    _lastAuthError = null;
    if (!_ensureSession()) {
      _lastAuthError = 'No authenticated session is available.';
      return false;
    }
    final String normalizedUserId = userId.trim();
    final String normalizedUid = uid.trim().toUpperCase();
    if (normalizedUserId.isEmpty || normalizedUid.isEmpty) {
      _lastAuthError = 'User ID and physical Tag UID are required.';
      return false;
    }

    try {
      await _api.post(
        '/staff/unpair_user_tag',
        token: _jwtToken!,
        body: <String, dynamic>{
          'user_id': normalizedUserId,
          'physical_id': normalizedUid,
        },
      );
      return true;
    } catch (e) {
      _lastAuthError = e.toString();
      _log('Error unpairing a staff-assigned user tag: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchStaffScoreboardStatus(
    String dangerToken,
  ) async {
    if (!_ensureSession() || dangerToken.trim().isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> result = await _api.get(
        '/staff/scoreboard_status',
        token: _jwtToken!,
        headers: _staffDangerHeaders(dangerToken),
      );
      return _jsonMap(result['data']);
    } catch (e) {
      _lastAuthError = e.toString();
      _log('Error fetching staff scoreboard status: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> freezeStaffScoreboard(
    String dangerToken,
  ) async {
    if (!_ensureSession() || dangerToken.trim().isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> result = await _api.post(
        '/staff/freeze_scoreboard',
        token: _jwtToken!,
        headers: _staffDangerHeaders(dangerToken),
      );
      return _jsonMap(result['data']);
    } catch (e) {
      _lastAuthError = e.toString();
      _log('Error freezing scoreboard: $e');
      return null;
    }
  }

  Future<bool> resumeStaffScoreboard(String dangerToken) async {
    if (!_ensureSession() || dangerToken.trim().isEmpty) {
      return false;
    }
    try {
      await _api.post(
        '/staff/resume_scoreboard',
        token: _jwtToken!,
        headers: _staffDangerHeaders(dangerToken),
      );
      return true;
    } catch (e) {
      _lastAuthError = e.toString();
      _log('Error resuming scoreboard: $e');
      return false;
    }
  }

  Map<String, String> _staffDangerHeaders(String dangerToken) {
    return <String, String>{'STAFF_DANGER_TOKEN': dangerToken.trim()};
  }

  Map<String, dynamic> _mergeRefreshedCard(
    Map<String, dynamic>? cached,
    Map<String, dynamic> refreshed,
  ) {
    if (cached == null) {
      return refreshed;
    }
    final String oldPhysicalUid = (cached['physical_uid'] as String? ?? '')
        .trim();
    final String refreshedPhysicalUid =
        (refreshed['physical_uid'] as String? ?? '').trim();
    final String userId = _profileUserId(refreshed);
    return <String, dynamic>{
      ...cached,
      ...refreshed,
      if (oldPhysicalUid.isNotEmpty &&
          (refreshedPhysicalUid.isEmpty || refreshedPhysicalUid == userId))
        'physical_uid': oldPhysicalUid,
      if (cached['collected_at'] != null)
        'collected_at': cached['collected_at'],
    };
  }

  String _profileUserId(Map<String, dynamic> profile) {
    return (profile['user_id'] as String? ?? profile['owner'] as String? ?? '')
        .trim();
  }

  List<String>? _stringList(Object? raw) {
    if (raw is! List) {
      return null;
    }
    return raw
        .whereType<String>()
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Map<String, dynamic> _profileUpdateForApi(Map<String, dynamic> updates) {
    final Map<String, dynamic> body = <String, dynamic>{};
    for (final String key in <String>['display_name', 'pixel_avatar_base64']) {
      if (updates.containsKey(key)) {
        body[key] = updates[key];
      }
    }
    if (updates.containsKey('emoji_icon')) {
      body['emoji_icon'] = updates['emoji_icon'];
    } else if (updates.containsKey('attribute_emoji')) {
      body['emoji_icon'] = updates['attribute_emoji'];
    }
    if (updates.containsKey('bio') ||
        updates.containsKey('link') ||
        updates.containsKey('card_color')) {
      body['bio'] = _cardBioCodec.encode(
        bio: _profileValue(updates, 'bio'),
        link: _profileValue(updates, 'link'),
        cardColor: updates.containsKey('card_color')
            ? updates['card_color']
            : _userProfile?['card_color'],
      );
    }
    body.removeWhere((String key, Object? value) => value == null);
    return body;
  }

  String _profileValue(Map<String, dynamic> updates, String key) {
    final Object? value = updates.containsKey(key)
        ? updates[key]
        : _userProfile?[key];
    return value is String ? value : '';
  }

  Map<String, dynamic> _normalizeProfile(Object? raw) {
    final Map<String, dynamic> profile = _jsonMap(raw);
    final int? phishingCount = readPhishingCount(profile);
    final CardBioData cardBio = _cardBioCodec.decode(profile['bio']);
    final String emoji =
        profile['attribute_emoji'] as String? ??
        profile['emoji_icon'] as String? ??
        '';
    final String? physicalId =
        profile['physical_id'] as String? ??
        profile['paired_ntag_uid'] as String?;

    final Map<String, dynamic> normalized = <String, dynamic>{
      ...profile,
      'bio': cardBio.bio,
      'emoji_icon': emoji,
      'attribute_emoji': emoji,
      'attribute_label':
          profile['attribute_label'] as String? ??
          profile['role'] as String? ??
          'ATTENDEE',
      'link': cardBio.link.isNotEmpty
          ? cardBio.link
          : profile['link'] as String? ?? '',
      if (cardBio.cardColor != null) 'card_color': cardBio.cardColor,
    };
    if (physicalId != null) {
      normalized['physical_id'] = physicalId;
      normalized['paired_ntag_uid'] = physicalId;
    }
    if (phishingCount == null) {
      normalized.remove('phishing_count');
    } else {
      normalized['phishing_count'] = phishingCount;
    }
    return normalized;
  }

  Map<String, dynamic> _collectionFromUsers({
    required Map<String, dynamic> owner,
    required List<dynamic> users,
  }) {
    final List<Map<String, dynamic>> cards = users
        .whereType<Object>()
        .map(_jsonMap)
        .map(_normalizeVisibleProfile)
        .map(_cardFromProfile)
        .toList(growable: false);
    return <String, dynamic>{
      'owner_display_name': owner['display_name'] ?? owner['user_id'] ?? '',
      'total_collected': cards.length,
      'collection': cards,
      'collection_version': owner['collection_version'] ?? 0,
    };
  }

  Map<String, dynamic> _normalizeVisibleProfile(Map<String, dynamic> profile) {
    final bool isFull =
        profile.containsKey('profile_version') ||
        profile.containsKey('pixel_avatar_base64') ||
        profile.containsKey('bio');
    return <String, dynamic>{
      ..._normalizeProfile(profile),
      '_profile_full': isFull,
    };
  }

  Map<String, dynamic> _cardFromProfile(
    Map<String, dynamic> profile, {
    String? physicalUid,
  }) {
    final String userId = profile['user_id'] as String? ?? '';
    final String uid =
        physicalUid ??
        profile['physical_id'] as String? ??
        profile['paired_ntag_uid'] as String? ??
        userId;
    return <String, dynamic>{
      ...profile,
      'physical_uid': uid,
      'owner': userId,
      'card_title': profile['display_name'] ?? userId,
      'collected_at': DateTime.now().toIso8601String(),
      'attribute_emoji': profile['attribute_emoji'] ?? profile['emoji_icon'],
      'attribute_label': profile['attribute_label'] ?? profile['role'],
      'link': profile['link'] ?? '',
    };
  }

  NtagLockSecret? _secretFromNfcTagKey(Object? raw) {
    final List<int>? key = _parseSecretBytes(raw, 6);
    if (key == null) {
      return null;
    }
    return NtagLockSecret(password: key.sublist(0, 4), pack: key.sublist(4, 6));
  }

  List<int>? _parseSecretBytes(dynamic value, int expectedLength) {
    if (value is List) {
      final List<int> bytes = value
          .whereType<num>()
          .map((num byte) => byte.toInt() & 0xFF)
          .toList(growable: false);
      return bytes.length == expectedLength ? bytes : null;
    }

    if (value is String) {
      final String normalized = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (normalized.length != expectedLength * 2) {
        return null;
      }
      return List<int>.generate(expectedLength, (int index) {
        final int offset = index * 2;
        return int.parse(normalized.substring(offset, offset + 2), radix: 16);
      }, growable: false);
    }

    return null;
  }

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((Object? key, Object? value) {
        return MapEntry<String, dynamic>(key.toString(), value);
      });
    }
    return <String, dynamic>{};
  }

  bool _samePhysicalId(String left, String right) {
    String normalize(String value) {
      return value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    }

    final String normalizedLeft = normalize(left);
    final String normalizedRight = normalize(right);
    return normalizedLeft.isNotEmpty && normalizedLeft == normalizedRight;
  }

  Future<void> _cacheUserProfile(Map<String, dynamic> profile) async {
    final String userId = (profile['user_id'] as String? ?? '').trim();
    if (userId.isEmpty || userId != _currentUserId) {
      return;
    }
    try {
      await _localProfileStore.save(userId, profile);
    } catch (error) {
      _log('Could not cache user profile for $userId: $error');
    }
  }

  Future<void> _cachePairingState(Map<String, dynamic> profile) async {
    final String userId = (profile['user_id'] as String? ?? '').trim();
    final bool hasPairingState =
        profile.containsKey('physical_id') ||
        profile.containsKey('paired_ntag_uid');
    if (userId.isEmpty || !hasPairingState || userId != _currentUserId) {
      return;
    }

    final Object? rawUid = profile.containsKey('physical_id')
        ? profile['physical_id']
        : profile['paired_ntag_uid'];
    final String pairedUid = rawUid is String ? rawUid.trim() : '';
    try {
      await _localProfileStore.save(userId, <String, dynamic>{
        'physical_id': pairedUid.isEmpty ? null : pairedUid,
        'paired_ntag_uid': pairedUid.isEmpty ? null : pairedUid,
      });
    } catch (error) {
      _log('Could not cache NFC pairing state for $userId: $error');
    }
  }

  Map<String, dynamic> _decodeJwtClaims(String token) {
    final List<String> parts = token.split('.');
    if (parts.length != 3) {
      throw const FormatException('Token is not a JWT.');
    }

    final String payload = parts[1];
    final String normalizedPayload = base64Url.normalize(payload);
    final String decodedPayload = utf8.decode(
      base64Url.decode(normalizedPayload),
    );
    return _jsonMap(jsonDecode(decodedPayload));
  }

  bool _ensureSession() {
    if (_jwtToken != null && _currentUserId != null) {
      return true;
    }
    return false;
  }

  void _setRoleFromString(String roleStr) {
    switch (roleStr) {
      case 'ADMIN':
        _currentRole = UserRole.admin;
        break;
      case 'EVENT_STAFF':
      case 'STAFF':
        _currentRole = UserRole.eventStaff;
        break;
      case 'USER':
      case 'ATTENDEE':
        _currentRole = UserRole.user;
        break;
      default:
        _currentRole = UserRole.unknown;
        break;
    }
  }

  void _setRoleFromApiRole(String? role) {
    _setRoleFromString(role ?? '');
  }

  String _roleStorageValue(UserRole role) {
    return switch (role) {
      UserRole.admin => 'ADMIN',
      UserRole.eventStaff => 'EVENT_STAFF',
      UserRole.user => 'USER',
      UserRole.unknown => '',
    };
  }

  void _log(String message) {
    if (AppConfig.enableDebugLogging) {
      debugPrint('[AuthService] $message');
    }
  }

  String? get currentUserId => _currentUserId;
  UserRole get currentRole => _currentRole;
  String? get jwtToken => _jwtToken;
  Map<String, dynamic>? get userProfile => _userProfile;
  int? get phishingCount => readPhishingCount(_userProfile);
  String? get lastAuthError => _lastAuthError;
  String? get lastApiErrorCode => _lastApiErrorCode;
  String? get lastNtagSecretError => _lastNtagSecretError;
  bool get isLoggedIn => _jwtToken != null && _currentUserId != null;
  bool get isAdmin => _currentRole == UserRole.admin;
  bool get isEventStaff => _currentRole == UserRole.eventStaff;
  bool get isRegularUser => _currentRole == UserRole.user;
  bool get canCollectCards => _currentRole.canCollectCards;
}
