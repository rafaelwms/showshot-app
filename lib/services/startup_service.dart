import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'native_bridge.dart';
import 'settings_service.dart';

/// Why the OS refused to turn "launch at startup" on (packaged Windows only).
enum StartupBlock {
  /// The user turned the app off in Task Manager / Settings > Apps > Startup;
  /// Windows won't let the app re-enable it programmatically.
  disabledByUser,

  /// Group policy / MDM forbids it.
  disabledByPolicy,
}

/// "Launch at login" integration (SMAppService / registry Run key / XDG
/// autostart; on a packaged (Microsoft Store / MSIX) Windows install the
/// MSIX StartupTask through the native channel instead).
///
/// A packaged Windows app can't use the Run key: its HKCU writes are
/// virtualized into the package's private hive, so Windows never sees them.
class StartupService extends ChangeNotifier {
  StartupService(this.settings, {NativeBridge? native})
    : _native = native ?? NativeBridge.instance;

  static const launchArg = '--autostart';

  final SettingsService settings;
  final NativeBridge _native;
  bool _available = false;

  // Packaged Windows (StartupTask) state. Last state we know the OS to be in (true = task enabled).
  bool _osEnabled = false;
  bool _busy = false;
  StartupBlock? _block;

  /// Set when the last attempt to enable failed for a reason the user must
  /// fix in Windows Settings; the Settings screen shows a hint for it.
  StartupBlock? get block => _block;

  Future<void> init() async {
    if (Platform.isWindows && await _native.isPackaged()) {
      await _initPackaged();
      return;
    }
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

  static bool _isOn(String state) =>
      state == 'enabled' || state == 'enabledByPolicy';

  Future<void> _initPackaged() async {
    final state = await _native.startupTaskState();
    if (state == 'unavailable') {
      // Packaged but the task isn't declared (old manifest) or WinRT is
      // missing. Don't fall back to the Run key: it would be virtualized.
      debugPrint('MSIX startup task unavailable');
      return;
    }
    _available = true;
    _osEnabled = _isOn(state);
    // The user may have toggled it in Task Manager / Windows Settings:
    // mirror the real state into the setting. _osEnabled already matches, so
    // the listener below sees nothing to do and no write loop starts.
    if (settings.settings.launchAtStartup != _osEnabled) {
      await settings.update((s) => s.copyWith(launchAtStartup: _osEnabled));
    }
    settings.addListener(_applyPackaged);
  }

  Future<void> _applyPackaged() async {
    // The listener fires for every settings change; calls are serialized and
    // only act when the wanted value differs from the known OS state.
    if (!_available || _busy) return;
    _busy = true;
    try {
      while (settings.settings.launchAtStartup != _osEnabled) {
        final wanted = settings.settings.launchAtStartup;
        final state = await _native.setStartupTask(wanted);
        if (state == 'unavailable') {
          // Native call failed: keep what we knew and undo the switch.
          _setBlock(null);
          await _revert(_osEnabled);
          break;
        }
        _osEnabled = _isOn(state);
        _setBlock(
          wanted && !_osEnabled
              ? switch (state) {
                  'disabledByUser' => StartupBlock.disabledByUser,
                  'disabledByPolicy' => StartupBlock.disabledByPolicy,
                  _ => null,
                }
              : null,
        );
        // Windows refused (or policy forced the opposite): show the real
        // state in the switch. _osEnabled is already updated, so the
        // listener this triggers is a no-op.
        if (settings.settings.launchAtStartup != _osEnabled) {
          await _revert(_osEnabled);
        }
      }
    } catch (error) {
      debugPrint('MSIX startup task apply failed: $error');
    } finally {
      _busy = false;
    }
  }

  Future<void> _revert(bool value) =>
      settings.update((s) => s.copyWith(launchAtStartup: value));

  void _setBlock(StartupBlock? value) {
    if (_block == value) return;
    _block = value;
    notifyListeners();
  }

  /// Opens Windows Settings > Apps > Startup (for the "enable it there" hint).
  Future<bool> openSystemStartupSettings() =>
      _native.openSettingsUri('ms-settings:startupapps');

  @override
  void dispose() {
    settings.removeListener(_apply);
    settings.removeListener(_applyPackaged);
    super.dispose();
  }
}
