import 'package:shared_preferences/shared_preferences.dart';

class SetupService {
  static const String _prefix = 'user_setup_complete_v1';

  Future<bool> isComplete(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  Future<void> markComplete(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }

  Future<void> reset(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }

  String _key(String userId) => '$_prefix:$userId';
}
