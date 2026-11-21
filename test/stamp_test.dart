import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoshot/models/annotation.dart';

const _style = AnnotationStyle(
  color: Color(0xFF000000),
  strokeWidth: 3,
  brushSize: 20,
);

StampAnnotation _stamp(List<Offset> points, Offset offset) =>
    StampAnnotation(id: 's', style: _style, points: points, offset: offset);

void main() {
  group('StampSourceState (aligned mode)', () {
    test('no source until set; no offset until the first stroke', () {
      final state = StampSourceState();
      expect(state.hasSource, isFalse);
      state.setSource(const Offset(100, 100));
      expect(state.hasSource, isTrue);
      expect(state.offset, isNull);
      expect(state.markerFor(const Offset(5, 5)), const Offset(100, 100));
    });

    test('first stroke fixes offset = source - first point', () {
      final state = StampSourceState()..setSource(const Offset(100, 80));
      expect(state.beginStroke(const Offset(10, 20)), const Offset(90, 60));
      expect(state.offset, const Offset(90, 60));
    });

    test('later strokes reuse the offset (aligned)', () {
      final state = StampSourceState()..setSource(const Offset(100, 80));
      state.beginStroke(const Offset(10, 20));
      expect(state.beginStroke(const Offset(300, 300)), const Offset(90, 60));
      // The crosshair follows the pointer by that offset.
      expect(state.markerFor(const Offset(300, 300)), const Offset(390, 360));
    });

    test('a new source resets the offset', () {
      final state = StampSourceState()..setSource(const Offset(100, 80));
      state.beginStroke(const Offset(10, 20));
      state.setSource(const Offset(500, 500));
      expect(state.offset, isNull);
      expect(state.beginStroke(const Offset(400, 450)), const Offset(100, 50));
    });

    test('offset is rounded to whole pixels', () {
      final state = StampSourceState()..setSource(const Offset(100.4, 80.7));
      expect(state.beginStroke(const Offset(10.2, 20.1)), const Offset(90, 61));
    });
  });

  group('StampAnnotation', () {
    test('translating keeps the copied content: offset shrinks by delta', () {
      final a = _stamp([
        const Offset(10, 10),
        const Offset(30, 10),
      ], const Offset(50, 40));
      final moved = a.translated(const Offset(7, -3)) as StampAnnotation;
      expect(moved.points.first, const Offset(17, 7));
      expect(moved.offset, const Offset(43, 43));
      // Pixel at (p + delta) samples (p + delta) + offset' == p + offset.
      expect(moved.points.first + moved.offset, a.points.first + a.offset);
    });

    test('hit test along the stroke within the brush radius', () {
      final a = _stamp([const Offset(0, 0), const Offset(100, 0)], Offset.zero);
      expect(a.hitTest(const Offset(50, 9), 0), isTrue); // radius 10
      expect(a.hitTest(const Offset(50, 11), 0), isFalse);
      expect(a.hitTest(const Offset(50, 15), 6), isTrue); // with tolerance
      expect(a.hitTest(const Offset(-9, 0), 0), isTrue); // round cap
      expect(a.hitTest(const Offset(-12, 0), 0), isFalse);
    });

    test('single point stroke hit test and bounds', () {
      final a = _stamp([const Offset(40, 40)], Offset.zero);
      expect(a.hitTest(const Offset(45, 40), 0), isTrue);
      expect(a.hitTest(const Offset(55, 40), 0), isFalse);
      expect(a.bounds, const Rect.fromLTRB(30, 30, 50, 50));
    });

    test('no handles, no rotation', () {
      final a = _stamp([const Offset(0, 0), const Offset(10, 10)], Offset.zero);
      expect(a.rotatable, isFalse);
      expect(a.handles, isEmpty);
      expect(identical(a.rotatedBy(1), a), isTrue);
      expect(a.withHandle(0, const Offset(5, 5)), same(a));
    });

    test('withStyle keeps points and offset', () {
      final a = _stamp([const Offset(1, 2)], const Offset(3, 4));
      final b = a.withStyle(_style.copyWith(hardness: 1)) as StampAnnotation;
      expect(b.points, a.points);
      expect(b.offset, a.offset);
      expect(b.style.hardness, 1);
    });
  });

  test('stampSigma: hard edge has no blur, soft edge grows with size', () {
    expect(stampSigma(40, 1), 0);
    expect(stampSigma(40, 0.5), 4);
    expect(stampSigma(40, 0), 8);
    expect(stampSigma(80, 0.5), 8);
    // The core (diameter - 4 sigma) never collapses.
    expect(40 - 4 * stampSigma(40, 0), greaterThan(0));
  });
}
