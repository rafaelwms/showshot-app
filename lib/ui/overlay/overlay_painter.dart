import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/window_info.dart';

/// Paints everything on top of the frozen screenshot: dimming, window
/// highlight, selection rectangle, handles, crosshair and the size label.
class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.selection,
    required this.hoverWindow,
    required this.cursor,
    required this.pixelRatio,
    required this.dragging,
    required this.showHandles,
    this.showCrosshair = true,
  });

  final Rect? selection;
  final WindowInfo? hoverWindow;
  final Offset? cursor;
  final double pixelRatio;
  final bool dragging;
  final bool showHandles;

  /// False while picking a window: the whole window is already highlighted,
  /// so the crosshair lines would just be visual noise.
  final bool showCrosshair;

  static const handleRadius = 5.0;

  /// Handle positions for [rect]: TL, T, TR, R, BR, B, BL, L.
  static List<Offset> handlesFor(Rect rect) => [
    rect.topLeft,
    rect.topCenter,
    rect.topRight,
    rect.centerRight,
    rect.bottomRight,
    rect.bottomCenter,
    rect.bottomLeft,
    rect.centerLeft,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final sel = selection;
    // In window-pick mode the hovered window acts as a live "spotlight"
    // preview: it stays undimmed, exactly like a committed selection would,
    // so hovering different windows clearly reads as choosing between them.
    final spotlight = sel ?? hoverWindow?.bounds;

    // Dim everything except the selection (or the hovered window).
    final dim = Paint()..color = const Color(0x8A000000);
    if (spotlight == null) {
      canvas.drawRect(full, dim);
    } else {
      final path = Path()
        ..addRect(full)
        ..addRect(spotlight)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(path, dim);
    }

    // Window highlight border/label (only while nothing is selected).
    if (sel == null && hoverWindow != null) {
      _paintWindowHighlight(canvas, hoverWindow!);
    }

    // Crosshair follows the cursor while choosing an area.
    if (showCrosshair && cursor != null && (sel == null || dragging)) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(cursor!.dx + 0.5, 0),
        Offset(cursor!.dx + 0.5, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, cursor!.dy + 0.5),
        Offset(size.width, cursor!.dy + 0.5),
        paint,
      );
    }

    if (sel != null) {
      _paintSelection(canvas, size, sel);
    }
  }

  void _paintWindowHighlight(Canvas canvas, WindowInfo window) {
    final rect = window.bounds;
    // The dim layer is already punched out for this window above, so it
    // just needs an outline — no extra fill on top.
    canvas.drawRect(
      rect.deflate(1.5),
      Paint()
        ..color = AppColors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final label = window.label;
    if (label.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, rect.width - 24));
    final chip = Rect.fromLTWH(
      rect.left + 8,
      rect.top + 8,
      painter.width + 20,
      painter.height + 12,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(8)),
      Paint()..color = const Color(0xE6161A2B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(8)),
      Paint()
        ..color = AppColors.cyan.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke,
    );
    painter.paint(canvas, chip.topLeft + const Offset(10, 6));
  }

  void _paintSelection(Canvas canvas, Size size, Rect sel) {
    // Accent glow + crisp border.
    canvas.drawRect(
      sel.inflate(1),
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRect(
      Rect.fromLTRB(
        sel.left - 0.5,
        sel.top - 0.5,
        sel.right + 0.5,
        sel.bottom + 0.5,
      ),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Rule-of-thirds guides while dragging.
    if (dragging && sel.width > 80 && sel.height > 80) {
      final guide = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        final x = sel.left + sel.width * i / 3;
        final y = sel.top + sel.height * i / 3;
        canvas.drawLine(Offset(x, sel.top), Offset(x, sel.bottom), guide);
        canvas.drawLine(Offset(sel.left, y), Offset(sel.right, y), guide);
      }
    }

    if (showHandles) {
      final fill = Paint()..color = Colors.white;
      final stroke = Paint()
        ..color = AppColors.violet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final handle in handlesFor(sel)) {
        canvas.drawCircle(handle, handleRadius, fill);
        canvas.drawCircle(handle, handleRadius, stroke);
      }
    }

    // Size label in device pixels.
    final w = (sel.width * pixelRatio).round();
    final h = (sel.height * pixelRatio).round();
    final painter = TextPainter(
      text: TextSpan(
        text: '$w × $h',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = 6.0;
    final labelSize = Size(
      painter.width + pad * 2 + 2,
      painter.height + pad * 2 - 2,
    );
    var origin = Offset(sel.left, sel.top - labelSize.height - 8);
    if (origin.dy < 4) origin = Offset(sel.left, sel.bottom + 8);
    if (origin.dy + labelSize.height > size.height - 4) {
      origin = Offset(sel.left + 8, sel.top + 8);
    }
    origin = Offset(
      origin.dx.clamp(4, math.max(4, size.width - labelSize.width - 4)),
      origin.dy,
    );
    final rect = origin & labelSize;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()..color = const Color(0xE6161A2B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke,
    );
    painter.paint(canvas, origin + Offset(pad + 1, pad - 1));
  }

  @override
  bool shouldRepaint(OverlayPainter old) =>
      old.selection != selection ||
      old.hoverWindow != hoverWindow ||
      old.cursor != cursor ||
      old.dragging != dragging ||
      old.showHandles != showHandles ||
      old.showCrosshair != showCrosshair;
}

/// Zoomed view of the pixels around the cursor.
class MagnifierPainter extends CustomPainter {
  MagnifierPainter({
    required this.image,
    required this.cursor,
    required this.pixelRatio,
    this.zoom = 6,
  });

  final ui.Image image;
  final Offset cursor;
  final double pixelRatio;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final clip = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(clip);

    // Source region in device pixels around the cursor.
    final srcHalf = radius / zoom * pixelRatio;
    final cx = cursor.dx * pixelRatio;
    final cy = cursor.dy * pixelRatio;
    final src = Rect.fromLTRB(
      cx - srcHalf,
      cy - srcHalf,
      cx + srcHalf,
      cy + srcHalf,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );

    // Pixel grid.
    final cell = zoom / pixelRatio * pixelRatio; // one device pixel
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    final offsetX = (radius - (cx - cx.floorToDouble()) * cell) % cell;
    final offsetY = (radius - (cy - cy.floorToDouble()) * cell) % cell;
    if (cell >= 4) {
      for (var x = offsetX; x < size.width; x += cell) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
      for (var y = offsetY; y < size.height; y += cell) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }

    // Center crosshair.
    final cross = Paint()
      ..color = AppColors.cyan
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, radius), Offset(size.width, radius), cross);
    canvas.drawLine(Offset(radius, 0), Offset(radius, size.height), cross);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: cell, height: cell),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();

    // Ring.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      radius - 3,
      Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(MagnifierPainter old) =>
      old.cursor != cursor || old.image != image;
}
