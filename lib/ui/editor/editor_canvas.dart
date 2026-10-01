import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/annotation.dart';

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
    for (final annotation in annotations) {
      annotation.paint(canvas, image);
    }
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
    _paintRotationHandle(canvas, annotation, inv, fill, stroke);
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
