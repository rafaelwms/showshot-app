import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoshot/models/annotation.dart';
import 'package:shoshot/models/crop.dart';
import 'package:shoshot/models/edit_history.dart';

const _bounds = Size(1000, 800);

const _style = AnnotationStyle(
  color: Color(0xFF000000),
  strokeWidth: 3,
  brushSize: 20,
);

ShapeAnnotation _rect(String id, Offset a, Offset b, {double rotation = 0}) =>
    ShapeAnnotation(
      id: id,
      style: _style,
      kind: ShapeKind.rect,
      start: a,
      end: b,
      rotation: rotation,
    );

void main() {
  group('clampCropRect', () {
    test('snaps to whole pixels and stays inside the image', () {
      expect(
        clampCropRect(const Rect.fromLTWH(-10, -10, 5000, 5000), _bounds),
        const Rect.fromLTWH(0, 0, 1000, 800),
      );
      expect(
        clampCropRect(const Rect.fromLTWH(990.4, 790.2, 100, 100), _bounds),
        const Rect.fromLTWH(900, 700, 100, 100),
      );
    });

    test('enforces a minimum size', () {
      expect(
        clampCropRect(const Rect.fromLTWH(10, 10, 2, 2), _bounds),
        const Rect.fromLTWH(10, 10, minCropSize, minCropSize),
      );
    });
  });

  group('fitRectToRatio', () {
    test('largest rect of the ratio, centered, inside the current one', () {
      expect(
        fitRectToRatio(
          const Rect.fromLTWH(0, 0, 1000, 500),
          1,
          const Size(1000, 500),
        ),
        const Rect.fromLTWH(250, 0, 500, 500),
      );
      expect(
        fitRectToRatio(const Rect.fromLTWH(100, 100, 400, 300), 1, _bounds),
        const Rect.fromLTWH(150, 100, 300, 300),
      );
    });

    test('a rect already of that ratio is unchanged', () {
      expect(
        fitRectToRatio(
          const Rect.fromLTWH(0, 0, 1920, 1080),
          16 / 9,
          const Size(1920, 1080),
        ),
        const Rect.fromLTWH(0, 0, 1920, 1080),
      );
    });

    test('tall ratio: integer size, centered, within 1 px of the ratio', () {
      final r = fitRectToRatio(
        const Rect.fromLTWH(0, 0, 1000, 500),
        9 / 16,
        const Size(1000, 500),
      );
      expect(r.height, 500);
      expect(r.width, 281);
      expect(r.left, 360); // (1000 - 281) / 2 = 359.5 -> 360
      expect(r.width % 1, 0);
      expect(r.left % 1, 0);
      expect((r.width / r.height - 9 / 16).abs(), lessThan(1 / 500));
      expect(wholeImageRect(const Size(1000, 500)).contains(r.topLeft), isTrue);
      expect(r.right, lessThanOrEqualTo(1000));
    });

    test('a rect hanging out of the image is clamped first', () {
      final r = fitRectToRatio(
        const Rect.fromLTWH(-50, -50, 2000, 2000),
        1,
        _bounds,
      );
      expect(r, const Rect.fromLTWH(100, 0, 800, 800));
    });
  });

  group('moveCropRect', () {
    test('keeps the size and stays inside the image', () {
      expect(
        moveCropRect(
          const Rect.fromLTWH(100, 100, 200, 100),
          const Offset(-500, 900),
          _bounds,
        ),
        const Rect.fromLTWH(0, 700, 200, 100),
      );
    });
  });

  group('resizeCropRect', () {
    const rect = Rect.fromLTWH(100, 100, 300, 200);

    test('free: the opposite corner stays, snapped to whole pixels', () {
      expect(
        resizeCropRect(
          rect: rect,
          handle: CropHandle.bottomRight,
          pointer: const Offset(650.4, 420),
          bounds: _bounds,
        ),
        const Rect.fromLTRB(100, 100, 650, 420),
      );
    });

    test('free: cannot cross the opposite edge nor leave the image', () {
      expect(
        resizeCropRect(
          rect: rect,
          handle: CropHandle.topLeft,
          pointer: const Offset(500, 500),
          bounds: _bounds,
        ),
        const Rect.fromLTRB(392, 292, 400, 300),
      );
      expect(
        resizeCropRect(
          rect: rect,
          handle: CropHandle.right,
          pointer: const Offset(5000, 0),
          bounds: _bounds,
        ).right,
        1000,
      );
    });

    test('an edge handle moves only its edge', () {
      final r = resizeCropRect(
        rect: rect,
        handle: CropHandle.top,
        pointer: const Offset(999, 40),
        bounds: _bounds,
      );
      expect(r, const Rect.fromLTRB(100, 40, 400, 300));
    });

    test('ratio lock (preset or Shift): corner keeps the ratio', () {
      final r = resizeCropRect(
        rect: const Rect.fromLTWH(100, 100, 400, 300),
        handle: CropHandle.bottomRight,
        pointer: const Offset(700, 400),
        bounds: _bounds,
        ratio: 400 / 300, // Shift: the rect's own ratio
      );
      expect(r, const Rect.fromLTWH(100, 100, 600, 450));
    });

    test('ratio lock: top-left corner anchors the bottom-right one', () {
      final r = resizeCropRect(
        rect: const Rect.fromLTWH(200, 200, 200, 200),
        handle: CropHandle.topLeft,
        pointer: const Offset(100, 150),
        bounds: _bounds,
        ratio: 1,
      );
      expect(r, const Rect.fromLTWH(100, 100, 300, 300));
    });

    test('ratio lock: never outside the image', () {
      final r = resizeCropRect(
        rect: const Rect.fromLTWH(100, 100, 200, 200),
        handle: CropHandle.bottomRight,
        pointer: const Offset(5000, 5000),
        bounds: _bounds,
        ratio: 1,
      );
      expect(r, const Rect.fromLTWH(100, 100, 700, 700));
    });

    test('ratio lock: an edge handle re-centers the other side', () {
      final r = resizeCropRect(
        rect: const Rect.fromLTWH(100, 100, 200, 200),
        handle: CropHandle.right,
        pointer: const Offset(500, 0),
        bounds: _bounds,
        ratio: 1,
      );
      expect(r, const Rect.fromLTWH(100, 0, 400, 400));
    });
  });

  group('cropRectFromDrag', () {
    test('any drag direction, clamped to the image', () {
      expect(
        cropRectFromDrag(
          const Offset(300, 300),
          const Offset(100, 50),
          _bounds,
        ),
        const Rect.fromLTWH(100, 50, 200, 250),
      );
      expect(
        cropRectFromDrag(
          const Offset(900, 700),
          const Offset(2000, 2000),
          _bounds,
        ),
        const Rect.fromLTWH(900, 700, 100, 100),
      );
    });

    test('with a ratio', () {
      expect(
        cropRectFromDrag(
          const Offset(300, 300),
          const Offset(100, 50),
          _bounds,
          ratio: 1,
        ),
        const Rect.fromLTWH(50, 50, 250, 250),
      );
    });
  });

  group('hitCropHandle', () {
    const r = Rect.fromLTWH(0, 0, 100, 100);

    test('finds the nearest handle within the tolerance', () {
      expect(hitCropHandle(r, const Offset(98, 2), 5), CropHandle.topRight);
      expect(hitCropHandle(r, const Offset(50, 1), 5), CropHandle.top);
      expect(hitCropHandle(r, const Offset(50, 50), 5), isNull);
    });
  });

  group('annotationsAfterCrop', () {
    const crop = Rect.fromLTWH(100, 100, 200, 200);

    test('removes the ones entirely outside, keeps the crossing ones', () {
      final outside = _rect('out', const Offset(0, 0), const Offset(50, 50));
      final crossing = _rect(
        'cross',
        const Offset(50, 150),
        const Offset(150, 250),
      );
      final inside = _rect(
        'in',
        const Offset(150, 150),
        const Offset(250, 250),
      );
      final result = annotationsAfterCrop([outside, crossing, inside], crop);
      expect(result.map((a) => a.id), ['cross', 'in']);
      final moved = result.first as ShapeAnnotation;
      expect(moved.start, const Offset(-50, 50)); // still editable, clipped
      expect(moved.end, const Offset(50, 150));
      expect((result.last as ShapeAnnotation).start, const Offset(50, 50));
    });

    test('uses the drawn (rotated) bounds', () {
      // Unrotated it sits above the crop; turned 90 degrees it reaches in.
      final bar = _rect('bar', const Offset(50, 20), const Offset(350, 40));
      expect(annotationsAfterCrop([bar], crop), isEmpty);
      final turned = _rect(
        'turned',
        const Offset(50, 20),
        const Offset(350, 40),
        rotation: math.pi / 2,
      );
      expect(annotationsAfterCrop([turned], crop).map((a) => a.id), ['turned']);
    });

    test('touching the border from outside is not inside', () {
      final touching = _rect('t', const Offset(0, 100), const Offset(98, 200));
      // Stroke inflates the bounds by 1.5: right = 99.5 < 100.
      expect(annotationsAfterCrop([touching], crop), isEmpty);
    });
  });

  group('Annotation.shiftedWithImage', () {
    test('default is translated()', () {
      final r = _rect('r', const Offset(10, 10), const Offset(20, 20));
      final moved = r.shiftedWithImage(const Offset(-5, 5)) as ShapeAnnotation;
      expect(moved.start, const Offset(5, 15));
    });

    test('a stamp keeps its offset (the image moved too)', () {
      const stamp = StampAnnotation(
        id: 's',
        style: _style,
        points: [Offset(150, 150), Offset(160, 160)],
        offset: Offset(10, -5),
      );
      final shifted =
          stamp.shiftedWithImage(const Offset(-100, -100)) as StampAnnotation;
      expect(shifted.points, const [Offset(50, 50), Offset(60, 60)]);
      expect(shifted.offset, const Offset(10, -5));
      // A user move, by contrast, compensates the offset.
      final dragged =
          stamp.translated(const Offset(-100, -100)) as StampAnnotation;
      expect(dragged.offset, const Offset(110, 95));
    });
  });

  group('CropRatio', () {
    test('values and the original ratio', () {
      const image = Size(1600, 900);
      expect(CropRatio.free.value(image), isNull);
      expect(CropRatio.square.value(image), 1);
      expect(CropRatio.r4x3.value(image), closeTo(4 / 3, 1e-12));
      expect(CropRatio.r9x16.value(image), closeTo(9 / 16, 1e-12));
      expect(CropRatio.original.value(image), closeTo(16 / 9, 1e-12));
    });

    test('debug tokens round-trip', () {
      for (final ratio in CropRatio.values) {
        expect(CropRatioValue.fromToken(ratio.token), ratio);
      }
      expect(CropRatioValue.fromToken('5:4'), isNull);
    });
  });

  group('EditHistory (image + annotations records restore in order)', () {
    test('undo and redo walk the states back and forth', () {
      final history = EditHistory<int>();
      var current = 0;
      history.push(current); // 0 -> 1
      current = 1;
      history.push(current); // 1 -> 2
      current = 2;
      current = history.undo(current)!;
      expect(current, 1);
      current = history.undo(current)!;
      expect(current, 0);
      expect(history.undo(current), isNull);
      current = history.redo(current)!;
      expect(current, 1);
      current = history.redo(current)!;
      expect(current, 2);
      expect(history.redo(current), isNull);
    });

    test('a new change drops the redo stack and reports it', () {
      final history = EditHistory<String>();
      history.push('a');
      history.push('b');
      var current = 'c';
      current = history.undo(current)!; // b, redo: [c]
      expect(history.canRedo, isTrue);
      final dropped = history.push(current); // new change from b
      expect(dropped, ['c']);
      expect(history.canRedo, isFalse);
    });

    test('past maxEntries the oldest entry is dropped and reported', () {
      final history = EditHistory<int>(maxEntries: 2);
      expect(history.push(1), isEmpty);
      expect(history.push(2), isEmpty);
      expect(history.push(3), [1]);
      expect(history.entries, [2, 3]);
    });
  });
}
