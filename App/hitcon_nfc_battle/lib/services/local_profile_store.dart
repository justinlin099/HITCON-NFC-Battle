import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalProfileStore {
  static const String _prefix = 'local_profile_v1';

  Future<Map<String, dynamic>> load(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }

  Future<void> save(String userId, Map<String, dynamic> profile) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> current = await load(userId);
    current.addAll(_jsonMap(profile));
    current['updated_at'] = DateTime.now().toIso8601String();
    await prefs.setString(_key(userId), jsonEncode(current));
  }

  String _key(String userId) => '$_prefix:$userId';

  Map<String, dynamic> _jsonMap(Map<String, dynamic> source) {
    final Map<String, dynamic> result = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in source.entries) {
      final dynamic value = entry.value;
      if (value == null ||
          value is String ||
          value is num ||
          value is bool ||
          value is List ||
          value is Map) {
        result[entry.key] = value;
      }
    }
    return result;
  }
}
