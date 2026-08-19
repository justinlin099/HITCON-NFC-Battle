import 'package:shared_preferences/shared_preferences.dart';

class SetupService {
  static const String _prefix = 'user_setup_complete_v1';
  static const String _manualPromptPrefix =
      'user_setup_manual_prompt_pending_v1';

  Future<bool> isComplete(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  Future<void> markComplete(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
    await prefs.setBool(_manualPromptKey(userId), true);
  }

  Future<bool> shouldPromptManual(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_manualPromptKey(userId)) ?? false;
  }

  Future<void> markManualPromptHandled(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_manualPromptKey(userId));
  }

  Future<void> reset(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
    await prefs.remove(_manualPromptKey(userId));
  }

  String _key(String userId) => '$_prefix:$userId';

  String _manualPromptKey(String userId) => '$_manualPromptPrefix:$userId';
}
