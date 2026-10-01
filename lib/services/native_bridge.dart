import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/display_info.dart';
import '../models/system_theme.dart';
import '../models/window_info.dart';

/// Raw pixels of a captured display.
class RawCapture {
  const RawCapture({
    required this.width,
    required this.height,
    required this.scale,
    required this.bytes,
    required this.format,
  });

  final int width;
  final int height;
  final double scale;
  final Uint8List bytes;
  final ui.PixelFormat format;

  Future<ui.Image> decode() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, width, height, format, completer.complete);
    return completer.future;
  }
}

/// A shortcut as the desktop actually bound it (Linux/Wayland portal).
class BoundShortcut {
  const BoundShortcut({required this.id, required this.trigger});

  final String id;

  /// Human-readable, from the desktop (e.g. "Ctrl+Shift+1"); may be empty
  /// when the user left the shortcut unassigned.
  final String trigger;

  static List<BoundShortcut> listFrom(List<Object?> raw) => [
    for (final item in raw.whereType<Map<Object?, Object?>>())
      BoundShortcut(
        id: item['id'] as String? ?? '',
        trigger: item['trigger'] as String? ?? '',
      ),
  ];
}

/// Static facts about the native layer for the current platform.
class NativePlatformInfo {
  const NativePlatformInfo({
    required this.globalIsPhysical,
    required this.supportsWindowList,
    required this.supportsNativeCapture,
    required this.needsScreenPermission,
    required this.isWayland,
    this.globalShortcutsPortal = false,
  });

  final bool globalIsPhysical;
  final bool supportsWindowList;
  final bool supportsNativeCapture;
  final bool needsScreenPermission;
  final bool isWayland;

  /// Linux/Wayland: global shortcuts go through the desktop portal (apps
  /// can't grab keys themselves there).
  final bool globalShortcutsPortal;

  static const fallback = NativePlatformInfo(
    globalIsPhysical: false,
    supportsWindowList: false,
    supportsNativeCapture: false,
    needsScreenPermission: false,
    isWayland: false,
  );
}

/// How the OS started the process, for what the command line can't say:
/// macOS login items carry no arguments.
class NativeLaunchInfo {
  const NativeLaunchInfo({this.atLogin = false});

  /// True when the OS launched the app as a login item.
  final bool atLogin;
}

/// Thin typed wrapper around the `shoshot/native` method channel implemented
/// in each platform runner.
class NativeBridge {
  NativeBridge._() {
    _channel.setMethodCallHandler(_handleIncoming);
  }

  static final NativeBridge instance = NativeBridge._();

  static const _channel = MethodChannel('shoshot/native');

  NativePlatformInfo? _info;

  /// Set by [SystemThemeService]: called whenever the native side pushes an
  /// `systemAccentChanged` notification (the user changed their accent
  /// color in System Settings while the app was running).
  void Function(SystemAccent accent)? onSystemAccentChanged;

  /// Linux/Wayland: a shortcut bound through [bindGlobalShortcuts] fired.
  void Function(String id)? onGlobalShortcutActivated;

  /// Linux/Wayland: the user changed our shortcuts in the desktop's settings.
  void Function(List<BoundShortcut> shortcuts)? onGlobalShortcutsChanged;

  Future<void> _handleIncoming(MethodCall call) async {
    if (call.method == 'systemAccentChanged') {
      final argb = (call.arguments as num?)?.toInt();
      if (argb != null) {
        onSystemAccentChanged?.call(SystemAccent(ui.Color(argb)));
      }
    } else if (call.method == 'globalShortcutActivated') {
      final id = call.arguments as String?;
      if (id != null) onGlobalShortcutActivated?.call(id);
    } else if (call.method == 'globalShortcutsChanged') {
      onGlobalShortcutsChanged?.call(
        BoundShortcut.listFrom(call.arguments as List<Object?>? ?? const []),
      );
    }
  }

