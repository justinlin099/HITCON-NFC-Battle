import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalCollectionStore {
  static const String _prefix = 'local_collection_cache_v1';

  Future<Map<String, dynamic>> load(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) {
      return _emptyCache(userId);
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _normalizeCache(userId, decoded);
      }
    } catch (_) {
      // Fall through to a clean cache if a previous local payload is malformed.
    }
    return _emptyCache(userId);
  }

  Future<void> saveCollectionIndex({
    required String userId,
    required Map<String, dynamic> collection,
  }) async {
    final Map<String, dynamic> cache = await load(userId);
    cache['collection_index'] = _jsonMap(collection);
    cache['owner_display_name'] = collection['owner_display_name'];
    cache['total_collected'] = collection['total_collected'];
    cache['updated_at'] = DateTime.now().toIso8601String();

    final List<dynamic> rawCards =
        collection['collection'] as List<dynamic>? ?? <dynamic>[];
    for (final Map<String, dynamic> card
        in rawCards.whereType<Map<String, dynamic>>()) {
      final String uid = (card['physical_uid'] as String? ?? '').trim();
      if (uid.isEmpty) {
        continue;
      }
      _upsertCard(cache, uid, <String, dynamic>{
        ...card,
        'source': 'collection_index',
      });
    }

    await _save(userId, cache);
  }

  Future<void> saveScanResult({
    required String userId,
    required String scannedUid,
    required Map<String, dynamic> scanResult,
  }) async {
    final Map<String, dynamic> cache = await load(userId);
    final String uid = scannedUid.trim();
    if (uid.isEmpty) {
      return;
    }

    final String scannedAt = DateTime.now().toIso8601String();
    final Map<String, dynamic> record = <String, dynamic>{
      'physical_uid': uid,
      'scanned_at': scannedAt,
      'source': 'scan_result',
      'scan_type': scanResult['type'],
      'scan_result': _jsonMap(scanResult),
    };

    final dynamic data = scanResult['data'];
    if (data is Map<String, dynamic>) {
      final dynamic targetInfo = data['target_info'];
      if (targetInfo is Map<String, dynamic>) {
        record.addAll(targetInfo);
      }
      for (final String key in <String>[
        'pixel_avatar_base64',
        'ciphertext',
        'sponsor_stand_id',
        'sponsor_stand_name',
        'sponsor_stand_message',
        'community_stand_id',
        'community_stand_name',
        'community_stand_message',
        'current_stamps',
        'required_for_prize',
      ]) {
        if (data.containsKey(key)) {
          record[key] = data[key];
        }
      }
    }

    _upsertCard(cache, uid, record);
    cache['updated_at'] = scannedAt;
    await _save(userId, cache);
  }

  Future<List<Map<String, dynamic>>> loadCards(String userId) async {
    final Map<String, dynamic> cache = await load(userId);
    final Map<String, dynamic> cards = _cardsMap(cache);
    final List<Map<String, dynamic>> result = cards.values
        .whereType<Map<String, dynamic>>()
        .map(_jsonMap)
        .toList();
    result.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final String left =
          a['collected_at'] as String? ?? a['scanned_at'] as String? ?? '';
      final String right =
          b['collected_at'] as String? ?? b['scanned_at'] as String? ?? '';
      return right.compareTo(left);
    });
    return result;
  }

  Future<String> exportJson(String userId) async {
    final Map<String, dynamic> cache = await load(userId);
    return const JsonEncoder.withIndent('  ').convert(cache);
  }

  Future<void> importJson(String userId, String rawJson) async {
    final dynamic decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Backup must be a JSON object.');
    }

    final Map<String, dynamic> cache = _normalizeCache(
      userId,
      _jsonMap(decoded),
    );
    cache['user_id'] = userId;
    cache['imported_at'] = DateTime.now().toIso8601String();
    cache['updated_at'] = DateTime.now().toIso8601String();
    await _save(userId, cache);
  }

  Future<void> copyExportToClipboard(String userId) async {
    await Clipboard.setData(ClipboardData(text: await exportJson(userId)));
  }

  Future<void> clear(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }

  Map<String, dynamic> _emptyCache(String userId) {
    return <String, dynamic>{
      'schema': 1,
      'user_id': userId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'cards_by_uid': <String, dynamic>{},
    };
  }

  Map<String, dynamic> _normalizeCache(
    String userId,
    Map<String, dynamic> cache,
  ) {
    cache['schema'] ??= 1;
    cache['user_id'] ??= userId;
    cache['cards_by_uid'] = _cardsMap(cache);
    cache['updated_at'] ??= DateTime.now().toIso8601String();
    return cache;
  }

  void _upsertCard(
    Map<String, dynamic> cache,
    String uid,
    Map<String, dynamic> next,
  ) {
    final Map<String, dynamic> cards = _cardsMap(cache);
    final Map<String, dynamic> previous = _jsonMap(cards[uid]);
    cards[uid] = <String, dynamic>{...previous, ..._jsonMap(next)};
    cache['cards_by_uid'] = cards;
  }

  Map<String, dynamic> _cardsMap(Map<String, dynamic> cache) {
    final dynamic raw = cache['cards_by_uid'];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
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

  Future<void> _save(String userId, Map<String, dynamic> cache) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(cache));
  }

  String _key(String userId) => '$_prefix:$userId';
}
