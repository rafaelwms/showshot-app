import 'dart:ui' as ui;

import 'capture_mode.dart';
import 'display_info.dart';
import 'window_info.dart';

/// A frozen screenshot of one display plus the metadata needed to pick a
/// region or window from it.
class CaptureSession {
  CaptureSession({
    required this.mode,
    required this.display,
    required this.image,
    required this.windows,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now();

  final CaptureMode mode;
  final DisplayInfo display;

  /// Full display capture in device pixels.
  final ui.Image image;

  /// Visible windows in display-local logical coordinates, front-most first.
  final List<WindowInfo> windows;

  final DateTime capturedAt;

  /// Ratio between image pixels and display-local logical pixels.
  double get pixelRatio => image.width / display.logicalSize.width;

  ui.Rect get logicalRect => ui.Offset.zero & display.logicalSize;

  /// Crops the frozen image to [logicalRect] (display-local logical
  /// coordinates) and returns a new image in device pixels.
  Future<ui.Image> crop(ui.Rect logicalRect) async {
    final ratio = pixelRatio;
    final full = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    var src = ui.Rect.fromLTWH(
      (logicalRect.left * ratio).roundToDouble(),
      (logicalRect.top * ratio).roundToDouble(),
      (logicalRect.width * ratio).roundToDouble(),
      (logicalRect.height * ratio).roundToDouble(),
    ).intersect(full);
    if (src.width < 1 || src.height < 1) src = full;
    if (src == full) return image.clone();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dst = ui.Rect.fromLTWH(0, 0, src.width, src.height);
    canvas.drawImageRect(
      image,
      src,
      dst,
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(src.width.toInt(), src.height.toInt());
    picture.dispose();
    return result;
  }

  /// The front-most window under [localPoint], if any.
  WindowInfo? windowAt(ui.Offset localPoint) {
    for (final window in windows) {
      if (window.bounds.contains(localPoint)) return window;
    }
    return null;
  }

  void dispose() => image.dispose();
}
