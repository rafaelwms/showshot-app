import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/annotation.dart';
import '../../models/crop.dart';
import 'editor_controller.dart';

/// Paints the screenshot, the annotations and the selection chrome.
class EditorCanvasPainter extends CustomPainter {
  EditorCanvasPainter({
    required this.image,
    required this.annotations,
    required this.selected,
    required this.zoom,
    required this.repaint,
  }) : super(repaint: repaint);

  final ui.Image image;
  final List<Annotation> annotations;
  final Annotation? selected;
  final double zoom;
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // Annotations are clipped by the image: what lies past its edge (dragged
    // out, or left over by a crop) is not part of the picture, and Copy/Save
    // (ExportService.render) clip the same way.
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    );
    for (final annotation in annotations) {
      annotation.paint(canvas, image);
    }
    canvas.restore();
    final current = selected;
    if (current != null) _paintSelection(canvas, current);
  }

  void _paintSelection(Canvas canvas, Annotation annotation) {
    final inv = 1 / zoom;
    final outline = annotation.bounds.inflate(4 * inv);
    // The outline turns with the annotation; the handles are already in
    // image coordinates.
    canvas.save();
    canvas.translate(annotation.pivot.dx, annotation.pivot.dy);
    canvas.rotate(annotation.rotation);
    canvas.translate(-annotation.pivot.dx, -annotation.pivot.dy);
    canvas.drawRect(
      outline,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * inv,
    );
    canvas.drawRect(
      outline,
      Paint()
        ..color = AppColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * inv,
    );
    canvas.restore();
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = AppColors.violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * inv;
    for (final handle in annotation.handles) {
      canvas.drawCircle(handle, 5.5 * inv, fill);
      canvas.drawCircle(handle, 5.5 * inv, stroke);
    }
    if (annotation.rotatable) {
      _paintRotationHandle(canvas, annotation, inv, fill, stroke);
    }
  }

  /// A stem from the outline to a round handle with a small "turn" arrow.
  void _paintRotationHandle(
    Canvas canvas,
    Annotation annotation,
    double inv,
    Paint fill,
    Paint stroke,
  ) {
    final handle = annotation.rotationHandle(
      rotationHandleScreenDistance * inv,
    );
    final base = annotation.rotationHandleBase(4 * inv);
    canvas.drawLine(
      base,
      handle,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..strokeWidth = 3 * inv,
    );
    canvas.drawLine(
      base,
      handle,
      Paint()
        ..color = AppColors.cyan
        ..strokeWidth = 1.2 * inv,
    );
    const radius = 7.0;
    canvas.drawCircle(handle, radius * inv, fill);
    canvas.drawCircle(handle, radius * inv, stroke);
    // Open arc with an arrow head at its end.
    const start = -math.pi * 0.35;
    const sweep = math.pi * 1.55;
    final arc = Rect.fromCircle(center: handle, radius: 3.2 * inv);
    canvas.drawArc(
      arc,
      start,
      sweep,
      false,
      Paint()
        ..color = AppColors.violet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * inv
        ..strokeCap = StrokeCap.round,
    );
    const endAngle = start + sweep;
    final tip =
        handle + Offset(math.cos(endAngle), math.sin(endAngle)) * 3.2 * inv;
    // Tangent direction of a clockwise arc at its end.
    final tangent = Offset(-math.sin(endAngle), math.cos(endAngle));
    final normal = Offset(-tangent.dy, tangent.dx);
    canvas.drawPath(
      Path()
        ..moveTo(
          tip.dx + tangent.dx * 2.2 * inv,
          tip.dy + tangent.dy * 2.2 * inv,
        )
        ..lineTo(tip.dx + normal.dx * 1.9 * inv, tip.dy + normal.dy * 1.9 * inv)
        ..lineTo(tip.dx - normal.dx * 1.9 * inv, tip.dy - normal.dy * 1.9 * inv)
        ..close(),
      Paint()..color = AppColors.violet,
    );
  }

  @override
  bool shouldRepaint(EditorCanvasPainter old) => true;
}

/// Clone stamp chrome, painted above (and separately from) the annotations:
/// the brush outline at the pointer and the source crosshair. It only listens
/// to the pointer/zoom/controller, so moving the mouse never re-rasterizes
/// the stamps underneath.
class StampOverlayPainter extends CustomPainter {
  StampOverlayPainter({required this.controller})
    : super(
        repaint: Listenable.merge([
          controller,
          controller.hover,
          controller.transformation,
        ]),
      );

  final EditorController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.tool != ToolType.stamp) return;
    final inv = 1 / math.max(controller.zoom, 0.01);
    final pointer = controller.hover.value;
    if (pointer != null) {
      // Brush outline: the nominal diameter, dark + light so it reads on any
      // content.
      // Bézier path, not drawCircle: see bezierOval (Linux Impeller GLES).
      final ring = bezierCircle(pointer, controller.style.brushSize / 2);
      canvas.drawPath(
        ring,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * inv,
      );
      canvas.drawPath(
        ring,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * inv,
      );
    }
    final marker = controller.stampSource.markerFor(pointer);
    if (marker != null) _paintCrosshair(canvas, marker, inv);
  }

  /// A small target: ring plus a cross, outlined for contrast.
  void _paintCrosshair(Canvas canvas, Offset c, double inv) {
    final r = 8 * inv;
    final arm = 13 * inv;
    void draw(Paint paint) {
      canvas.drawPath(bezierCircle(c, r), paint);
      canvas.drawLine(c - Offset(arm, 0), c + Offset(arm, 0), paint);
      canvas.drawLine(c - Offset(0, arm), c + Offset(0, arm), paint);
    }

    draw(
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * inv,
    );
    draw(
      Paint()
        ..color = AppColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * inv,
    );
  }

  @override
  bool shouldRepaint(StampOverlayPainter old) => old.controller != controller;
}

/// Crop tool chrome, painted above the annotations: the image dimmed outside
/// the crop rectangle, a thin border, rule-of-thirds guides and the eight
/// handles (same look as the capture overlay). Listens to the controller (the
/// rect changes through it) and the zoom, so handles keep their screen size.
class CropOverlayPainter extends CustomPainter {
  CropOverlayPainter({required this.controller})
    : super(repaint: Listenable.merge([controller, controller.transformation]));

  final EditorController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = controller.cropRect;
    if (controller.tool != ToolType.crop || rect == null) return;
    final inv = 1 / math.max(controller.zoom, 0.01);
    final full = Offset.zero & size;

    // Dim everything outside the crop rectangle.
    canvas.drawPath(
      Path()
        ..addRect(full)
        ..addRect(rect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = const Color(0x99000000),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * inv,
    );

    // Rule-of-thirds guides.
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1 * inv;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), guide);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), guide);
    }

    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = AppColors.violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * inv;
    for (final handle in cropHandlePoints(rect)) {
      canvas.drawCircle(handle, 5.5 * inv, fill);
      canvas.drawCircle(handle, 5.5 * inv, stroke);
    }
  }

  @override
  bool shouldRepaint(CropOverlayPainter old) => old.controller != controller;
}
