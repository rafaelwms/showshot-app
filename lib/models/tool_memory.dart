import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'annotation.dart';

/// The editor tool settings remembered between captures (opt-in via
/// `AppSettings.rememberTools`).
///
/// Width and font size are stored in *logical* (UI) units, i.e. what the
/// properties bar shows, not image pixels: the editor works in image pixels
/// and `EditorController.pixelRatio` (image px per logical px) differs per
/// capture, so storing pixels would change the visual size on another
/// display scale. Everything here is pure so it can be unit-tested.
class ToolMemory {
  const ToolMemory({
    this.tool,
    required this.colorArgb,
    required this.strokeWidth,
    required this.opacity,
    required this.filled,
    required this.fontSize,
    required this.smoothing,
    this.textAlign = TextAlign.left,
  });

  /// Tools never restored as the starting tool: the OCR region tool is a
  /// one-shot action, not something to annotate with.
  static const transientTools = {ToolType.ocr};

  /// [ToolType.name] of the last non-transient tool; null = editor default.
  final String? tool;
  final int colorArgb;

  /// Logical (UI) stroke width.
  final double strokeWidth;
  final double opacity;
  final bool filled;

  /// Logical (UI) font size.
  final double fontSize;
  final double smoothing;

  /// Text alignment (left, center or right only).
  final TextAlign textAlign;

  // Same ranges as the properties bar sliders.
  static const _minWidth = 1.0, _maxWidth = 24.0;
  static const _minFont = 8.0, _maxFont = 96.0;

  /// Captures the editor state. A transient [tool] keeps the [previous]
  /// remembered tool, so quitting right after an OCR selection reopens on
  /// the tool used before it.
  factory ToolMemory.capture({
    ToolMemory? previous,
    required ToolType tool,
    required AnnotationStyle style,
    required double pixelRatio,
  }) {
    final ratio = pixelRatio <= 0 ? 1.0 : pixelRatio;
    return ToolMemory(
      tool: transientTools.contains(tool) ? previous?.tool : tool.name,
      colorArgb: style.color.toARGB32(),
      strokeWidth: style.strokeWidth / ratio,
      opacity: style.opacity,
      filled: style.filled,
      fontSize: style.fontSize / ratio,
      smoothing: style.smoothing,
      textAlign: _sanitizeAlign(style.textAlign),
    );
  }

  static TextAlign _sanitizeAlign(TextAlign a) =>
      a == TextAlign.center || a == TextAlign.right ? a : TextAlign.left;

  /// The remembered tool, or null when none is stored, the name is unknown
  /// (old/foreign prefs) or the tool is transient.
  ToolType? get toolType {
    for (final t in ToolType.values) {
      if (t.name == tool) return transientTools.contains(t) ? null : t;
    }
    return null;
  }

  /// The style for a capture with the given [pixelRatio] (values clamped to
  /// the slider ranges, pixel sizes rounded like the sliders do).
  AnnotationStyle toStyle(double pixelRatio) {
    final ratio = pixelRatio <= 0 ? 1.0 : pixelRatio;
    return AnnotationStyle(
      color: Color(colorArgb),
      strokeWidth: (strokeWidth.clamp(_minWidth, _maxWidth) * ratio)
          .roundToDouble(),
      opacity: opacity.clamp(0.1, 1.0).toDouble(),
      filled: filled,
      fontSize: (fontSize.clamp(_minFont, _maxFont) * ratio).roundToDouble(),
      smoothing: smoothing.clamp(0.0, 1.0).toDouble(),
      textAlign: textAlign,
    );
  }

  /// True when [other] would restore exactly the same editor state.
  bool sameAs(ToolMemory? other) =>
      other != null &&
      other.tool == tool &&
      other.colorArgb == colorArgb &&
      (other.strokeWidth - strokeWidth).abs() < 1e-6 &&
      other.opacity == opacity &&
      other.filled == filled &&
      (other.fontSize - fontSize).abs() < 1e-6 &&
      other.smoothing == smoothing &&
      other.textAlign == textAlign;

  Map<String, dynamic> toJson() => {
    'tool': tool,
    'color': colorArgb,
    'strokeWidth': strokeWidth,
    'opacity': opacity,
    'filled': filled,
    'fontSize': fontSize,
    'smoothing': smoothing,
    'textAlign': textAlign.name,
  };

  /// Lenient parse: anything missing or of the wrong type falls back to the
  /// editor defaults (3 px wide, 20 pt text, first palette color).
  factory ToolMemory.fromJson(Map<String, dynamic> json, int defaultArgb) {
    double number(String key, double fallback) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble() : fallback;
    }

    final rawTool = json['tool'];
    final color = json['color'];
    return ToolMemory(
      tool: rawTool is String ? rawTool : null,
      colorArgb: color is int ? color : defaultArgb,
      strokeWidth: math.max(0.0, number('strokeWidth', 3)),
      opacity: number('opacity', 1),
      filled: json['filled'] is bool ? json['filled'] as bool : false,
      fontSize: math.max(0.0, number('fontSize', 20)),
      smoothing: number('smoothing', 0),
      // Missing or unknown values (old prefs, tampering) mean left.
      textAlign: switch (json['textAlign']) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      },
    );
  }
}
