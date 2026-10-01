import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/strings.dart';
import '../models/capture_mode.dart';
import 'native_bridge.dart';
import 'settings_service.dart';

/// Registers the global capture shortcuts and keeps them in sync with settings.
///
/// Two backends: `hotkey_manager` grabs keys itself (macOS, Windows, Linux
/// X11); on Linux/Wayland no app can do that, so the shortcuts are handed to
/// the desktop through the GlobalShortcuts portal instead — the desktop then
/// decides (asking the user) which keys actually trigger them, see [labelFor].
class HotkeyService extends ChangeNotifier {
  HotkeyService({
    required this.settings,
    required this.native,
    required this.onTrigger,
  });

  final SettingsService settings;
  final NativeBridge native;
  final void Function(CaptureMode mode) onTrigger;

  /// Modes whose shortcut could not be registered (probably taken by another app).
  final Set<CaptureMode> failed = {};

  /// Wayland: shortcuts live in the desktop, not in our settings.
  bool get usesPortal => _portal;
  bool _portal = false;

  /// Wayland: the keys the desktop actually bound, by mode (human-readable).
  final Map<CaptureMode, String> _bound = {};

  /// Wayland: what was last sent to the portal, so unrelated settings
  /// changes don't re-bind (each bind may pop up a desktop dialog).
  String? _portalSignature;

  bool _syncing = false;
  bool _dirty = false;

  Future<void> init() async {
    _portal = (await native.platformInfo()).globalShortcutsPortal;
    if (_portal) {
      native.onGlobalShortcutActivated = (id) {
        final mode = CaptureMode.values.where((m) => m.name == id).firstOrNull;
        if (mode != null) onTrigger(mode);
      };
      native.onGlobalShortcutsChanged = (shortcuts) {
        _applyBound(shortcuts);
        notifyListeners();
      };
    }
    settings.addListener(_onSettingsChanged);
    await sync();
  }

  void _onSettingsChanged() => sync();

  /// The shortcut to show for [mode] (Home, tray menu, Settings).
  String labelFor(CaptureMode mode) {
    if (!_portal) return hotKeyLabel(settings.settings.hotKeys[mode]);
    final trigger = _bound[mode];
    return trigger == null || trigger.isEmpty ? '—' : trigger;
  }

