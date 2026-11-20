import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/capture_mode.dart';
import '../models/capture_session.dart';
import '../models/display_info.dart';
import '../models/window_info.dart';
import 'export_service.dart';
import 'native_bridge.dart';
import 'screen_layout.dart';

class CaptureException implements Exception {
  CaptureException(this.message);
  final String message;
  @override
  String toString() => 'CaptureException: $message';
}

/// One display's screenshot, in device pixels.
class DisplayShot {
  const DisplayShot(this.display, this.image);
  final DisplayInfo display;
  final ui.Image image;
}

/// Result of capturing every display.
///
/// Either [shots] (one image per display, in left-to-right order), or
/// [wholeDesktop] when the platform could only deliver one image of the whole
/// desktop (Linux/Wayland combined mode, a single display, or a layout the
/// image can't be cropped by).
class AllScreensCapture {
  const AllScreensCapture({this.shots = const [], this.wholeDesktop});
  final List<DisplayShot> shots;
  final ui.Image? wholeDesktop;

  void dispose() {
    for (final shot in shots) {
      shot.image.dispose();
    }
    wholeDesktop?.dispose();
  }
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

    // Wayland has no window list to pick from in our overlay: let the
    // desktop's own screenshot UI do the picking (GNOME: click a window).
    if (info.isWayland && mode == CaptureMode.window) {
      final png = await _native.captureScreenshotPortal(interactive: true);
      return CaptureSession(
        mode: mode,
        display: display,
        image: await _decode(png),
        windows: const [],
        pickedByDesktop: true,
        pixelRatio: display.scale,
      );
    }

    final imageFuture = info.supportsNativeCapture
        ? _captureNative(display)
        : (info.isWayland
              ? _captureWayland(display)
              : _captureWithSystemTools(display));
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

  /// Captures every connected display (see [AllScreensCapture]). Windows and
  /// macOS/X11 capture each display natively; on Wayland (and tool-based
  /// fallbacks) the desktop comes as one image, which is returned as-is when
  /// [combined] is true and cropped per display otherwise.
  Future<AllScreensCapture> captureAllDisplays({required bool combined}) async {
    final info = await _native.platformInfo();
    final all = await _native.getDisplays();
    if (all.isEmpty) throw CaptureException('No displays found');
    // Left-to-right order, independent of how the OS enumerates monitors.
    final order = ScreenLayout.spatialOrder([for (final d in all) d.bounds]);
    final displays = [for (final i in order) all[i]];

    if (info.supportsNativeCapture) {
      final shots = <DisplayShot>[];
      try {
        for (final display in displays) {
          shots.add(DisplayShot(display, await _captureNative(display)));
        }
      } catch (_) {
        for (final shot in shots) {
          shot.image.dispose();
        }
        rethrow;
      }
      return AllScreensCapture(shots: shots);
    }

    // One image for the whole desktop (the portal has no per-monitor shot).
    final ui.Image desktop;
    if (info.isWayland) {
      desktop = await _portalDesktopImage();
    } else {
      desktop = await _systemToolImage();
    }
    if (combined || displays.length == 1) {
      return AllScreensCapture(wholeDesktop: desktop);
    }

    // Per-screen: crop each display out of the desktop image, offsets relative
    // to the top-left corner of the whole layout. When the image doesn't match
    // that layout (fractional scaling quirks...), cropping would guess wrong:
    // keep the single image instead.
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final d in displays) {
      minX = math.min(minX, d.bounds.left);
      minY = math.min(minY, d.bounds.top);
      maxX = math.max(maxX, d.bounds.left + d.pixelSize.width);
      maxY = math.max(maxY, d.bounds.top + d.pixelSize.height);
    }
    final fits =
        (desktop.width - (maxX - minX)).abs() <= 4 &&
        (desktop.height - (maxY - minY)).abs() <= 4;
    if (!fits) {
      debugPrint(
        'Desktop image ${desktop.width}x${desktop.height} does not match the '
        'display layout; saving it as a single image',
      );
      return AllScreensCapture(wholeDesktop: desktop);
    }
    final shots = <DisplayShot>[];
    for (final display in displays) {
      final size = display.pixelSize;
      final rect = ui.Rect.fromLTWH(
        display.bounds.left - minX,
        display.bounds.top - minY,
        size.width,
        size.height,
      );
      try {
        shots.add(
          DisplayShot(display, await ExportService.crop(desktop, rect)),
        );
      } catch (_) {
        for (final shot in shots) {
          shot.image.dispose();
        }
        desktop.dispose();
        rethrow;
      }
    }
    desktop.dispose();
    return AllScreensCapture(shots: shots);
  }

  /// Linux/Wayland: the portal's whole-desktop screenshot, falling back to a
  /// CLI tool when the portal call fails.
  Future<ui.Image> _portalDesktopImage() async {
    try {
      return await _decode(await _native.captureScreenshotPortal());
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') rethrow;
      debugPrint(
        'Portal screenshot failed (${error.code}: ${error.message}); '
        'falling back to CLI tools',
      );
      return await _systemToolImage();
    }
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

  /// Linux/Wayland: `org.freedesktop.portal.Screenshot`, falling back to a
  /// CLI screenshot tool if the portal call fails (missing/older portal).
  Future<ui.Image> _captureWayland(DisplayInfo display) async {
    try {
      final png = await _native.captureScreenshotPortal();
      return await _cropToDisplay(await _decode(png), display);
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') rethrow;
      debugPrint(
        'Portal screenshot failed (${error.code}: ${error.message}); '
        'falling back to CLI tools',
      );
      return await _captureWithSystemTools(display);
    }
  }

  Future<ui.Image> _decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Fallback for platforms with no portal (or an older one): ask a desktop
  /// screenshot tool to write a PNG and crop it to the target display.
  Future<ui.Image> _captureWithSystemTools(DisplayInfo display) async =>
      _cropToDisplay(await _systemToolImage(), display);

  /// Whole-desktop screenshot written by the first available CLI tool.
  Future<ui.Image> _systemToolImage() async {
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
          return await _decode(bytes);
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
