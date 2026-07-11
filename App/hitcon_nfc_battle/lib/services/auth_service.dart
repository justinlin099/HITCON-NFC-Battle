import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'card_bio_codec.dart';
import 'mock_api_service.dart';
import 'nfc_battle_api_client.dart';
import 'ntag_security_service.dart';
import 'staging_jwt_service.dart';

enum UserRole { admin, user, eventStaff, unknown }

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  static const String _stagingJwtKey = 'staging_jwt_token';
  static const String _stagingUserIdKey = 'staging_user_id';
  static const String _stagingUserRoleKey = 'staging_user_role';

  final NfcBattleApiClient _api = const NfcBattleApiClient();
  final CardBioCodec _cardBioCodec = const CardBioCodec();

  String? _currentUserId;
  UserRole _currentRole = UserRole.unknown;
  String? _jwtToken;
  Map<String, dynamic>? _userProfile;

  Future<bool> login(String userType) async {
    try {
      _log('Attempting login with userType: $userType');

      if (AppConfig.useMockServices) {
        return _mockLogin(userType);
      }

      final _StagingIdentity identity = _identityForUserType(userType);
      final String token = const StagingJwtService().createToken(
        userId: identity.userId,
        role: identity.apiRole,
      );

      _jwtToken = token;
      _currentUserId = identity.userId;
      _currentRole = identity.appRole;

      final Map<String, dynamic>? profile = await fetchUserProfile();
      if (profile == null) {
        return false;
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stagingJwtKey, token);
      await prefs.setString(_stagingUserIdKey, _currentUserId!);
      await prefs.setString(_stagingUserRoleKey, identity.apiRole);
      return true;
    } catch (e) {
      _log('Login error: $e');
      return false;
    }
  }

  Future<bool> loginWithToken(String token) async {
    final String normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return false;
    }

    try {
      final Map<String, dynamic> claims = _decodeJwtClaims(normalizedToken);
      final String? userId = claims['sub'] as String?;
      final String? role = claims['role'] as String?;
      if (userId == null || userId.trim().isEmpty) {
        return false;
      }

      _jwtToken = normalizedToken;
      _currentUserId = userId;
      _setRoleFromString(role ?? '');

      final Map<String, dynamic>? profile = await fetchUserProfile();
      if (profile == null) {
        _jwtToken = null;
        _currentUserId = null;
        _currentRole = UserRole.unknown;
        return false;
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stagingJwtKey, normalizedToken);
      await prefs.setString(_stagingUserIdKey, _currentUserId!);
      if (role != null) {
        await prefs.setString(_stagingUserRoleKey, role);
      }
      return true;
    } catch (e) {
      _log('Token login error: $e');
      _jwtToken = null;
      _currentUserId = null;
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
      if (AppConfig.useMockServices) {
        _jwtToken = prefs.getString('test_jwt_token');
        _currentUserId = prefs.getString('test_user_id');
        if (_jwtToken == null || _currentUserId == null) {
          return false;
        }
        final Map<String, dynamic>? profile = await fetchUserProfile();
        return profile != null;
      }

      final String? token = prefs.getString(_stagingJwtKey);
      final String? userId = prefs.getString(_stagingUserIdKey);
      final String? role = prefs.getString(_stagingUserRoleKey);
      if (token == null || userId == null) {
        return false;
      }

      _jwtToken = token;
      _currentUserId = userId;
      _setRoleFromString(role ?? '');

      final Map<String, dynamic>? profile = await fetchUserProfile();
      if (profile != null) {
        return true;
      }

      await logout();
      return false;
    } catch (e) {
      _log('Restore session error: $e');
      await logout();
      return false;
    }
  }

  Future<bool> _mockLogin(String userType) async {
    await MockApiService.saveTestJwt(userType);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _jwtToken = prefs.getString('test_jwt_token');
    _currentUserId = prefs.getString('test_user_id');
    _setRoleFromString(userType.toUpperCase());

    if (_currentUserId == null) {
      return false;
    }

    final Map<String, dynamic> profileResult =
        await MockApiService.getUserProfile(_currentUserId!);
    if (profileResult['status'] != 'success') {
      return false;
    }
    _userProfile = _normalizeProfile(profileResult['data']);
    return true;
  }

  Future<void> logout() async {
    try {
      if (AppConfig.useMockServices) {
        await MockApiService.clearTestData();
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_stagingJwtKey);
      await prefs.remove(_stagingUserIdKey);
      await prefs.remove(_stagingUserRoleKey);

      _currentUserId = null;
      _jwtToken = null;
      _userProfile = null;
      _currentRole = UserRole.unknown;
    } catch (e) {
      _log('Logout error: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchUserProfile() async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result = await MockApiService.getUserProfile(
          _currentUserId!,
        );
        if (result['status'] == 'success') {
          _userProfile = _normalizeProfile(result['data']);
          return _userProfile;
        }
      } else {
        final Map<String, dynamic> result = await _api.get(
          '/users/me',
          token: _jwtToken!,
        );
        _userProfile = _normalizeProfile(result['data']);
        _currentUserId = _userProfile?['user_id'] as String? ?? _currentUserId;
        _setRoleFromApiRole(_userProfile?['role'] as String?);
        return _userProfile;
      }
    } catch (e) {
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
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result =
            await MockApiService.updateUserProfile(_currentUserId!, body);
        if (result['status'] == 'success') {
          await fetchUserProfile();
          return true;
        }
      } else {
        final Map<String, dynamic> result = await _api.patch(
          '/users/me',
          token: _jwtToken!,
          body: body,
        );
        _userProfile = _normalizeProfile(result['data']);
        return true;
      }
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
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result = await MockApiService.pairTag(
          _currentUserId!,
          uid,
        );
        return result['status'] == 'success';
      }

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
  }) async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result =
            await MockApiService.getNtagLockSecret(
              uid: uid,
              purpose: purpose,
              requesterUserId: _currentUserId!,
            );
        if (result['status'] == 'success') {
          return _secretFromData(result['data']);
        }
      } else {
        final Map<String, dynamic>? profile =
            _userProfile ?? await fetchUserProfile();
        if (purpose == 'unlock') {
          final String pairedUid =
              (profile?['paired_ntag_uid'] as String? ??
                      profile?['physical_id'] as String? ??
                      '')
                  .trim()
                  .toUpperCase();
          if (pairedUid.isNotEmpty && pairedUid != uid.trim().toUpperCase()) {
            _log(
              'Server API only exposes the current user nfc_tag_key; cannot unlock another user tag uid=$uid paired=$pairedUid',
            );
            return null;
          }
        }
        return _secretFromNfcTagKey(profile?['nfc_tag_key']);
      }
    } catch (e) {
      _log('Error requesting NTAG secret: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> fetchCollectionRecords() async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result =
            await MockApiService.getCollectionRecords(_currentUserId!);
        if (result['status'] == 'success') {
          return result['data'] as Map<String, dynamic>;
        }
      } else {
        final Map<String, dynamic> result = await _api.get(
          '/users/me/bootstrap',
          token: _jwtToken!,
        );
        final Map<String, dynamic> data = _jsonMap(result['data']);
        final Map<String, dynamic> me = _normalizeProfile(data['me']);
        _userProfile = me;
        return _collectionFromUsers(
          owner: me,
          users: (data['collected_users'] as List<dynamic>? ?? <dynamic>[]),
        );
      }
    } catch (e) {
      _log('Error fetching collection records: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> fetchStampMission() async {
    if (!_ensureSession()) {
      _log('No user logged in');
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result =
            await MockApiService.getStampMission(_currentUserId!);
        return result['status'] == 'success' ? _jsonMap(result['data']) : null;
      }

      final Map<String, dynamic> result = await _api.get(
        '/missions/stamp',
        token: _jwtToken!,
      );
      return _jsonMap(result['data']);
    } catch (e) {
      _log('Error fetching stamp mission: $e');
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
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result = await MockApiService.scanCollection(
          currentUserId: _currentUserId!,
          targetUserId: normalizedTargetUserId,
          scannedNfcUid: scannedNfcUid,
        );
        return result['status'] == 'success' ? result : null;
      }

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
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result = await MockApiService.recordPhishing(
          victim: victim,
          attacker: attacker,
        );
        return result['status'] == 'success';
      }

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

  Future<Map<String, dynamic>?> fetchUserCollection(String targetUserId) async {
    if (!_ensureSession()) {
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result =
            await MockApiService.getUserCollection(targetUserId);
        return result['status'] == 'success'
            ? result['data'] as Map<String, dynamic>
            : null;
      }

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
      _log('Error fetching user collection: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> fetchPublicUserProfile(
    String targetUserId,
  ) async {
    if (!_ensureSession() || targetUserId.trim().isEmpty) {
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result = await MockApiService.getUserProfile(
          targetUserId,
        );
        return result['status'] == 'success'
            ? _normalizeVisibleProfile(_jsonMap(result['data']))
            : null;
      }

      final Map<String, dynamic> result = await _api.get(
        '/users/$targetUserId',
        token: _jwtToken!,
      );
      return _normalizeVisibleProfile(_jsonMap(result['data']));
    } catch (e) {
      _log('Error fetching public user profile: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> fetchScoreboard({
    int offset = 0,
    int limit = 50,
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
      _log('Error fetching scoreboard: $e');
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
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result =
            await MockApiService.submitCardPrintOrder(
              userId: _currentUserId!,
              artworkPng: artworkPng,
              metadata: metadata,
            );
        return result['status'] == 'success'
            ? result['data'] as Map<String, dynamic>
            : null;
      }
      _log('Card print order endpoint is not present in openapi.yaml.');
    } catch (e) {
      _log('Error submitting card print order: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>?> confirmPrizeClaim({
    required String tagUid,
    required String userId,
  }) async {
    if (!_ensureSession()) {
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final Map<String, dynamic> result =
            await MockApiService.confirmPrizeClaim(
              tagUid: tagUid,
              userId: userId,
              staffUserId: _currentUserId!,
            );
        return result['status'] == 'success'
            ? result['data'] as Map<String, dynamic>
            : null;
      }
      _log('Prize claim endpoint is not present in openapi.yaml.');
    } catch (e) {
      _log('Error confirming prize claim: $e');
    }

    return null;
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

  NtagLockSecret? _secretFromData(Object? raw) {
    final Map<String, dynamic> data = _jsonMap(raw);
    final List<int>? password = _parseSecretBytes(data['password'], 4);
    final List<int>? pack = _parseSecretBytes(data['pack'], 2);
    if (password == null || pack == null) {
      return null;
    }
    return NtagLockSecret(password: password, pack: pack);
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

  _StagingIdentity _identityForUserType(String userType) {
    switch (userType.toUpperCase()) {
      case 'ADMIN':
        return const _StagingIdentity(
          userId: 'staging_admin',
          apiRole: 'STAFF',
          appRole: UserRole.admin,
        );
      case 'EVENT_STAFF':
      case 'STAFF':
        return const _StagingIdentity(
          userId: 'staging_staff',
          apiRole: 'STAFF',
          appRole: UserRole.eventStaff,
        );
      case 'USER':
      default:
        return const _StagingIdentity(
          userId: 'staging_attendee',
          apiRole: 'ATTENDEE',
          appRole: UserRole.user,
        );
    }
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
    if (_currentRole == UserRole.admin) {
      return;
    }
    _setRoleFromString(role ?? '');
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
  bool get isLoggedIn => _jwtToken != null && _currentUserId != null;
  bool get isAdmin => _currentRole == UserRole.admin;
  bool get isEventStaff => _currentRole == UserRole.eventStaff;
  bool get isRegularUser => _currentRole == UserRole.user;
}

class _StagingIdentity {
  const _StagingIdentity({
    required this.userId,
    required this.apiRole,
    required this.appRole,
  });

  final String userId;
  final String apiRole;
  final UserRole appRole;
}
