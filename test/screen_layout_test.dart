import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoshot/services/screen_layout.dart';

ScreenTile tile(double l, double t, double w, double h, [double ppu = 1]) =>
    ScreenTile(globalBounds: Rect.fromLTWH(l, t, w, h), pixelsPerUnit: ppu);

void main() {
  group('ScreenLayout.compute', () {
    test('single display: canvas equals the display', () {
      final l = ScreenLayout.compute([tile(0, 0, 1920, 1080)]);
      expect((l.width, l.height), (1920, 1080));
      expect(l.destRects.single, const Rect.fromLTWH(0, 0, 1920, 1080));
    });

    test('two side-by-side displays, physical pixels', () {
      final l = ScreenLayout.compute([
        tile(0, 0, 1920, 1080),
        tile(1920, 0, 2560, 1440),
      ]);
      expect((l.width, l.height), (4480, 1440));
      expect(l.destRects[0], const Rect.fromLTWH(0, 0, 1920, 1080));
      expect(l.destRects[1], const Rect.fromLTWH(1920, 0, 2560, 1440));
    });

    test('negative coordinates are shifted to the canvas origin', () {
      // Secondary monitor to the left and above the primary.
      final l = ScreenLayout.compute([
        tile(0, 0, 1920, 1080),
        tile(-1280, -200, 1280, 1024),
      ]);
      expect((l.width, l.height), (3200, 1280));
      expect(l.destRects[0], const Rect.fromLTWH(1280, 200, 1920, 1080));
      expect(l.destRects[1], const Rect.fromLTWH(0, 0, 1280, 1024));
    });

    test('non-rectangular arrangement leaves uncovered gaps', () {
      final l = ScreenLayout.compute([
        tile(0, 0, 1000, 1000),
        tile(1000, 600, 1000, 400),
      ]);
      expect((l.width, l.height), (2000, 1000));
      // The top-right corner (1000..2000 x 0..600) belongs to no display.
      final covered = l.destRects.any(
        (r) => r.contains(const Offset(1500, 300)),
      );
      expect(covered, isFalse);
    });

    test('macOS mixed scale: points, canvas uses the highest density', () {
      // 1440x900 pt Retina (2x) next to a 1920x1080 pt 1x monitor.
      final l = ScreenLayout.compute([
        tile(0, 0, 1440, 900, 2),
        tile(1440, 0, 1920, 1080, 1),
      ]);
      expect(l.scale, 2);
      expect((l.width, l.height), (6720, 2160));
      expect(l.destRects[0], const Rect.fromLTWH(0, 0, 2880, 1800));
      // The 1x display is upscaled to 2x its pixel size.
      expect(l.destRects[1], const Rect.fromLTWH(2880, 0, 3840, 2160));
    });

    test('macOS all-1x keeps scale 1', () {
      final l = ScreenLayout.compute([
        tile(0, 0, 1920, 1080),
        tile(0, 1080, 1920, 1080),
      ]);
      expect(l.scale, 1);
      expect((l.width, l.height), (1920, 2160));
    });

    test('fractional scale rounds edges, not widths (no seams)', () {
      final l = ScreenLayout.compute([
        tile(0, 0, 1000.5, 100, 1.5),
        tile(1000.5, 0, 1000, 100, 1.5),
      ]);
      expect(l.destRects[0].right, l.destRects[1].left);
      expect(l.width, (2000.5 * 1.5).ceil());
    });

    test('oversized layout is scaled down to the max dimension', () {
      final l = ScreenLayout.compute([
        tile(0, 0, 3840, 2160),
        tile(3840, 0, 3840, 2160),
        tile(7680, 0, 3840, 2160),
        tile(11520, 0, 3840, 2160),
        tile(15360, 0, 3840, 2160),
      ], maxDimension: 16384);
      expect(l.width, lessThanOrEqualTo(16384));
      expect(l.height, lessThanOrEqualTo(16384));
      expect(l.scale, lessThan(1));
      expect(l.destRects.last.right, lessThanOrEqualTo(l.width.toDouble()));
    });

    test('empty input gives an empty layout', () {
      final l = ScreenLayout.compute(const []);
      expect((l.width, l.height), (0, 0));
      expect(l.destRects, isEmpty);
    });
  });

  group('ScreenLayout.spatialOrder', () {
    test('orders left to right, ties top to bottom', () {
      final order = ScreenLayout.spatialOrder(const [
        Rect.fromLTWH(1920, 0, 1920, 1080),
        Rect.fromLTWH(0, 1080, 1920, 1080),
        Rect.fromLTWH(0, 0, 1920, 1080),
        Rect.fromLTWH(-1920, 0, 1920, 1080),
      ]);
      expect(order, [3, 2, 1, 0]);
    });
  });
}
