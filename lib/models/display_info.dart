import 'dart:ui';

/// A physical display as reported by the native layer.
///
/// [bounds] is expressed in the platform's *global* coordinate space:
/// points on macOS, physical pixels on Windows and Linux. [globalPixelRatio]
/// converts that space into Flutter logical pixels for a window covering the
/// display (1.0 on macOS, `scale` elsewhere). Captured image pixels are always
/// `logical * scale`.
class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.bounds,
    required this.scale,
    required this.isPrimary,
    required this.name,
    required this.globalPixelRatio,
  });

  final int id;
  final Rect bounds;
  final double scale;
  final bool isPrimary;
  final String name;
  final double globalPixelRatio;

  /// Size of the display in Flutter logical pixels.
  Size get logicalSize =>
      Size(bounds.width / globalPixelRatio, bounds.height / globalPixelRatio);

  /// Size of the display in device pixels (the captured image size).
  Size get pixelSize => logicalSize * scale;

  bool containsGlobal(Offset point) => bounds.contains(point);

  /// Converts a global point into logical coordinates local to this display.
  Offset globalToLocal(Offset point) =>
      (point - bounds.topLeft) / globalPixelRatio;

  /// Converts a global rect into logical coordinates local to this display.
  Rect globalRectToLocal(Rect rect) {
    final topLeft = globalToLocal(rect.topLeft);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      rect.width / globalPixelRatio,
      rect.height / globalPixelRatio,
    );
  }

  factory DisplayInfo.fromMap(
    Map<Object?, Object?> map,
    double Function(double scale) globalPixelRatioForScale,
  ) {
    final scale = (map['scale'] as num?)?.toDouble() ?? 1.0;
    return DisplayInfo(
      id: (map['id'] as num).toInt(),
      bounds: Rect.fromLTWH(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
        (map['width'] as num).toDouble(),
        (map['height'] as num).toDouble(),
      ),
      scale: scale,
      isPrimary: map['isPrimary'] == true,
      name: map['name'] as String? ?? 'Display',
      globalPixelRatio: globalPixelRatioForScale(scale),
    );
  }

  @override
  String toString() =>
      'DisplayInfo($id, $name, bounds: $bounds, scale: $scale, primary: $isPrimary)';
}
