import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Editor tools. Everything except [select], [hand] and [ocr] creates
/// annotations — [ocr] draws a selection rectangle like [rect], but on
/// release it recognizes text in that region instead of leaving a shape
/// behind.
enum ToolType {
  select,
  hand,
  arrow,
  line,
  rect,
  ellipse,
  pen,
  marker,
  text,
  number,
  blur,
  ocr,
}

/// Visual properties shared by all annotations.
class AnnotationStyle {
  const AnnotationStyle({
    required this.color,
    required this.strokeWidth,
    this.opacity = 1.0,
    this.filled = false,
    this.fontSize = 24,
  });

  final Color color;
  final double strokeWidth;
  final double opacity;
  final bool filled;
  final double fontSize;

  Color get effectiveColor => color.withValues(alpha: color.a * opacity);

  AnnotationStyle copyWith({
    Color? color,
    double? strokeWidth,
    double? opacity,
    bool? filled,
    double? fontSize,
  }) {
    return AnnotationStyle(
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

int _nextId = 0;
String newAnnotationId() => 'a${_nextId++}';

/// Distance (screen pixels) from an annotation's top edge to its rotation
/// handle. The editor divides by the zoom to get image pixels.
const rotationHandleScreenDistance = 28.0;

/// Rotates [point] clockwise by [angle] radians around [pivot].
Offset rotatePoint(Offset point, Offset pivot, double angle) {
  if (angle == 0) return point;
  final c = math.cos(angle);
  final s = math.sin(angle);
  final d = point - pivot;
  return pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
}

/// Wraps [angle] into (-π, π] so repeated rotations don't grow without bound.
double wrapAngle(double angle) {
  const turn = 2 * math.pi;
  var a = angle % turn;
  if (a > math.pi) a -= turn;
  if (a <= -math.pi) a += turn;
  return a;
}

/// Base class for everything drawn on top of the screenshot.
///
/// All coordinates are in *image pixel* space. Each annotation's geometry
/// (its [bounds] and its own points) lives in a local, un-rotated frame;
/// [rotation] then turns that frame around [pivot] when painting, hit
/// testing and drawing selection chrome — so rotating never rewrites the
/// geometry, and undo/redo stay simple immutable snapshots.
abstract class Annotation {
  const Annotation({required this.id, required this.style});

  final String id;
  final AnnotationStyle style;

  /// Clockwise rotation in radians around [pivot]. Arrows and lines never use
  /// it: rotating those turns their two endpoints instead (see
  /// [ShapeAnnotation.rotatedBy]), which keeps their endpoint handles simple.
  double get rotation => 0;

  /// Center of the un-rotated [bounds]. It doesn't move when [rotation]
  /// changes, so successive rotations never drift.
  Offset get pivot => bounds.center;

  /// Axis-aligned bounds in the local (un-rotated) frame, used for the
  /// selection outline.
  Rect get bounds;

  /// Resize handles in image coordinates, already rotated. Empty for
  /// move-only annotations.
  List<Offset> get handles => const [];

  /// The handle that rotates the annotation: [distance] past the top edge of
  /// [bounds] (arrows and lines: past the midpoint, sideways).
  Offset rotationHandle(double distance) => rotatePoint(
    Offset(bounds.center.dx, bounds.top - distance),
    pivot,
    rotation,
  );

  /// Where the stem to [rotationHandle] leaves the selection outline, which
  /// sits [outlineInflate] outside [bounds].
  Offset rotationHandleBase(double outlineInflate) => rotatePoint(
    Offset(bounds.center.dx, bounds.top - outlineInflate),
    pivot,
    rotation,
  );

  /// [point] is in image coordinates (un-rotated by [rotation] first).
  bool hitTest(Offset point, double tolerance) =>
      hitTestLocal(rotatePoint(point, pivot, -rotation), tolerance);

  /// Hit test in the local, un-rotated frame.
  bool hitTestLocal(Offset point, double tolerance);

  Annotation translated(Offset delta);

  Annotation withStyle(AnnotationStyle style);

  /// Moves handle [index] to [position] (image coordinates). Default: no-op.
  Annotation withHandle(int index, Offset position) => this;

  /// A copy turned clockwise by [delta] radians around [pivot].
  Annotation rotatedBy(double delta);

  /// True when the annotation has no visible extent (e.g. a zero-length line).
  bool get isDegenerate => false;

  void paint(Canvas canvas, ui.Image? source) {
    if (rotation == 0) {
      paintLocal(canvas, source);
      return;
    }
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(rotation);
    canvas.translate(-pivot.dx, -pivot.dy);
    paintLocal(canvas, source);
    canvas.restore();
  }

  /// Paints in the local, un-rotated frame ([paint] applies the rotation).
  void paintLocal(Canvas canvas, ui.Image? source);

  Paint strokePaint() => Paint()
    ..color = style.effectiveColor
    ..strokeWidth = style.strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  Paint fillPaint() => Paint()
    ..color = style.effectiveColor
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
}

enum ShapeKind { arrow, line, rect, ellipse, blur }

/// Two-point shapes: arrows, lines, rectangles, ellipses and blur regions.
class ShapeAnnotation extends Annotation {
  const ShapeAnnotation({
    required super.id,
    required super.style,
    required this.kind,
    required this.start,
    required this.end,
    this.rotation = 0,
  });

  final ShapeKind kind;
  final Offset start;
  final Offset end;

  /// Always 0 for arrows and lines (see [Annotation.rotation]).
  @override
  final double rotation;

  Rect get rect => Rect.fromPoints(start, end);

  bool get isLinear => kind == ShapeKind.arrow || kind == ShapeKind.line;

  Offset get _midpoint => (start + end) / 2;

  @override
  bool get isDegenerate =>
      isLinear ? (end - start).distance < 2 : rect.width < 2 || rect.height < 2;

  @override
  Rect get bounds {
    if (isLinear) {
      final head = kind == ShapeKind.arrow ? _headLength : 0.0;
      return rect.inflate(math.max(style.strokeWidth, head) / 2 + 2);
    }
    return rect.inflate(style.strokeWidth / 2);
  }

  @override
  List<Offset> get handles {
    if (isLinear) return [start, end];
    final r = rect;
    return [
      for (final corner in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft])
        rotatePoint(corner, pivot, rotation),
    ];
  }

  /// Unit vector perpendicular to a line/arrow (pointing "up" for a segment
  /// drawn left to right).
  Offset get _sideways {
    final v = end - start;
    final length = v.distance;
    if (length < 1e-6) return const Offset(0, -1);
    return Offset(v.dy / length, -v.dx / length);
  }

  @override
  Offset rotationHandle(double distance) => isLinear
      ? _midpoint + _sideways * (distance + style.strokeWidth / 2)
      : super.rotationHandle(distance);

  @override
  Offset rotationHandleBase(double outlineInflate) =>
      isLinear ? _midpoint : super.rotationHandleBase(outlineInflate);

  double get _headLength => math.max(14.0, style.strokeWidth * 3.5);

  @override
  bool hitTestLocal(Offset point, double tolerance) {
    final tol = tolerance + style.strokeWidth / 2;
    switch (kind) {
      case ShapeKind.arrow:
      case ShapeKind.line:
        return _distanceToSegment(point, start, end) <= tol;
      case ShapeKind.blur:
        return rect.contains(point);
      case ShapeKind.rect:
        if (style.filled) return rect.inflate(tol).contains(point);
        return rect.inflate(tol).contains(point) &&
            !rect.deflate(tol).contains(point);
      case ShapeKind.ellipse:
        final center = rect.center;
        final a = rect.width / 2;
        final b = rect.height / 2;
        if (a <= 0 || b <= 0) return false;
        final dx = point.dx - center.dx;
        final dy = point.dy - center.dy;
        double norm(double ra, double rb) => ra <= 0 || rb <= 0
            ? double.infinity
            : (dx * dx) / (ra * ra) + (dy * dy) / (rb * rb);
        final outer = norm(a + tol, b + tol);
        if (style.filled) return outer <= 1;
        final inner = norm(a - tol, b - tol);
        return outer <= 1 && inner >= 1;
    }
  }

  @override
  Annotation translated(Offset delta) =>
      copyWith(start: start + delta, end: end + delta);

  @override
  Annotation withStyle(AnnotationStyle style) => copyWith(style: style);

  @override
  Annotation withHandle(int index, Offset position) {
    if (isLinear) {
      return index == 0 ? copyWith(start: position) : copyWith(end: position);
    }
    // Corner handles: the opposite corner stays put *on screen* and the box
    // keeps its rotation. `diagonal` is the anchor→pointer vector in the
    // box's own (un-rotated) axes; with no rotation this is exactly
    // "start = anchor, end = position".
    final r = rect;
    final anchorLocal = switch (index) {
      0 => r.bottomRight,
      1 => r.bottomLeft,
      2 => r.topLeft,
      _ => r.topRight,
    };
    final anchor = rotatePoint(anchorLocal, pivot, rotation);
    final center = (anchor + position) / 2;
    final diagonal = rotatePoint(position, anchor, -rotation) - anchor;
    return copyWith(start: center - diagonal / 2, end: center + diagonal / 2);
  }

  @override
  Annotation rotatedBy(double delta) {
    if (!isLinear) return copyWith(rotation: wrapAngle(rotation + delta));
    final mid = _midpoint;
    return copyWith(
      start: rotatePoint(start, mid, delta),
      end: rotatePoint(end, mid, delta),
    );
  }

  ShapeAnnotation copyWith({
    AnnotationStyle? style,
    Offset? start,
    Offset? end,
    double? rotation,
  }) => ShapeAnnotation(
    id: id,
    style: style ?? this.style,
    kind: kind,
    start: start ?? this.start,
    end: end ?? this.end,
    rotation: rotation ?? this.rotation,
  );

  @override
  void paint(Canvas canvas, ui.Image? source) {
    // A blur samples the *un-rotated* screenshot through a rotated window,
    // so it can't use the base class's rotate-the-canvas approach.
    if (kind == ShapeKind.blur) {
      _paintBlur(canvas, source);
      return;
    }
    super.paint(canvas, source);
  }

  @override
  void paintLocal(Canvas canvas, ui.Image? source) {
    switch (kind) {
      case ShapeKind.line:
        canvas.drawLine(start, end, strokePaint());
      case ShapeKind.arrow:
        _paintArrow(canvas);
      case ShapeKind.rect:
        final rrect = RRect.fromRectAndRadius(
          rect,
          Radius.circular(math.min(6, style.strokeWidth)),
        );
        if (style.filled) {
          canvas.drawRRect(rrect, fillPaint());
        } else {
          canvas.drawRRect(rrect, strokePaint());
        }
      case ShapeKind.ellipse:
        if (style.filled) {
          canvas.drawOval(rect, fillPaint());
        } else {
          canvas.drawOval(rect, strokePaint());
        }
      case ShapeKind.blur:
        _paintBlur(canvas, source);
    }
  }

  void _paintArrow(Canvas canvas) {
    final vector = end - start;
    final length = vector.distance;
    final paint = strokePaint();
    if (length < 1) {
      canvas.drawCircle(start, style.strokeWidth / 2, fillPaint());
      return;
    }
    final unit = vector / length;
    final normal = Offset(-unit.dy, unit.dx);
    final headLength = math.min(_headLength, length);
    final headWidth = headLength * 0.9;
    final base = end - unit * headLength;
    canvas.drawLine(start, base, paint);
    final head = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        base.dx + normal.dx * headWidth / 2,
        base.dy + normal.dy * headWidth / 2,
      )
      ..lineTo(
        base.dx - normal.dx * headWidth / 2,
        base.dy - normal.dy * headWidth / 2,
      )
      ..close();
    canvas.drawPath(head, fillPaint()..strokeJoin = StrokeJoin.round);
  }

  void _paintBlur(Canvas canvas, ui.Image? source) {
    final r = rect;
    if (source == null || r.isEmpty) return;
    final sigma = 6.0 + style.strokeWidth * 1.5;
    final Path? region;
    if (rotation == 0) {
      region = null;
      canvas.save();
      canvas.clipRect(r);
    } else {
      region = Path()
        ..addPolygon([
          for (final corner in [
            r.topLeft,
            r.topRight,
            r.bottomRight,
            r.bottomLeft,
          ])
            rotatePoint(corner, r.center, rotation),
        ], true);
      canvas.save();
      canvas.clipPath(region);
    }
    canvas.saveLayer(
      region?.getBounds() ?? r,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawImage(source, Offset.zero, Paint());
    canvas.restore();
    canvas.restore();
  }
}

/// Freehand strokes: pen (opaque, thin) and marker (wide, translucent).
class StrokeAnnotation extends Annotation {
  const StrokeAnnotation({
    required super.id,
    required super.style,
    required this.points,
    required this.marker,
    this.rotation = 0,
  });

  final List<Offset> points;
  final bool marker;

  @override
  final double rotation;

  double get _width => marker ? style.strokeWidth * 4 : style.strokeWidth;

  @override
  bool get isDegenerate => points.length < 2;

  @override
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(_width / 2);
  }

  /// Bounding box of the path itself (without the pen width).
  Rect get _pathRect {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Corners of the path box (top-left, top-right, bottom-right,
  /// bottom-left), rotated like the stroke. Dragging one scales the path.
  @override
  List<Offset> get handles {
    final r = _pathRect;
    return [
      for (final corner in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft])
        rotatePoint(corner, pivot, rotation),
    ];
  }

  Offset _localCorner(int index) {
    final r = _pathRect;
    return switch (index) {
      0 => r.topLeft,
      1 => r.topRight,
      2 => r.bottomRight,
      _ => r.bottomLeft,
    };
  }

  /// Scales the path so the corner opposite handle [index] stays fixed on
  /// screen and the dragged corner follows [position]. The pen width is left
  /// alone (like resizing a rectangle keeps its outline width), and the path
  /// may be flipped by dragging past the anchor. A path that is perfectly
  /// flat along one axis (a straight horizontal stroke) can only be scaled
  /// along the other.
  @override
  Annotation withHandle(int index, Offset position) {
    if (points.isEmpty) return this;
    final anchorLocal = _localCorner((index + 2) % 4);
    final anchor = rotatePoint(anchorLocal, pivot, rotation);
    final old = _localCorner(index) - anchorLocal;
    final now = rotatePoint(position, anchor, -rotation) - anchor;
    double factor(double from, double to) {
      if (from.abs() < 1e-6) return 1;
      final f = to / from;
      // Never collapse to nothing, but keep the sign so it can flip.
      return f.abs() < 0.02 ? (f < 0 ? -0.02 : 0.02) : f;
    }

    final sx = factor(old.dx, now.dx);
    final sy = factor(old.dy, now.dy);
    final scaled = [
      for (final p in points)
        anchorLocal +
            Offset((p.dx - anchorLocal.dx) * sx, (p.dy - anchorLocal.dy) * sy),
    ];
    final moved = StrokeAnnotation(
      id: id,
      style: style,
      points: scaled,
      marker: marker,
      rotation: rotation,
    );
    // The pivot moved with the new bounds: shift everything so the anchor
    // corner is exactly where it was on screen.
    final drift =
        anchor - rotatePoint(anchorLocal, moved.pivot, moved.rotation);
    return moved.translated(drift);
  }

  /// Where the pointer should count as being when Shift holds the stroke's
  /// proportions: the drag is projected onto the corner diagonal.
  Offset proportionalHandleTarget(int index, Offset position) {
    final anchorLocal = _localCorner((index + 2) % 4);
    final anchor = rotatePoint(anchorLocal, pivot, rotation);
    final old = _localCorner(index) - anchorLocal;
    final lengthSquared = old.dx * old.dx + old.dy * old.dy;
    if (lengthSquared < 1e-9) return position;
    final now = rotatePoint(position, anchor, -rotation) - anchor;
    final k = (now.dx * old.dx + now.dy * old.dy) / lengthSquared;
    return rotatePoint(anchor + old * k, anchor, rotation);
  }

  @override
  bool hitTestLocal(Offset point, double tolerance) {
    final tol = tolerance + _width / 2;
    if (points.length == 1) return (points.first - point).distance <= tol;
    for (var i = 0; i < points.length - 1; i++) {
      if (_distanceToSegment(point, points[i], points[i + 1]) <= tol) {
        return true;
      }
    }
    return false;
  }

  @override
  Annotation translated(Offset delta) => StrokeAnnotation(
    id: id,
    style: style,
    points: [for (final p in points) p + delta],
    marker: marker,
    rotation: rotation,
  );

  @override
  Annotation withStyle(AnnotationStyle style) => StrokeAnnotation(
    id: id,
    style: style,
    points: points,
    marker: marker,
    rotation: rotation,
  );

  @override
  Annotation rotatedBy(double delta) => StrokeAnnotation(
    id: id,
    style: style,
    points: points,
    marker: marker,
    rotation: wrapAngle(rotation + delta),
  );

  StrokeAnnotation appended(Offset point) => StrokeAnnotation(
    id: id,
    style: style,
    points: [...points, point],
    marker: marker,
    rotation: rotation,
  );

  @override
  void paintLocal(Canvas canvas, ui.Image? source) {
    if (points.isEmpty) return;
    final paint = strokePaint()..strokeWidth = _width;
    if (marker) {
      // Plain alpha blending stays visible on both light and dark content.
      paint
        ..color = style.color.withValues(alpha: 0.4 * style.opacity)
        ..strokeCap = StrokeCap.square;
    }
    if (points.length == 1) {
      canvas.drawCircle(points.first, _width / 2, Paint()..color = paint.color);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = (points[i] + points[i + 1]) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }
}

/// A block of text anchored at its top-left corner (before rotation).
class TextAnnotation extends Annotation {
  TextAnnotation({
    required super.id,
    required super.style,
    required this.position,
    required this.text,
    this.rotation = 0,
  });

  final Offset position;
  final String text;

  @override
  final double rotation;

  static const _padding = 6.0;

  /// Font size limits (image pixels) for resizing by the corner handles.
  static const minFontSize = 6.0;
  static const maxFontSize = 1200.0;

  TextPainter _painter() {
    final painter = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: textStyle(style)),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter;
  }

  static TextStyle textStyle(AnnotationStyle style) => TextStyle(
    color: style.effectiveColor,
    fontSize: style.fontSize,
    fontWeight: FontWeight.w600,
    height: 1.25,
    shadows: const [
      Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
    ],
  );

  @override
  bool get isDegenerate => text.trim().isEmpty;

  @override
  Rect get bounds {
    final painter = _painter();
    return Rect.fromLTWH(
      position.dx - _padding,
      position.dy - _padding,
      painter.width + _padding * 2,
      painter.height + _padding * 2,
    );
  }

  /// Corner handles resize the text by scaling its font size.
  @override
  List<Offset> get handles {
    final b = bounds;
    return [
      for (final corner in [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft])
        rotatePoint(corner, pivot, rotation),
    ];
  }

  @override
  bool hitTestLocal(Offset point, double tolerance) =>
      bounds.inflate(tolerance).contains(point);

  @override
  Annotation translated(Offset delta) => copyWith(position: position + delta);

  @override
  Annotation withStyle(AnnotationStyle style) {
    final next = copyWith(style: style);
    if (rotation == 0 || style.fontSize == this.style.fontSize) return next;
    // Rotated text keeps its *center* when the size changes (from the
    // properties bar), rather than its unrotated top-left corner — which
    // would swing the whole block around the pivot.
    final size = next._painter();
    return next.copyWith(
      position: pivot - Offset(size.width / 2, size.height / 2),
    );
  }

  @override
  Annotation withHandle(int index, Offset position) {
    final painter = _painter();
    final w = painter.width;
    final h = painter.height;
    final b = bounds;
    final corners = [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
    final anchorLocal = corners[(index + 2) % 4];
    final draggedLocal = corners[index];
    final anchor = rotatePoint(anchorLocal, pivot, rotation);
    // Anchor→pointer vector in the text's own axes, and which way the
    // dragged corner points from the anchor along each of them.
    final v = rotatePoint(position, anchor, -rotation) - anchor;
    final sx = draggedLocal.dx >= anchorLocal.dx ? 1.0 : -1.0;
    final sy = draggedLocal.dy >= anchorLocal.dy ? 1.0 : -1.0;
    // The text box (without its padding) implied by the pointer; the scale
    // is its projection onto the current box's diagonal, so dragging along
    // the diagonal scales smoothly and sideways movement is mostly ignored.
    final e = Offset(sx * v.dx - 2 * _padding, sy * v.dy - 2 * _padding);
    final scale = (e.dx * w + e.dy * h) / (w * w + h * h);
    final fontSize = (style.fontSize * scale).clamp(minFontSize, maxFontSize);
    if (!fontSize.isFinite) return this;
    final resized = copyWith(style: style.copyWith(fontSize: fontSize));
    final rp = resized._painter();
    // Keep the anchor corner fixed on screen: the anchor sits opposite the
    // dragged corner, so its offset from the new center is known.
    final half = Offset(rp.width / 2 + _padding, rp.height / 2 + _padding);
    final anchorOffset = Offset(-sx * half.dx, -sy * half.dy);
    final center = anchor - rotatePoint(anchorOffset, Offset.zero, rotation);
    return resized.copyWith(
      position: center - Offset(rp.width / 2, rp.height / 2),
    );
  }

  @override
  Annotation rotatedBy(double delta) =>
      copyWith(rotation: wrapAngle(rotation + delta));

  TextAnnotation copyWith({
    AnnotationStyle? style,
    Offset? position,
    String? text,
    double? rotation,
  }) => TextAnnotation(
    id: id,
    style: style ?? this.style,
    position: position ?? this.position,
    text: text ?? this.text,
    rotation: rotation ?? this.rotation,
  );

  @override
  void paintLocal(Canvas canvas, ui.Image? source) {
    if (text.isEmpty) return;
    _painter().paint(canvas, position);
  }
}

/// A numbered badge used to describe steps.
class NumberAnnotation extends Annotation {
  const NumberAnnotation({
    required super.id,
    required super.style,
    required this.center,
    required this.number,
    this.rotation = 0,
  });

  final Offset center;
  final int number;

  @override
  final double rotation;

  double get radius => 14 + style.strokeWidth * 1.6;

  @override
  Rect get bounds => Rect.fromCircle(center: center, radius: radius + 2);

  @override
  bool hitTestLocal(Offset point, double tolerance) =>
      (point - center).distance <= radius + tolerance;

  @override
  Annotation translated(Offset delta) => NumberAnnotation(
    id: id,
    style: style,
    center: center + delta,
    number: number,
    rotation: rotation,
  );

  @override
  Annotation withStyle(AnnotationStyle style) => NumberAnnotation(
    id: id,
    style: style,
    center: center,
    number: number,
    rotation: rotation,
  );

  @override
  Annotation rotatedBy(double delta) => NumberAnnotation(
    id: id,
    style: style,
    center: center,
    number: number,
    rotation: wrapAngle(rotation + delta),
  );

  @override
  void paintLocal(Canvas canvas, ui.Image? source) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(center, radius, fillPaint());
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * style.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * 0.1),
    );
    final luminance = style.color.computeLuminance();
    final painter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color:
              (luminance > 0.6
                      ? const Color(0xFF111111)
                      : const Color(0xFFFFFFFF))
                  .withValues(alpha: style.opacity),
          fontSize: radius * 1.15,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
  final projection = a + ab * t;
  return (p - projection).distance;
}
