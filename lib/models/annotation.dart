import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Editor tools. Everything except [select] and [hand] creates annotations.
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

/// Base class for everything drawn on top of the screenshot.
///
/// All coordinates are in *image pixel* space.
abstract class Annotation {
  const Annotation({required this.id, required this.style});

  final String id;
  final AnnotationStyle style;

  /// Axis-aligned bounds used for selection outlines and hit testing.
  Rect get bounds;

  /// Draggable handles (image coordinates). Empty for move-only annotations.
  List<Offset> get handles => const [];

  bool hitTest(Offset point, double tolerance);

  Annotation translated(Offset delta);

  Annotation withStyle(AnnotationStyle style);

  /// Moves handle [index] to [position]. Default: no-op.
  Annotation withHandle(int index, Offset position) => this;

  /// True when the annotation has no visible extent (e.g. a zero-length line).
  bool get isDegenerate => false;

  void paint(Canvas canvas, ui.Image? source);

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
  });

  final ShapeKind kind;
  final Offset start;
  final Offset end;

  Rect get rect => Rect.fromPoints(start, end);

  bool get isLinear => kind == ShapeKind.arrow || kind == ShapeKind.line;

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
  List<Offset> get handles => isLinear
      ? [start, end]
      : [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];

  double get _headLength => math.max(14.0, style.strokeWidth * 3.5);

  @override
  bool hitTest(Offset point, double tolerance) {
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
  Annotation withStyle(AnnotationStyle style) =>
      ShapeAnnotation(id: id, style: style, kind: kind, start: start, end: end);

  @override
  Annotation withHandle(int index, Offset position) {
    if (isLinear) {
      return index == 0 ? copyWith(start: position) : copyWith(end: position);
    }
    // Corner handles: keep the opposite corner anchored.
    final r = rect;
    final anchor = switch (index) {
      0 => r.bottomRight,
      1 => r.bottomLeft,
      2 => r.topLeft,
      _ => r.topRight,
    };
    return copyWith(start: anchor, end: position);
  }

  ShapeAnnotation copyWith({Offset? start, Offset? end}) => ShapeAnnotation(
    id: id,
    style: style,
    kind: kind,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  @override
  void paint(Canvas canvas, ui.Image? source) {
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
    canvas.save();
    canvas.clipRect(r);
    canvas.saveLayer(
      r,
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
  });

  final List<Offset> points;
  final bool marker;

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

  @override
  bool hitTest(Offset point, double tolerance) {
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
  );

  @override
  Annotation withStyle(AnnotationStyle style) =>
      StrokeAnnotation(id: id, style: style, points: points, marker: marker);

  StrokeAnnotation appended(Offset point) => StrokeAnnotation(
    id: id,
    style: style,
    points: [...points, point],
    marker: marker,
  );

  @override
  void paint(Canvas canvas, ui.Image? source) {
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

/// A block of text anchored at its top-left corner.
class TextAnnotation extends Annotation {
  TextAnnotation({
    required super.id,
    required super.style,
    required this.position,
    required this.text,
  });

  final Offset position;
  final String text;

  static const _padding = 6.0;

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

  @override
  bool hitTest(Offset point, double tolerance) =>
      bounds.inflate(tolerance).contains(point);

  @override
  Annotation translated(Offset delta) => copyWith(position: position + delta);

  @override
  Annotation withStyle(AnnotationStyle style) =>
      TextAnnotation(id: id, style: style, position: position, text: text);

  TextAnnotation copyWith({Offset? position, String? text}) => TextAnnotation(
    id: id,
    style: style,
    position: position ?? this.position,
    text: text ?? this.text,
  );

  @override
  void paint(Canvas canvas, ui.Image? source) {
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
  });

  final Offset center;
  final int number;

  double get radius => 14 + style.strokeWidth * 1.6;

  @override
  Rect get bounds => Rect.fromCircle(center: center, radius: radius + 2);

  @override
  bool hitTest(Offset point, double tolerance) =>
      (point - center).distance <= radius + tolerance;

  @override
  Annotation translated(Offset delta) => NumberAnnotation(
    id: id,
    style: style,
    center: center + delta,
    number: number,
  );

  @override
  Annotation withStyle(AnnotationStyle style) =>
      NumberAnnotation(id: id, style: style, center: center, number: number);

  @override
  void paint(Canvas canvas, ui.Image? source) {
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
