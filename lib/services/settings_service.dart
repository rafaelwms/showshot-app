import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Loads and persists [AppSettings]. Notifies listeners on every change.
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs, this._settings);

  static const _key = 'shoshot.settings';
  static const maxRecentFiles = 12;

  final SharedPreferences _prefs;
  AppSettings _settings;

  AppSettings get settings => _settings;

  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    AppSettings settings;
    try {
      final raw = prefs.getString(_key);
      settings = raw == null
          ? AppSettings.defaults()
          : AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('Settings corrupted, using defaults: $error');
      settings = AppSettings.defaults();
    }
    return SettingsService._(prefs, settings);
  }

  Future<void> update(AppSettings Function(AppSettings current) mutate) async {
    _settings = mutate(_settings);
    notifyListeners();
    await _prefs.setString(_key, jsonEncode(_settings.toJson()));
  }

  Future<void> addRecentFile(String path) => update((s) {
    final files = [path, ...s.recentFiles.where((p) => p != path)];
    return s.copyWith(recentFiles: files.take(maxRecentFiles).toList());
  });

  Future<void> removeRecentFile(String path) => update(
    (s) =>
        s.copyWith(recentFiles: s.recentFiles.where((p) => p != path).toList()),
  );
}
