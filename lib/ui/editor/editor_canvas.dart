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
    final bounds = annotation.bounds.inflate(4 * inv);
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * inv,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..color = AppColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * inv,
    );
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = AppColors.violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * inv;
    for (final handle in annotation.handles) {
      canvas.drawCircle(handle, 5.5 * inv, fill);
      canvas.drawCircle(handle, 5.5 * inv, stroke);
    }
  }

  @override
  bool shouldRepaint(EditorCanvasPainter old) => true;
}
