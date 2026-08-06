import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalScoreboardStore {
  static const String _prefix = 'local_scoreboard_v1';
  static const String _pagePrefix = 'local_scoreboard_page_v1';
  static const String _mePrefix = 'local_scoreboard_me_v1';

  Future<Map<String, dynamic>?> load(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key(userId)));
  }

  Future<Map<String, dynamic>?> loadPage(
    String userId, {
    required int offset,
    required int limit,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic>? page = _decode(
      prefs.getString(_pageKey(userId, offset, limit)),
    );
    if (page != null || offset != 0) {
      return page;
    }
    return _decode(prefs.getString(_key(userId)));
  }

  Future<Map<String, dynamic>?> loadMyRank(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_meKey(userId)));
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore malformed or obsolete cache entries.
    }
    return null;
  }

  Future<void> save(String userId, Map<String, dynamic> scoreboard) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _write(prefs, _key(userId), scoreboard);
  }

  Future<void> savePage(
    String userId,
    Map<String, dynamic> scoreboard, {
    required int offset,
    required int limit,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _write(prefs, _pageKey(userId, offset, limit), scoreboard);
    if (offset == 0) {
      await _write(prefs, _key(userId), scoreboard);
    }
  }

  Future<void> saveMyRank(String userId, Map<String, dynamic> ranking) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _write(prefs, _meKey(userId), ranking);
  }

  Future<void> _write(
    SharedPreferences prefs,
    String key,
    Map<String, dynamic> value,
  ) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      ...value,
      'cached_at': DateTime.now().toIso8601String(),
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  String _key(String userId) => '$_prefix:$userId';

  String _pageKey(String userId, int offset, int limit) =>
      '$_pagePrefix:$userId:$offset:$limit';

  String _meKey(String userId) => '$_mePrefix:$userId';
}
