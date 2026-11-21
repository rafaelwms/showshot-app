import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/annotation.dart';
import '../models/app_settings.dart';
import 'file_namer.dart';
import 'folder_access.dart';
import 'native_bridge.dart';
import 'screen_layout.dart';

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
    final result = await picture.toImage(src.width.round(), src.height.round());
    picture.dispose();
    return result;
  }

  /// Stitches per-display [images] onto one canvas following [layout]
  /// (`layout.destRects[i]` is where `images[i]` goes). The gaps stay
  /// transparent, or black when [opaqueBlack] is set (JPG has no alpha).
  /// Drawing and the PNG encode run on the engine's raster/IO threads, not
  /// the UI thread; JPG encoding goes through an isolate (see [encodeJpg]).
  static Future<ui.Image> compose(
    List<ui.Image> images,
    CombinedLayout layout, {
    bool opaqueBlack = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Rect.fromLTWH(
      0,
      0,
      layout.width.toDouble(),
      layout.height.toDouble(),
    );
    if (opaqueBlack) {
      canvas.drawRect(size, ui.Paint()..color = const ui.Color(0xFF000000));
    }
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        layout.destRects[i],
        paint,
      );
    }
    final picture = recorder.endRecording();
    final ui.Image result;
    try {
      result = await picture.toImage(layout.width, layout.height);
    } finally {
      picture.dispose();
    }
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

  static String defaultFileName(ImageFormat format, [DateTime? when]) =>
      FileNamer.timestampName(format.name, when ?? DateTime.now());

  /// Called with the new counter value after a save that consumed a
  /// sequential number, so the caller can persist it as `sequenceNext`.
  void Function(int next)? onSequenceAdvanced;

  /// Next file name for [dir] according to [settings] (skips taken numbers).
  static Future<GeneratedName> _nextName(AppSettings settings, Directory dir) {
    return FileNamer.next(
      settings: settings,
      now: DateTime.now(),
      exists: (name) =>
          File('${dir.path}${Platform.pathSeparator}$name').exists(),
    );
  }

  /// File name without directory or extension, for either separator style.
  static String _stem(String path) {
    final base = path.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    return dot <= 0 ? base : base.substring(0, dot);
  }

  /// `~/Pictures/ShowShot` path, without touching the disk.
  static Future<String> defaultDirectoryPath() async {
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
    return '${pictures.path}${Platform.pathSeparator}ShowShot';
  }

  /// `~/Pictures/ShowShot` (created on demand).
  static Future<Directory> defaultDirectory() async {
    final dir = Directory(await defaultDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Picks the folder a save goes to. Pure apart from the injected [exists] /
  /// [create] callbacks, so it can be unit-tested with fake file systems.
  ///
  /// Order: the last used folder (only when [useLastFolder]) -> the configured
  /// folder -> the built-in default, which is created when missing.
  static Future<String> resolveSaveDirectoryPath({
    required bool useLastFolder,
    required String? lastDirectory,
    required String? configuredDirectory,
    required Future<String> Function() builtInDefault,
    required Future<bool> Function(String path) exists,
    required Future<void> Function(String path) create,
  }) async {
    if (useLastFolder &&
        lastDirectory != null &&
        lastDirectory.isNotEmpty &&
        await exists(lastDirectory)) {
      return lastDirectory;
    }
    if (configuredDirectory != null &&
        configuredDirectory.isNotEmpty &&
        await exists(configuredDirectory)) {
      return configuredDirectory;
    }
    final fallback = await builtInDefault();
    if (!await exists(fallback)) await create(fallback);
    return fallback;
  }

  /// Called with a fresh base64 bookmark when macOS reports the stored
  /// configured-folder bookmark as stale (folder moved/renamed), so the caller
  /// can persist it.
  void Function(String bookmark)? onBookmarkRefreshed;

  /// Same as [onBookmarkRefreshed], for `lastSaveDirectoryBookmark`.
  void Function(String bookmark)? onLastBookmarkRefreshed;

  /// macOS: called after the user granted access to a folder through
  /// [NativeBridge.requestFolderAccess] with the folder actually chosen and
  /// its base64 bookmark, so the caller can persist both as
  /// `lastSaveDirectory(+Bookmark)`.
  void Function(String directory, String bookmark)? onLastFolderAccess;

  /// Texts of the macOS "allow this folder" panel, in the current language.
  ({String message, String prompt}) Function()? folderAccessTexts;

  /// Bookmarks already resolved (and being accessed) in this launch -> path.
  final Map<String, String> _resolvedBookmarks = {};

  /// Normalized folders this launch can write to thanks to a bookmark or a
  /// granted [NativeBridge.requestFolderAccess].
  final Set<String> _accessibleFolders = {};

  /// Folders whose permission panel the user cancelled this launch (in
  /// memory only: asked again after a relaunch).
  final Set<String> _declinedFolders = {};

  /// Called with the directory of every successful save, so the caller can
  /// persist it as `lastSaveDirectory`.
  void Function(String directory)? onSaved;

  /// Folder for the next save. [ignoreLast] skips the "last used folder" step
  /// (used to retry after a write to it failed).
  Future<Directory> targetDirectory(
    AppSettings settings, {
    bool ignoreLast = false,
  }) async {
    final custom = settings.saveDirectory;
    String? configured;
    if (custom != null && custom.isNotEmpty) {
      // Also re-activates the sandbox bookmark for this launch.
      configured = await _sandboxAccessiblePath(settings) ?? custom;
    }
    final useLast = settings.saveToLastFolder && !ignoreLast;
    var last = settings.lastSaveDirectory;
    if (useLast) {
      // Re-activates the bookmark of the last folder (macOS sandbox) before
      // we check that it exists; also follows a moved/renamed folder.
      last = await _sandboxLastPath(settings) ?? last;
    }
    final path = await resolveSaveDirectoryPath(
      useLastFolder: useLast,
      lastDirectory: last,
      configuredDirectory: configured,
      builtInDefault: defaultDirectoryPath,
      exists: (p) => Directory(p).exists(),
      create: (p) async {
        await Directory(p).create(recursive: true);
      },
    );
    return Directory(path);
  }

  /// macOS/App Sandbox: re-opens access to the custom folder through its
  /// security-scoped bookmark, once per launch. Null when there's no bookmark
  /// (other platforms, or a folder picked before bookmarks existed).
  Future<String?> _sandboxAccessiblePath(AppSettings settings) {
    return _resolveBookmark(
      settings.saveDirectoryBookmark,
      onBookmarkRefreshed,
    );
  }

  /// Same for the last used folder's bookmark (`lastSaveDirectoryBookmark`).
  Future<String?> _sandboxLastPath(AppSettings settings) {
    if (settings.lastSaveDirectory.isEmpty) return Future.value(null);
    return _resolveBookmark(
      settings.lastSaveDirectoryBookmark,
      onLastBookmarkRefreshed,
    );
  }

  Future<String?> _resolveBookmark(
    String? bookmark,
    void Function(String bookmark)? onRefreshed,
  ) async {
    if (!Platform.isMacOS || bookmark == null || bookmark.isEmpty) return null;
    final cached = _resolvedBookmarks[bookmark];
    if (cached != null) return cached;
    final resolved = await _native.resolveDirectoryBookmark(
      base64Decode(bookmark),
    );
    if (resolved == null) return null;
    _resolvedBookmarks[bookmark] = resolved.path;
    _accessibleFolders.add(FolderAccess.normalize(resolved.path));
    final refreshed = resolved.refreshed;
    if (refreshed != null) {
      final encoded = base64Encode(refreshed);
      _resolvedBookmarks[encoded] = resolved.path;
      onRefreshed?.call(encoded);
    }
    return resolved.path;
  }

  /// macOS + "save to the last folder": a folder reached only through the
  /// Save As panel is writable for this launch only. After the save (the file
  /// is already written), asks once per folder for a persistent permission so
  /// the next launch's quick saves can really go there.
  Future<void> _offerFolderAccess(AppSettings settings, String folder) async {
    if (!Platform.isMacOS || !settings.saveToLastFolder) return;
    final texts = folderAccessTexts?.call();
    if (texts == null) return;
    final defaultDir = await defaultDirectoryPath();
    final needs = FolderAccess.needsPrompt(
      folder: folder,
      accessible: _accessibleFolders,
      declined: _declinedFolders,
      freeRoots: [File(defaultDir).parent.path],
    );
    if (!needs) return;
    // Marked first: a cancel (or any failure) must not nag again this launch.
    _declinedFolders.add(FolderAccess.normalize(folder));
    final granted = await _native.requestFolderAccess(
      path: folder,
      message: texts.message,
      prompt: texts.prompt,
    );
    if (granted == null) return;
    final encoded = base64Encode(granted.bookmark);
    _resolvedBookmarks[encoded] = granted.path;
    _accessibleFolders.add(FolderAccess.normalize(granted.path));
    onLastFolderAccess?.call(granted.path, encoded);
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
    final dialogUsed = settings.askWhereToSave || forceDialog;
    // Counter value this save consumes (null: timestamp name, or the user
    // typed a different name in the Save As dialog).
    int? consumed;
    if (dialogUsed) {
      final dir = await targetDirectory(settings);
      final suggested = await _nextName(settings, dir);
      final location = await getSaveLocation(
        suggestedName: suggested.name,
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
      // Only advance the counter when the user kept the suggested name
      // (extension changes don't matter); a custom name leaves it alone.
      if (_stem(path) == _stem(suggested.name)) consumed = suggested.usedNumber;
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
      final generated = await _nextName(settings, dir);
      consumed = generated.usedNumber;
      path = '${dir.path}${Platform.pathSeparator}${generated.name}';
    }
    final bytes = format == ImageFormat.jpg
        ? await encodeJpg(image, settings.jpgQuality)
        : await encodePng(image);
    try {
      await File(path).writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      // Quick save into the last used folder can fail (e.g. macOS sandbox:
      // no bookmark for it after a relaunch). Retry silently in the default
      // folder; any other failure still propagates.
      if (dialogUsed ||
          !settings.saveToLastFolder ||
          settings.lastSaveDirectory.isEmpty) {
        rethrow;
      }
      final dir = await targetDirectory(settings, ignoreLast: true);
      // The fallback folder may already hold the number: pick again there.
      final generated = await _nextName(settings, dir);
      consumed = generated.usedNumber;
      path = '${dir.path}${Platform.pathSeparator}${generated.name}';
      await File(path).writeAsBytes(bytes, flush: true);
    }
    if (consumed != null) onSequenceAdvanced?.call(consumed + 1);
    final savedDir = File(path).parent.path;
    onSaved?.call(savedDir);
    if (dialogUsed) await _offerFolderAccess(settings, savedDir);
    return path;
  }

  /// Saves several images (one file each, in order) into the target folder,
  /// never asking where: the "All screens" path. Names follow
  /// [FileNamer.nextBatch]. Returns the written paths; the folder is the
  /// parent of any of them. Like [save], a failed write into the "last used
  /// folder" is retried once in the default folder.
  Future<List<String>> saveBatch(
    List<ui.Image> images,
    AppSettings settings,
  ) async {
    final format = settings.saveFormat;
    final encoded = <Uint8List>[
      for (final image in images)
        format == ImageFormat.jpg
            ? await encodeJpg(image, settings.jpgQuality)
            : await encodePng(image),
    ];
    Future<List<String>> write(Directory dir, List<GeneratedName> names) async {
      final paths = <String>[
        for (final n in names) '${dir.path}${Platform.pathSeparator}${n.name}',
      ];
      var written = 0;
      try {
        for (; written < paths.length; written++) {
          await File(paths[written])
              .writeAsBytes(encoded[written], flush: true);
        }
      } catch (_) {
        // All or nothing: don't leave half a batch behind (a later timestamp
        // save could overwrite it, and the counter isn't advanced for it).
        for (var i = 0; i < written; i++) {
          try {
            await File(paths[i]).delete();
          } catch (_) {}
        }
        rethrow;
      }
      return paths;
    }

    Future<(Directory, List<GeneratedName>)> plan({
      bool ignoreLast = false,
    }) async {
      final dir = await targetDirectory(settings, ignoreLast: ignoreLast);
      final names = await FileNamer.nextBatch(
        settings: settings,
        now: DateTime.now(),
        count: images.length,
        exists: (name) =>
            File('${dir.path}${Platform.pathSeparator}$name').exists(),
      );
      return (dir, names);
    }

    var (dir, names) = await plan();
    List<String> paths;
    try {
      paths = await write(dir, names);
    } on FileSystemException {
      if (!settings.saveToLastFolder || settings.lastSaveDirectory.isEmpty) {
        rethrow;
      }
      (dir, names) = await plan(ignoreLast: true);
      paths = await write(dir, names);
    }
    final used = names.map((n) => n.usedNumber).whereType<int>();
    if (used.isNotEmpty) {
      onSequenceAdvanced?.call(used.reduce((a, b) => a > b ? a : b) + 1);
    }
    onSaved?.call(dir.path);
    return paths;
  }
}

class _JpgJob {
  const _JpgJob(this.rgba, this.width, this.height, this.quality);
  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
}
