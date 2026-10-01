import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'settings_service.dart';

/// "Launch at login" integration (SMAppService / registry Run key / XDG autostart).
class StartupService {
  StartupService(this.settings);

  static const launchArg = '--autostart';

  final SettingsService settings;
  bool _available = false;

  Future<void> init() async {
    try {
      launchAtStartup.setup(
        appName: 'Show Shot',
        appPath: Platform.resolvedExecutable,
        packageName: 'com.rafaelwms.showshot',
        args: const [launchArg],
      );
      _available = true;
      settings.addListener(_apply);
      await _apply();
    } catch (error) {
      debugPrint('launch_at_startup unavailable: $error');
    }
  }

  Future<void> _apply() async {
    if (!_available) return;
    try {
      final wanted = settings.settings.launchAtStartup;
      final enabled = await launchAtStartup.isEnabled();
      if (wanted && !enabled) {
        await launchAtStartup.enable();
      } else if (!wanted && enabled) {
        await launchAtStartup.disable();
      }
    } catch (error) {
      debugPrint('launch_at_startup apply failed: $error');
    }
  }

  void dispose() => settings.removeListener(_apply);
}
