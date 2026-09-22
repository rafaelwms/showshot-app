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

/// Static facts about the native layer for the current platform.
class NativePlatformInfo {
  const NativePlatformInfo({
    required this.globalIsPhysical,
    required this.supportsWindowList,
    required this.supportsNativeCapture,
    required this.needsScreenPermission,
    required this.isWayland,
  });

  final bool globalIsPhysical;
  final bool supportsWindowList;
  final bool supportsNativeCapture;
  final bool needsScreenPermission;
  final bool isWayland;

  static const fallback = NativePlatformInfo(
    globalIsPhysical: false,
    supportsWindowList: false,
    supportsNativeCapture: false,
    needsScreenPermission: false,
    isWayland: false,
  );
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

  Future<void> _handleIncoming(MethodCall call) async {
    if (call.method == 'systemAccentChanged') {
      final argb = (call.arguments as num?)?.toInt();
      if (argb != null) {
        onSystemAccentChanged?.call(SystemAccent(ui.Color(argb)));
      }
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
  Future<Uint8List> captureScreenshotPortal() async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'captureScreenshotPortal',
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

  Future<bool> requestScreenAccess() async =>
      await _channel.invokeMethod<bool>('requestScreenAccess') ?? true;

  Future<void> openScreenAccessSettings() =>
      _channel.invokeMethod('openScreenAccessSettings');

  Future<void> setDockIconVisible(bool visible) =>
      _channel.invokeMethod('setDockIconVisible', {'visible': visible});

  Future<void> revealFile(String path) =>
      _channel.invokeMethod('revealFile', {'path': path});

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
