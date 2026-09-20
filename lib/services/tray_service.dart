import 'dart:io';
import 'dart:ui' show Brightness, PlatformDispatcher, Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

import '../core/strings.dart';
import '../models/capture_mode.dart';
import 'hotkey_service.dart';
import 'settings_service.dart';

/// Menu bar (macOS/Linux) and tray (Windows) icon with the capture menu.
class TrayService {
  TrayService({
    required this.settings,
    required this.onCapture,
    required this.onOpen,
    required this.onSettings,
    required this.onQuit,
  });

  final SettingsService settings;
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
      // macOS: left click opens the menu. Windows: left click opens the app,
      // right click opens the menu. Linux panels handle clicks themselves.
      icon.setContextMenuTrigger(
        Platform.isWindows
            ? tray.ContextMenuTrigger.rightClicked
            : tray.ContextMenuTrigger.clicked,
      );
      icon.addListener((event) {
        if (event is tray.TrayIconClickedEvent && Platform.isWindows) onOpen();
        if (event is tray.TrayIconDoubleClickedEvent) onOpen();
      });
      rebuildMenu();
      icon.setVisible(true);
      settings.addListener(rebuildMenu);
    } catch (error, stack) {
      debugPrint('Tray init failed: $error\n$stack');
    }
  }

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
        if (event is tray.MenuItemClickedEvent) onClick();
      });
      return menuItem;
    }

    String withHotKey(String label, CaptureMode mode) {
      final hotKey = hotKeys[mode];
      return hotKey == null ? label : '$label   ${hotKeyLabel(hotKey)}';
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
    if (!Platform.isMacOS) {
      PlatformDispatcher.instance.onPlatformBrightnessChanged = null;
    }
    _icon?.setVisible(false);
  }
}
