import 'package:flutter/foundation.dart';

import '../models/system_theme.dart';
import 'native_bridge.dart';

/// Tracks the OS accent color and keeps it in sync live: reads it once at
/// startup, then listens for the native side pushing an update when the
/// user changes it in System Settings while the app is running.
class SystemThemeService extends ChangeNotifier {
  SystemThemeService(this._native);

  final NativeBridge _native;
  SystemAccent _accent = SystemAccent.fallback;

  SystemAccent get accent => _accent;

  Future<void> init() async {
    _native.onSystemAccentChanged = (accent) {
      if (accent == _accent) return;
      _accent = accent;
      notifyListeners();
    };
    try {
      final accent = await _native.getSystemAccent();
      if (accent != null && accent != _accent) {
        _accent = accent;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('getSystemAccent failed, keeping fallback: $error');
    }
  }

  @override
  void dispose() {
    _native.onSystemAccentChanged = null;
    super.dispose();
  }
}
