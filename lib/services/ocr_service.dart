import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'native_bridge.dart';

/// Recognizes text in a screenshot.
///
/// macOS/Windows go through the native `shoshot/native` channel (Vision /
/// Windows.Media.Ocr). Linux has no comparable OS-bundled API, so it shells
/// out to `tesseract` if it's on `$PATH` — the same "ask an external tool"
/// pattern [CaptureService] already uses for Wayland screenshots.
class OcrService {
  OcrService(this._native);

  final NativeBridge _native;

  /// Returns the recognized text, or null if none was found / recognition
  /// isn't available on this platform.
  Future<String?> recognize(Uint8List png) async {
    if (Platform.isLinux) {
      final viaTesseract = await _recognizeWithTesseract(png);
      if (viaTesseract != null) return viaTesseract;
    }
    return _native.recognizeText(png);
  }

  Future<String?> _recognizeWithTesseract(Uint8List png) async {
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final inputPath = '${tmp.path}/shoshot_ocr_$stamp.png';
    final input = File(inputPath);
    try {
      await input.writeAsBytes(png, flush: true);
      final languages = await _tesseractLanguages();
      // `stdout` as the output base tells tesseract to print the result
      // instead of writing a `.txt` file. `--psm 3` (automatic layout) copes
      // with the scattered blocks/columns screenshots tend to have.
      final result = await Process.run('tesseract', [
        inputPath,
        'stdout',
        if (languages.isNotEmpty) ...['-l', languages],
        '--psm',
        '3',
      ]);
      if (result.exitCode != 0) return null;
      final text = (result.stdout as String).trim();
      return text.isEmpty ? null : text;
    } on ProcessException {
      // tesseract isn't installed; fall back to the native channel.
      return null;
    } catch (error) {
      debugPrint('tesseract OCR failed: $error');
      return null;
    } finally {
      if (await input.exists()) await input.delete();
    }
  }

  String? _languages;

  /// tesseract only reads English unless told otherwise, which drops accents
  /// (Portuguese "não" comes out as "nao"). Use the OS language plus English,
  /// limited to the traineddata packs actually installed
  /// (`tesseract-ocr-por`, …).
  Future<String> _tesseractLanguages() async {
    if (_languages != null) return _languages!;
    final installed = <String>{};
    try {
      final result = await Process.run('tesseract', ['--list-langs']);
      // First line is a header ("List of available languages in …").
      installed.addAll(
        (result.stdout as String).split('\n').skip(1).map((l) => l.trim()),
      );
    } catch (_) {}
    const iso639_2 = {
      'pt': 'por',
      'en': 'eng',
      'es': 'spa',
      'fr': 'fra',
      'de': 'deu',
      'it': 'ita',
      'nl': 'nld',
      'pl': 'pol',
      'ru': 'rus',
      'ja': 'jpn',
      'zh': 'chi_sim',
      'ko': 'kor',
    };
    final system = iso639_2[Platform.localeName.split(RegExp('[_.-]')).first];
    final wanted = {?system, 'eng'}.where(installed.contains);
    return _languages = wanted.join('+');
  }
}
