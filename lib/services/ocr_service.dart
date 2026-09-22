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
      // `stdout` as the output base tells tesseract to print the result
      // instead of writing a `.txt` file.
      final result = await Process.run('tesseract', [
        inputPath,
        'stdout',
        '--psm',
        '6',
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
}
