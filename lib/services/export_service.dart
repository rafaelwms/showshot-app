import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/annotation.dart';
import '../models/app_settings.dart';
import 'native_bridge.dart';

/// Renders, encodes, copies and saves screenshots.
class ExportService {
  ExportService(this._native);

  final NativeBridge _native;

  /// Flattens [annotations] onto [source] and returns a new image.
  static Future<ui.Image> render(
    ui.Image source,
    List<Annotation> annotations,
  ) async {
    if (annotations.isEmpty) return source.clone();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    for (final annotation in annotations) {
      annotation.paint(canvas, source);
    }
    final picture = recorder.endRecording();
    final result = await picture.toImage(source.width, source.height);
    picture.dispose();
    return result;
  }

  /// Crops [source] to [rect] (image pixel coordinates), clamped to the
  /// image bounds.
  static Future<ui.Image> crop(ui.Image source, ui.Rect rect) async {
    final full = ui.Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );
    final src = rect.intersect(full);
    if (src.width < 1 || src.height < 1) return source.clone();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dst = ui.Rect.fromLTWH(0, 0, src.width, src.height);
    canvas.drawImageRect(source, src, dst, ui.Paint());
    final picture = recorder.endRecording();
    final result = await picture.toImage(
      src.width.round(),
      src.height.round(),
    );
    picture.dispose();
    return result;
  }

  static Future<Uint8List> encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<Uint8List> rawRgba(ui.Image image) async {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) throw StateError('Raw encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<Uint8List> encodeJpg(ui.Image image, int quality) async {
    final rgba = await rawRgba(image);
    return compute(
      _encodeJpgIsolate,
      _JpgJob(rgba, image.width, image.height, quality),
    );
  }

  static Uint8List _encodeJpgIsolate(_JpgJob job) {
    final source = img.Image.fromBytes(
      width: job.width,
      height: job.height,
      bytes: job.rgba.buffer,
      bytesOffset: job.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    // JPEG has no alpha; composite onto white to avoid black fringes.
    final opaque = img.Image(
      width: job.width,
      height: job.height,
      numChannels: 3,
    );
    opaque.clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(opaque, source);
    return img.encodeJpg(opaque, quality: job.quality);
  }

  Future<bool> copyToClipboard(ui.Image image) async {
    final png = await encodePng(image);
    final rgba = await rawRgba(image);
    return _native.setClipboardImage(
      png: png,
      rgba: rgba,
      width: image.width,
      height: image.height,
    );
  }

  static String defaultFileName(ImageFormat format, [DateTime? when]) {
    final t = when ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
    return 'ShowShot_$stamp.${format.name}';
  }

  /// `~/Pictures/ShowShot` (created on demand).
  static Future<Directory> defaultDirectory() async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    var pictures = Directory('$home${Platform.pathSeparator}Pictures');
    if (Platform.isLinux) {
      try {
        final result = await Process.run('xdg-user-dir', ['PICTURES']);
        final path = (result.stdout as String).trim();
        if (result.exitCode == 0 && path.isNotEmpty) pictures = Directory(path);
      } catch (_) {}
    }
    final dir = Directory('${pictures.path}${Platform.pathSeparator}ShowShot');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> targetDirectory(AppSettings settings) async {
    final custom = settings.saveDirectory;
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (await dir.exists()) return dir;
    }
    return defaultDirectory();
  }

  /// Saves [image] according to [settings]. Returns the written path, or null
  /// when the user cancelled the dialog.
  Future<String?> save(
    ui.Image image,
    AppSettings settings, {
    bool forceDialog = false,
  }) async {
    var format = settings.saveFormat;
    String path;
    if (settings.askWhereToSave || forceDialog) {
      final dir = await targetDirectory(settings);
      final location = await getSaveLocation(
        suggestedName: defaultFileName(format),
        initialDirectory: dir.path,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PNG',
            extensions: ['png'],
            mimeTypes: ['image/png'],
          ),
          XTypeGroup(
            label: 'JPEG',
            extensions: ['jpg', 'jpeg'],
            mimeTypes: ['image/jpeg'],
          ),
        ],
      );
      if (location == null) return null;
      path = location.path;
      final lower = path.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        format = ImageFormat.jpg;
      } else if (lower.endsWith('.png')) {
        format = ImageFormat.png;
      } else {
        path = '$path.${format.name}';
      }
    } else {
      final dir = await targetDirectory(settings);
      path = '${dir.path}${Platform.pathSeparator}${defaultFileName(format)}';
    }
    final bytes = format == ImageFormat.jpg
        ? await encodeJpg(image, settings.jpgQuality)
        : await encodePng(image);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}

class _JpgJob {
  const _JpgJob(this.rgba, this.width, this.height, this.quality);
  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
}