  /// Linux/Wayland: asks the desktop (`org.freedesktop.portal.
  /// GlobalShortcuts`) to bind [shortcuts]. GNOME shows its own confirmation
  /// dialog the first time and may assign different keys than the preferred
  /// ones — the result says what's actually bound. Throws [PlatformException]
  /// (`cancelled` when the user declined).
  Future<List<BoundShortcut>> bindGlobalShortcuts(
    List<({String id, String description, String trigger})> shortcuts,
  ) async {
    final list = await _channel.invokeListMethod<Object?>(
      'bindGlobalShortcuts',
      {
        'shortcuts': [
          for (final s in shortcuts)
            {'id': s.id, 'description': s.description, 'trigger': s.trigger},
        ],
      },
    );
    return BoundShortcut.listFrom(list ?? const []);
  }

  /// Opens the desktop's own UI to change the bound shortcuts. False when the
  /// portal can't (older desktops) — fall back to the system settings.
  Future<bool> configureGlobalShortcuts() async {
    try {
      return await _channel.invokeMethod<bool>('configureGlobalShortcuts') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<NativePlatformInfo> platformInfo() async {
    if (_info != null) return _info!;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>(
        'platformInfo',
      );
      _info = NativePlatformInfo(
        globalIsPhysical: map?['globalIsPhysical'] == true,
        supportsWindowList: map?['supportsWindowList'] == true,
        supportsNativeCapture: map?['supportsNativeCapture'] == true,
        needsScreenPermission: map?['needsScreenPermission'] == true,
        isWayland: map?['wayland'] == true,
        globalShortcutsPortal: map?['globalShortcutsPortal'] == true,
      );
    } on MissingPluginException {
      _info = NativePlatformInfo.fallback;
    }
    return _info!;
  }

  Future<List<DisplayInfo>> getDisplays() async {
    final info = await platformInfo();
    final list = await _channel.invokeListMethod<Object?>('getDisplays') ?? [];
    return list
        .map(
          (e) => DisplayInfo.fromMap(
            e as Map<Object?, Object?>,
            (scale) => info.globalIsPhysical ? scale : 1.0,
          ),
        )
        .toList();
  }

  Future<ui.Offset> getCursorPosition() async {
    final map = await _channel.invokeMapMethod<String, Object?>(
      'getCursorPosition',
    );
    return ui.Offset(
      (map?['x'] as num?)?.toDouble() ?? 0,
      (map?['y'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<RawCapture> captureDisplay(int displayId) async {
    final map = await _channel.invokeMapMethod<String, Object?>(
      'captureDisplay',
      {'displayId': displayId},
    );
    if (map == null) {
      throw PlatformException(
        code: 'capture_failed',
        message: 'Empty response',
      );
    }
    final format = map['format'] == 'bgra'
        ? ui.PixelFormat.bgra8888
        : ui.PixelFormat.rgba8888;
    return RawCapture(
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      scale: (map['scale'] as num?)?.toDouble() ?? 1.0,
      bytes: map['bytes'] as Uint8List,
      format: format,
    );
  }

  /// Linux/Wayland only: `org.freedesktop.portal.Screenshot`, returned as
  /// PNG bytes of the whole screen (the portal has no per-monitor concept).
  /// [interactive] lets the desktop show its own screenshot UI first (GNOME:
  /// pick an area, window or screen) and returns what the user took there.
  Future<Uint8List> captureScreenshotPortal({bool interactive = false}) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'captureScreenshotPortal',
      {'interactive': interactive},
    );
    if (bytes == null) {
      throw PlatformException(
        code: 'capture_failed',
        message: 'Empty response',
      );
    }
    return bytes;
  }

  Future<List<WindowInfo>> listWindows() async {
    try {
      final list =
          await _channel.invokeListMethod<Object?>('listWindows') ?? [];
      return list
          .map((e) => WindowInfo.fromMap(e as Map<Object?, Object?>))
          .toList();
    } catch (error) {
      debugPrint('listWindows failed: $error');
      return const [];
    }
  }

  Future<void> enterOverlay(int displayId) =>
      _channel.invokeMethod('enterOverlay', {'displayId': displayId});

  Future<void> exitOverlay({required double width, required double height}) =>
      _channel.invokeMethod('exitOverlay', {'width': width, 'height': height});

  /// Puts an image on the system clipboard. [rgba] must be `width * height * 4`
  /// bytes; [png] is used by platforms that prefer encoded data.
  Future<bool> setClipboardImage({
    required Uint8List png,
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    final ok = await _channel.invokeMethod<bool>('setClipboardImage', {
      'png': png,
      'rgba': rgba,
      'width': width,
      'height': height,
    });
    return ok ?? false;
  }

  Future<bool> hasScreenAccess() async =>
      await _channel.invokeMethod<bool>('hasScreenAccess') ?? true;

  /// Asks for screen capture access. macOS: shows the system prompt (the
  /// grant only applies after a restart). Linux/Wayland: shows GNOME's
  /// one-time screenshot access dialog — only possible while our window is
  /// focused — and resolves once the user answered; [reset] first forgets an
  /// earlier "deny", which the portal would otherwise apply silently forever.
  Future<bool> requestScreenAccess({bool reset = false}) async =>
      await _channel.invokeMethod<bool>('requestScreenAccess', {
        'reset': reset,
      }) ??
      true;

  Future<void> openScreenAccessSettings() =>
      _channel.invokeMethod('openScreenAccessSettings');

  Future<void> setDockIconVisible(bool visible) =>
      _channel.invokeMethod('setDockIconVisible', {'visible': visible});

  Future<void> revealFile(String path) =>
      _channel.invokeMethod('revealFile', {'path': path});

  /// macOS (App Sandbox): a security-scoped bookmark for a folder the user
  /// just picked, so it stays writable across launches. Null elsewhere or on
  /// failure.
  Future<Uint8List?> bookmarkDirectory(String path) async {
    try {
      return await _channel.invokeMethod<Uint8List>('bookmarkDirectory', {
        'path': path,
      });
    } on MissingPluginException {
      return null;
    }
  }

  /// Resolves a bookmark from [bookmarkDirectory] and starts accessing that
  /// folder for the rest of this launch. Returns the folder path plus a
  /// refreshed bookmark when the stored one went stale, or null if the folder
  /// can't be reached anymore.
  Future<({String path, Uint8List? refreshed})?> resolveDirectoryBookmark(
    Uint8List bookmark,
  ) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'resolveDirectoryBookmark',
        {'bookmark': bookmark},
      );
      if (raw == null) return null;
      return (
        path: raw['path'] as String,
        refreshed: raw['bookmark'] as Uint8List?,
      );
    } on MissingPluginException {
      return null;
    }
  }

  /// Posts an OS notification. True only if the system accepted it — false
  /// when notifications aren't allowed/available, or the platform doesn't
  /// implement it. Never waits on a permission prompt for more than a few
  /// seconds, so a flow can't hang on it.
  Future<bool> notify({required String title, required String body}) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('notify', {'title': title, 'body': body})
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('notify failed: ${error.message}');
      return false;
    }
  }

  /// Launch details only the native side can see (see [NativeLaunchInfo]).
  /// Platforms that don't implement it report a plain, non-login launch.
  Future<NativeLaunchInfo> launchInfo() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('launchInfo');
      return NativeLaunchInfo(atLogin: map?['atLogin'] == true);
    } on MissingPluginException {
      return const NativeLaunchInfo();
    }
  }

  /// Reads the OS accent color once. Returns null where unsupported (the
  /// caller should keep [SystemAccent.fallback]).
  Future<SystemAccent?> getSystemAccent() async {
    try {
      final argb = await _channel.invokeMethod<int>('getSystemAccent');
      return argb == null ? null : SystemAccent(ui.Color(argb));
    } on MissingPluginException {
      return null;
    }
  }

  /// Recognizes text in a screenshot (macOS: Vision; Windows: Windows.Media.
  /// Ocr). Returns null when no text was found, or the platform doesn't
  /// implement it — [OcrService] is what callers should actually go through,
  /// since it also covers Linux via `tesseract`.
  Future<String?> recognizeText(Uint8List png) async {
    try {
      final text = await _channel.invokeMethod<String>('recognizeText', {
        'png': png,
      });
      return (text == null || text.isEmpty) ? null : text;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('recognizeText failed: ${error.message}');
      return null;
    }
  }
}
