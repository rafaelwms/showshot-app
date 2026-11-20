import 'dart:math' as math;
import 'dart:ui';

/// One display as the stitcher sees it.
class ScreenTile {
  const ScreenTile({required this.globalBounds, required this.pixelsPerUnit});

  /// Position and size in the platform's global coordinate space (points on
  /// macOS, physical pixels on Windows/Linux). May hold negative coordinates.
  final Rect globalBounds;

  /// Captured image pixels per global unit (`DisplayInfo.pixelsPerGlobalUnit`).
  final double pixelsPerUnit;
}

/// Where each display lands on the combined canvas.
class CombinedLayout {
  const CombinedLayout({
    required this.width,
    required this.height,
    required this.scale,
    required this.destRects,
  });

  /// Canvas size in pixels.
  final int width;
  final int height;

  /// Canvas pixels per global unit actually used (after any size cap).
  final double scale;

  /// Destination rect (canvas pixels, whole numbers) for each input tile, in
  /// input order.
  final List<Rect> destRects;
}

/// Pure layout math for "All screens → one combined image".
class ScreenLayout {
  const ScreenLayout._();

  /// Largest canvas side we ask the GPU for; bigger layouts are scaled down
  /// uniformly to fit.
  static const defaultMaxDimension = 16384;

  /// Stitches [tiles] according to their real desktop positions.
  ///
  /// The canvas uses the *highest* pixel density among the displays, so no
  /// display loses detail: on macOS (points) a Retina 2x display next to a 1x
  /// one makes the canvas 2x and the 1x display is upscaled; on Windows/Linux
  /// the global space is already physical pixels (density 1 for every tile),
  /// so each display is copied 1:1 at its real offset. Gaps between displays
  /// (non-rectangular arrangements) are simply not covered by any rect.
  ///
  /// Edges are rounded individually (not widths), so touching displays stay
  /// seamless.
  static CombinedLayout compute(
    List<ScreenTile> tiles, {
    int maxDimension = defaultMaxDimension,
  }) {
    if (tiles.isEmpty) {
      return const CombinedLayout(width: 0, height: 0, scale: 1, destRects: []);
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var scale = 0.0;
    for (final tile in tiles) {
      final b = tile.globalBounds;
      minX = math.min(minX, b.left);
      minY = math.min(minY, b.top);
      maxX = math.max(maxX, b.right);
      maxY = math.max(maxY, b.bottom);
      scale = math.max(scale, tile.pixelsPerUnit);
    }
    if (scale <= 0) scale = 1;

    var width = ((maxX - minX) * scale).ceil();
    var height = ((maxY - minY) * scale).ceil();
    final longest = math.max(width, height);
    if (longest > maxDimension) {
      scale *= maxDimension / longest;
      width = math.min(((maxX - minX) * scale).ceil(), maxDimension);
      height = math.min(((maxY - minY) * scale).ceil(), maxDimension);
    }

    final rects = <Rect>[
      for (final tile in tiles)
        Rect.fromLTRB(
          ((tile.globalBounds.left - minX) * scale).roundToDouble(),
          ((tile.globalBounds.top - minY) * scale).roundToDouble(),
          math.min(
            ((tile.globalBounds.right - minX) * scale).roundToDouble(),
            width.toDouble(),
          ),
          math.min(
            ((tile.globalBounds.bottom - minY) * scale).roundToDouble(),
            height.toDouble(),
          ),
        ),
    ];
    return CombinedLayout(
      width: width,
      height: height,
      scale: scale,
      destRects: rects,
    );
  }

  /// Display order used for file naming and stitching: left to right, then
  /// top to bottom, so "screen 1" is the leftmost one whatever order the OS
  /// enumerates them in. Returns indices into [bounds].
  static List<int> spatialOrder(List<Rect> bounds) {
    final indices = List<int>.generate(bounds.length, (i) => i);
    indices.sort((a, b) {
      final byLeft = bounds[a].left.compareTo(bounds[b].left);
      return byLeft != 0 ? byLeft : bounds[a].top.compareTo(bounds[b].top);
    });
    return indices;
  }
}
