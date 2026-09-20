import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/capture_mode.dart';
import '../models/capture_session.dart';
import '../models/display_info.dart';
import '../models/window_info.dart';
import 'native_bridge.dart';

class CaptureException implements Exception {
  CaptureException(this.message);
  final String message;
  @override
  String toString() => 'CaptureException: $message';
}

/// Produces [CaptureSession]s by freezing the display under the cursor.
class CaptureService {
  CaptureService(this._native);

  final NativeBridge _native;

  Future<CaptureSession> captureUnderCursor(CaptureMode mode) async {
    final info = await _native.platformInfo();
    final displays = await _native.getDisplays();
    if (displays.isEmpty) throw CaptureException('No displays found');

    final cursor = await _native.getCursorPosition();
    final display = displays.firstWhere(
      (d) => d.containsGlobal(cursor),
      orElse: () =>
          displays.firstWhere((d) => d.isPrimary, orElse: () => displays.first),
    );

    final imageFuture = info.supportsNativeCapture
        ? _captureNative(display)
        : _captureWithSystemTools(display);
    final windowsFuture =
        info.supportsWindowList && mode != CaptureMode.fullScreen
        ? _native.listWindows()
        : Future.value(const <WindowInfo>[]);

    final image = await imageFuture;
    final windows = _localizeWindows(await windowsFuture, display);

    return CaptureSession(
      mode: mode,
      display: display,
      image: image,
      windows: windows,
    );
  }

  Future<ui.Image> _captureNative(DisplayInfo display) async {
    try {
      final raw = await _native.captureDisplay(display.id);
      return await raw.decode();
    } on PlatformException catch (error) {
      if (error.code == 'unsupported' && Platform.isLinux) {
        return await _captureWithSystemTools(display);
      }
      throw CaptureException(error.message ?? error.code);
    }
  }

  /// Linux/Wayland fallback: ask a desktop screenshot tool to write a PNG and
  /// crop it to the target display.
  Future<ui.Image> _captureWithSystemTools(DisplayInfo display) async {
    final tmp = await getTemporaryDirectory();
    final path =
        '${tmp.path}/shoshot_${DateTime.now().millisecondsSinceEpoch}.png';
    const candidates = <List<String>>[
      ['gnome-screenshot', '-f'],
      ['spectacle', '-b', '-n', '-o'],
      ['grim'],
      ['scrot', '-o'],
      ['import', '-window', 'root'],
    ];
    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate.first, [
          ...candidate.skip(1),
          path,
        ]);
        final file = File(path);
        if (result.exitCode == 0 &&
            await file.exists() &&
            await file.length() > 0) {
          final bytes = await file.readAsBytes();
          await file.delete();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          return await _cropToDisplay(frame.image, display);
        }
      } on ProcessException {
        continue;
      } catch (error) {
        debugPrint('Screenshot tool ${candidate.first} failed: $error');
      }
    }
    throw CaptureException(
      'No screenshot tool available (tried gnome-screenshot, spectacle, grim, scrot, import).',
    );
  }

  /// Full-desktop screenshots may span several displays; keep only [display].
  Future<ui.Image> _cropToDisplay(ui.Image image, DisplayInfo display) async {
    final expected = display.pixelSize;
    if ((image.width - expected.width).abs() < 2 &&
        (image.height - expected.height).abs() < 2) {
      return image;
    }
    final src =
        ui.Rect.fromLTWH(
          display.bounds.left,
          display.bounds.top,
          expected.width,
          expected.height,
        ).intersect(
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
        );
    if (src.isEmpty) return image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      ui.Rect.fromLTWH(0, 0, src.width, src.height),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(
      src.width.toInt(),
      src.height.toInt(),
    );
    picture.dispose();
    image.dispose();
    return cropped;
  }

  List<WindowInfo> _localizeWindows(
    List<WindowInfo> windows,
    DisplayInfo display,
  ) {
    final result = <WindowInfo>[];
    final displayLocal = Offset.zero & display.logicalSize;
    for (final window in windows) {
      if (!window.bounds.overlaps(display.bounds)) continue;
      final local = display
          .globalRectToLocal(window.bounds)
          .intersect(displayLocal);
      if (local.width < 8 || local.height < 8) continue;
      result.add(window.copyWith(bounds: local));
    }
    return result;
  }
}