  Future<void> sync() async {
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
      if (_portal) {
        await _syncPortal();
      } else {
        await _syncHotkeyManager();
      }
      notifyListeners();
    } finally {
      _syncing = false;
      if (_dirty) {
        _dirty = false;
        await sync();
      }
    }
  }

  Future<void> _syncHotkeyManager() async {
    await hotKeyManager.unregisterAll();
    failed.clear();
    for (final entry in settings.settings.hotKeys.entries) {
      final hotKey = entry.value;
      if (hotKey == null) continue;
      try {
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) => onTrigger(entry.key),
        );
      } catch (error) {
        debugPrint('Failed to register ${entry.key}: $error');
        failed.add(entry.key);
      }
    }
  }

  Future<void> _syncPortal() async {
    final strings = Strings.forLanguage(settings.settings.language);
    final shortcuts = [
      for (final mode in CaptureMode.values)
        if (settings.settings.hotKeys[mode] case final hotKey?)
          (
            id: mode.name,
            description: '${strings.appName}: ${strings.modeName(mode)}',
            trigger: xdgTrigger(hotKey),
          ),
    ];
    final signature = shortcuts.map((s) => '${s.id}=${s.trigger}').join(';');
    if (signature == _portalSignature) return;
    _portalSignature = signature;
    try {
      _applyBound(await native.bindGlobalShortcuts(shortcuts));
    } on PlatformException catch (error) {
      debugPrint('Global shortcuts portal: ${error.code} ${error.message}');
      _bound.clear();
      failed
        ..clear()
        ..addAll(shortcuts.map((s) => CaptureMode.values.byName(s.id)));
    }
  }

  void _applyBound(List<BoundShortcut> shortcuts) {
    _bound.clear();
    for (final shortcut in shortcuts) {
      final mode = CaptureMode.values
          .where((m) => m.name == shortcut.id)
          .firstOrNull;
      if (mode != null) _bound[mode] = prettyPortalTrigger(shortcut.trigger);
    }
    failed
      ..clear()
      ..addAll(
        CaptureMode.values.where(
          (m) =>
              settings.settings.hotKeys[m] != null &&
              (_bound[m]?.isEmpty ?? true),
        ),
      );
  }

  /// Debug automation: forget what was sent to the portal and bind again.
  Future<void> debugRebind() {
    _portalSignature = null;
    return sync();
  }

  /// Wayland: opens the desktop's own UI for changing the shortcuts — the
  /// portal's ConfigureShortcuts where implemented (portal v2), otherwise the
  /// system settings page that lists them. False if nothing could be opened.
  Future<bool> configureInSystem() async {
    if (await native.configureGlobalShortcuts()) return true;
    final desktop = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
        .toUpperCase();
    final command = desktop.contains('KDE')
        ? ['systemsettings', 'kcm_keys']
        // GNOME lists an app's global shortcuts on its page in Settings >
        // Apps (the portal's own dialog points there too).
        : ['gnome-control-center', 'applications', 'com.rafaelwms.showshot'];
    try {
      await Process.start(
        command.first,
        command.skip(1).toList(),
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }

  /// Temporarily suspends shortcuts (e.g. while recording a new one).
  Future<void> suspend() async {
    // Portal shortcuts belong to the desktop; nothing to release here.
    if (!_portal) await hotKeyManager.unregisterAll();
  }

  Future<void> resume() async {
    if (!_portal) await sync();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}

/// GNOME describes bound triggers as a localized sentence around a GTK
/// accelerator (`Pressione <Shift><Control>1`); show them the way the rest of
/// the app does ("Ctrl+Shift+1"). Anything unrecognized is shown as is.
String prettyPortalTrigger(String description) {
  final match = RegExp(r'((?:<[A-Za-z0-9_]+>)+)(\S+)\s*$')
      .firstMatch(description);
  if (match == null) return description;
  final modifiers = RegExp(r'<([A-Za-z0-9_]+)>')
      .allMatches(match.group(1)!)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet();
  const order = [
    ({'control', 'primary', 'ctrl'}, 'Ctrl'),
    ({'alt', 'mod1'}, 'Alt'),
    ({'shift'}, 'Shift'),
    ({'super', 'meta', 'logo', 'mod4'}, 'Super'),
  ];
  final key = match.group(2)!;
  const keyNames = {
    'Print': 'PrtSc',
    'space': 'Space',
    'Return': 'Enter',
    'Escape': 'Esc',
    'Page_Up': 'PgUp',
    'Page_Down': 'PgDn',
  };
  return [
    for (final (names, label) in order)
      if (modifiers.any(names.contains)) label,
    keyNames[key] ?? (key.length == 1 ? key.toUpperCase() : key),
  ].join('+');
}

/// [hotKey] in the XDG shortcuts format the GlobalShortcuts portal takes as
/// a *preferred* trigger: `CTRL+SHIFT+1`, modifiers + an xkb keysym name.
String xdgTrigger(HotKey hotKey) {
  final parts = <String>[
    for (final modifier in hotKey.modifiers ?? const <HotKeyModifier>[])
      ?switch (modifier) {
        HotKeyModifier.control => 'CTRL',
        HotKeyModifier.shift => 'SHIFT',
        HotKeyModifier.alt => 'ALT',
        HotKeyModifier.meta => 'LOGO',
        HotKeyModifier.capsLock || HotKeyModifier.fn => null,
      },
  ];
  final key = hotKey.logicalKey;
  final named = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.printScreen: 'Print',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.enter: 'Return',
    LogicalKeyboardKey.space: 'space',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.backspace: 'BackSpace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.arrowUp: 'Up',
    LogicalKeyboardKey.arrowDown: 'Down',
    LogicalKeyboardKey.arrowLeft: 'Left',
    LogicalKeyboardKey.arrowRight: 'Right',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'Page_Up',
    LogicalKeyboardKey.pageDown: 'Page_Down',
    LogicalKeyboardKey.insert: 'Insert',
  };
  final label = key.keyLabel;
  final name =
      named[key] ??
      (RegExp(r'^F([1-9]|1[0-9]|2[0-4])$').hasMatch(label)
          ? label
          : label.length == 1
          ? label.toLowerCase()
          : label);
  return [...parts, name].join('+');
}

/// Human readable label for a [HotKey], using platform glyphs on macOS.
String hotKeyLabel(HotKey? hotKey) {
  if (hotKey == null) return '—';
  final mac = Platform.isMacOS;
  final parts = <String>[];
  for (final modifier in hotKey.modifiers ?? const <HotKeyModifier>[]) {
    parts.add(switch (modifier) {
      HotKeyModifier.control => mac ? '⌃' : 'Ctrl',
      HotKeyModifier.shift => mac ? '⇧' : 'Shift',
      HotKeyModifier.alt => mac ? '⌥' : 'Alt',
      HotKeyModifier.meta => mac ? '⌘' : 'Win',
      HotKeyModifier.capsLock => 'Caps',
      HotKeyModifier.fn => 'Fn',
    });
  }
  parts.add(keyLabel(hotKey.logicalKey));
  return parts.join(mac ? '' : '+');
}

String keyLabel(LogicalKeyboardKey key) {
  final label = key.keyLabel;
  if (label.isNotEmpty && label.trim().isNotEmpty) {
    if (label == ' ') return 'Space';
    return label.length == 1 ? label.toUpperCase() : label;
  }
  final names = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.printScreen: 'PrtSc',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PgUp',
    LogicalKeyboardKey.pageDown: 'PgDn',
    LogicalKeyboardKey.insert: 'Ins',
  };
  if (names.containsKey(key)) return names[key]!;
  final debug = key.debugName ?? 'Key';
  return debug.replaceAll('Key ', '');
}
