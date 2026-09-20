import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../models/capture_mode.dart';
import 'settings_service.dart';

/// Registers the global capture shortcuts and keeps them in sync with settings.
class HotkeyService extends ChangeNotifier {
  HotkeyService({required this.settings, required this.onTrigger});

  final SettingsService settings;
  final void Function(CaptureMode mode) onTrigger;

  /// Modes whose shortcut could not be registered (probably taken by another app).
  final Set<CaptureMode> failed = {};

  bool _syncing = false;
  bool _dirty = false;

  Future<void> init() async {
    settings.addListener(_onSettingsChanged);
    await sync();
  }

  void _onSettingsChanged() => sync();

  Future<void> sync() async {
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
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
      notifyListeners();
    } finally {
      _syncing = false;
      if (_dirty) {
        _dirty = false;
        await sync();
      }
    }
  }

  /// Temporarily suspends shortcuts (e.g. while recording a new one).
  Future<void> suspend() => hotKeyManager.unregisterAll();

  Future<void> resume() => sync();

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
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
