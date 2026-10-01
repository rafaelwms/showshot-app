import 'dart:async';
import 'dart:io';
import 'dart:ui' show Brightness, PlatformDispatcher, Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

import '../core/strings.dart';
import '../models/app_settings.dart';
import '../models/capture_mode.dart';
import 'hotkey_service.dart';
import 'settings_service.dart';

/// Menu bar (macOS/Linux) and tray (Windows) icon with the capture menu.
class TrayService {
  TrayService({
    required this.settings,
    required this.hotkeys,
    required this.onCapture,
    required this.onOpen,
    required this.onSettings,
    required this.onQuit,
  });

  final SettingsService settings;

  /// Shortcut labels next to the capture items (on Wayland the desktop picks
  /// the keys, so they can change without a settings change).
  final HotkeyService hotkeys;
  final void Function(CaptureMode mode) onCapture;
  final VoidCallback onOpen;
  final VoidCallback onSettings;
  final VoidCallback onQuit;

  tray.TrayIcon? _icon;

  Future<void> init() async {
    try {
      final icon = tray.TrayIcon.create();
      if (icon == null) {
        debugPrint('Tray icon unavailable on this platform');
        return;
      }
      _icon = icon;
      if (Platform.isMacOS) {
        // macOS re-colors a "template" image itself for light/dark menu bars
        // (and selection states) — only the alpha mask matters, so one asset
        // covers every appearance.
        final image = tray.ImageAsset.fromAsset(
          'assets/tray/tray_icon_template.png',
        );
        if (image != null) icon.icon = image;
        icon.isIconTemplate = true;
        icon.iconSize = const Size(18, 18);
      } else {
        // Windows/Linux don't auto-recolor tray icons, and there is no OS
        // API for "what color is the tray background" — the system's
        // light/dark preference (which Flutter's engine already detects) is
        // the best available proxy, kept in sync live.
        _applyTrayIconForBrightness(icon);
        PlatformDispatcher.instance.onPlatformBrightnessChanged = () {
          _applyTrayIconForBrightness(icon);
        };
      }
      icon.setTooltip('Show Shot');
      // Left click runs the action chosen in Settings
      // (`AppSettings.trayLeftClick`, area capture by default); right click
      // opens the menu on macOS and Windows alike. Linux panels handle
      // clicks (and show the menu) themselves: the StatusNotifierItem gets no
      // click events through to us (nativeapi's Activate/ContextMenu are
      // no-ops), and it only publishes the menu with the `clicked` trigger —
      // with `rightClicked` the icon had no menu at all.
      icon.setContextMenuTrigger(
        Platform.isLinux
            ? tray.ContextMenuTrigger.clicked
            : tray.ContextMenuTrigger.rightClicked,
      );
      icon.addListener((event) {
        if (event is tray.TrayIconClickedEvent) {
          _runOutsideCallback(() => _onLeftClick(icon));
        }
      });
      rebuildMenu();
      icon.setVisible(true);
      settings.addListener(rebuildMenu);
      hotkeys.addListener(rebuildMenu);
    } catch (error, stack) {
      debugPrint('Tray init failed: $error\n$stack');
    }
  }

  /// Debug automation: what a left click on the icon would do.
  void debugLeftClick() {
    final icon = _icon;
    if (icon != null) _onLeftClick(icon);
  }

  void _onLeftClick(tray.TrayIcon icon) {
    final action = settings.settings.trayLeftClick;
    switch (action) {
      case TrayAction.openApp:
        onOpen();
      case TrayAction.menu:
        icon.openContextMenu();
      case TrayAction.area:
      case TrayAction.window:
      case TrayAction.fullScreen:
      case TrayAction.text:
        onCapture(action.mode!);
    }
  }

  /// Tray events arrive through a synchronous native (FFI) callback. On
  /// Linux, async work started right inside it stalls at its first `await`:
  /// the continuation sits in the microtask queue until some *other* event
  /// wakes the isolate — a tray "Area" click looked dead until the user
  /// happened to open the window. Running the handler as a regular event
  /// (a zero timer) gets its microtasks drained normally.
  void _runOutsideCallback(VoidCallback action) => Timer.run(action);

  void _applyTrayIconForBrightness(tray.TrayIcon icon) {
    final dark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    final ext = Platform.isWindows ? 'ico' : 'png';
    // A dark tray/taskbar needs the light-glyph asset to stay visible, and
    // vice versa — named here by the glyph's own color, not the background.
    final asset = dark
        ? 'assets/tray/tray_icon_dark_bg.$ext'
        : 'assets/tray/tray_icon_light_bg.$ext';
    final image = tray.ImageAsset.fromAsset(asset);
    if (image != null) icon.icon = image;
  }

  void rebuildMenu() {
    final icon = _icon;
    if (icon == null) return;
    final strings = Strings.forLanguage(settings.settings.language);
    final hotKeys = settings.settings.hotKeys;
    final menu = tray.Menu.create();
    if (menu == null) return;

    tray.MenuItem? item(String label, VoidCallback onClick) {
      final menuItem = tray.MenuItem.createWithLabelAndType(
        label,
        tray.MenuItemType.normal,
      );
      menuItem?.addListener((event) {
        if (event is tray.MenuItemClickedEvent) _runOutsideCallback(onClick);
      });
      return menuItem;
    }

    String withHotKey(String label, CaptureMode mode) {
      if (hotKeys[mode] == null) return label;
      final shortcut = hotkeys.labelFor(mode);
      return shortcut == '—' ? label : '$label   $shortcut';
    }

    for (final mode in CaptureMode.values) {
      menu.addItem(
        item(withHotKey(strings.modeName(mode), mode), () => onCapture(mode)),
      );
    }
    menu.addSeparator();
    menu.addItem(item(strings.openApp, onOpen));
    menu.addItem(item('${strings.settings}…', onSettings));
    menu.addSeparator();
    menu.addItem(item(strings.quit, onQuit));

    icon.setContextMenu(menu);
  }

  void dispose() {
    settings.removeListener(rebuildMenu);
    hotkeys.removeListener(rebuildMenu);
    if (!Platform.isMacOS) {
      PlatformDispatcher.instance.onPlatformBrightnessChanged = null;
    }
    _icon?.setVisible(false);
  }
}
