import 'dart:math' as math;
import 'dart:ui';

import 'annotation.dart';

/// Aspect-ratio presets of the crop tool.
enum CropRatio { free, square, r4x3, r3x4, r16x9, r9x16, original }

extension CropRatioValue on CropRatio {
  /// Width / height, or null for [CropRatio.free]. [CropRatio.original] is the
  /// ratio of [image].
  double? value(Size image) => switch (this) {
    CropRatio.free => null,
    CropRatio.square => 1,
    CropRatio.r4x3 => 4 / 3,
    CropRatio.r3x4 => 3 / 4,
    CropRatio.r16x9 => 16 / 9,
    CropRatio.r9x16 => 9 / 16,
    CropRatio.original => image.height <= 0 ? null : image.width / image.height,
  };

  /// Short name used by the debug server (`cropratio 16:9`).
  String get token => switch (this) {
    CropRatio.free => 'free',
    CropRatio.square => '1:1',
    CropRatio.r4x3 => '4:3',
    CropRatio.r3x4 => '3:4',
    CropRatio.r16x9 => '16:9',
    CropRatio.r9x16 => '9:16',
    CropRatio.original => 'original',
  };

  static CropRatio? fromToken(String? token) {
    for (final ratio in CropRatio.values) {
      if (ratio.token == token) return ratio;
    }
    return null;
  }
}

/// The eight resize handles, in the order of [cropHandlePoints].
enum CropHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  /// -1: moves the left edge, 1: moves the right edge, 0: neither.
  int get dirX => switch (this) {
    topLeft || left || bottomLeft => -1,
    topRight || right || bottomRight => 1,
    _ => 0,
  };

  /// -1: moves the top edge, 1: moves the bottom edge, 0: neither.
  int get dirY => switch (this) {
    topLeft || top || topRight => -1,
    bottomLeft || bottom || bottomRight => 1,
    _ => 0,
  };

  bool get isCorner => dirX != 0 && dirY != 0;
}

/// Smallest crop side (image pixels); smaller than the image if the image is.
const minCropSize = 8.0;

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(v, lo));

double _snap(double v) => v.roundToDouble();

Rect wholeImageRect(Size image) =>
    Rect.fromLTWH(0, 0, image.width, image.height);

/// [r] snapped to whole pixels, at least [minSize] on each side and fully
/// inside [bounds] (the image).
Rect clampCropRect(Rect r, Size bounds, {double minSize = minCropSize}) {
  final minW = math.min(minSize, bounds.width);
  final minH = math.min(minSize, bounds.height);
  final w = _clamp(_snap(r.width), minW, bounds.width);
  final h = _clamp(_snap(r.height), minH, bounds.height);
  final left = _clamp(_snap(r.left), 0, bounds.width - w);
  final top = _clamp(_snap(r.top), 0, bounds.height - h);
  return Rect.fromLTWH(left, top, w, h);
}

/// The largest rect of aspect [ratio] (width / height) that fits inside
/// [current], centered on it, in whole pixels and inside [bounds]. Used when
/// a ratio preset is chosen. A non-positive [ratio] only clamps [current].
Rect fitRectToRatio(Rect current, double ratio, Size bounds) {
  final cur = clampCropRect(current, bounds);
  if (!(ratio > 0) || !ratio.isFinite) return cur;
  double w;
  double h;
  if (cur.width / cur.height > ratio) {
    h = cur.height;
    w = _snap(h * ratio);
  } else {
    w = cur.width;
    h = _snap(w / ratio);
  }
  w = math.max(1, math.min(w, cur.width));
  h = math.max(1, math.min(h, cur.height));
  final left = _clamp(_snap(cur.center.dx - w / 2), cur.left, cur.right - w);
  final top = _clamp(_snap(cur.center.dy - h / 2), cur.top, cur.bottom - h);
  return Rect.fromLTWH(left, top, w, h);
}

/// Handle positions of [r], in [CropHandle] order.
List<Offset> cropHandlePoints(Rect r) => [
  r.topLeft,
  r.topCenter,
  r.topRight,
  r.centerRight,
  r.bottomRight,
  r.bottomCenter,
  r.bottomLeft,
  r.centerLeft,
];

/// The handle of [r] nearest to [p] within [tolerance] (image pixels), if any.
CropHandle? hitCropHandle(Rect r, Offset p, double tolerance) {
  final points = cropHandlePoints(r);
  CropHandle? best;
  var bestDistance = tolerance;
  for (var i = 0; i < points.length; i++) {
    final d = (points[i] - p).distance;
    if (d <= bestDistance) {
      bestDistance = d;
      best = CropHandle.values[i];
    }
  }
  return best;
}

/// [rect] moved by [delta] (total drag distance), whole pixels, kept inside
/// [bounds].
Rect moveCropRect(Rect rect, Offset delta, Size bounds) {
  final left = _clamp(
    _snap(rect.left + delta.dx),
    0,
    bounds.width - rect.width,
  );
  final top = _clamp(
    _snap(rect.top + delta.dy),
    0,
    bounds.height - rect.height,
  );
  return Rect.fromLTWH(left, top, rect.width, rect.height);
}

/// Resizes [rect] by dragging [handle] to [pointer] (image pixels), without
/// ever leaving [bounds] or going under [minSize]. The opposite edge/corner
/// stays put. With a [ratio] (width / height; the preset, or the rect's own
/// ratio while Shift is held) the result keeps that ratio: corners grow along
/// it, edge handles also adjust the other side around the rect's center.
Rect resizeCropRect({
  required Rect rect,
  required CropHandle handle,
  required Offset pointer,
  required Size bounds,
  double? ratio,
  double minSize = minCropSize,
}) {
  final minW = math.min(minSize, bounds.width);
  final minH = math.min(minSize, bounds.height);
  final px = _clamp(_snap(pointer.dx), 0, bounds.width);
  final py = _clamp(_snap(pointer.dy), 0, bounds.height);
  final dx = handle.dirX;
  final dy = handle.dirY;

  if (ratio == null || !(ratio > 0) || !ratio.isFinite) {
    var l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    if (dx < 0) l = math.min(px, r - minW);
    if (dx > 0) r = math.max(px, l + minW);
    if (dy < 0) t = math.min(py, b - minH);
    if (dy > 0) b = math.max(py, t + minH);
    return Rect.fromLTRB(l, t, r, b);
  }

  final minWr = math.max(minW, minH * ratio);
  final minHr = math.max(minH, minW / ratio);
  // Anchor = the edge/corner opposite the handle.
  final ax = dx > 0 ? rect.left : rect.right;
  final ay = dy > 0 ? rect.top : rect.bottom;
  final maxW = dx > 0 ? bounds.width - ax : ax;
  final maxH = dy > 0 ? bounds.height - ay : ay;

  double w;
  double h;
  if (handle.isCorner) {
    final w0 = math.max(0.0, dx * (px - ax));
    final h0 = math.max(0.0, dy * (py - ay));
    w = math.max(w0, h0 * ratio);
    w = _clamp(w, minWr, math.min(maxW, maxH * ratio));
    w = _snap(w);
    h = _snap(w / ratio);
    if (h > maxH) {
      h = maxH.floorToDouble();
      w = _snap(h * ratio);
      if (w > maxW) w = maxW.floorToDouble();
    }
  } else if (dx != 0) {
    final w0 = math.max(0.0, dx * (px - ax));
    w = _snap(_clamp(w0, minWr, math.min(maxW, bounds.height * ratio)));
    h = math.min(bounds.height, _snap(w / ratio));
  } else {
    final h0 = math.max(0.0, dy * (py - ay));
    h = _snap(_clamp(h0, minHr, math.min(maxH, bounds.width / ratio)));
    w = math.min(bounds.width, _snap(h * ratio));
  }

  double left;
  double top;
  if (handle.isCorner) {
    left = dx > 0 ? ax : ax - w;
    top = dy > 0 ? ay : ay - h;
  } else if (dx != 0) {
    left = dx > 0 ? ax : ax - w;
    top = _clamp(_snap(rect.center.dy - h / 2), 0, bounds.height - h);
  } else {
    top = dy > 0 ? ay : ay - h;
    left = _clamp(_snap(rect.center.dx - w / 2), 0, bounds.width - w);
  }
  return Rect.fromLTWH(left, top, w, h);
}

/// The rect of a fresh drag from [start] to [pointer] (both clamped into
/// [bounds], whole pixels). It can be tiny or empty — the caller decides
/// whether a drag that small counts. With a [ratio] the rect keeps it.
Rect cropRectFromDrag(
  Offset start,
  Offset pointer,
  Size bounds, {
  double? ratio,
}) {
  final ax = _clamp(_snap(start.dx), 0, bounds.width);
  final ay = _clamp(_snap(start.dy), 0, bounds.height);
  final px = _clamp(_snap(pointer.dx), 0, bounds.width);
  final py = _clamp(_snap(pointer.dy), 0, bounds.height);
  final right = px >= ax;
  final down = py >= ay;
  final maxW = right ? bounds.width - ax : ax;
  final maxH = down ? bounds.height - ay : ay;
  var w = (px - ax).abs();
  var h = (py - ay).abs();
  if (ratio != null && ratio > 0 && ratio.isFinite) {
    w = math.max(w, h * ratio);
    w = math.min(w, math.min(maxW, maxH * ratio));
    w = _snap(w);
    h = _snap(w / ratio);
    if (h > maxH) {
      h = maxH.floorToDouble();
      w = math.min(_snap(h * ratio), maxW.floorToDouble());
    }
  }
  return Rect.fromLTWH(right ? ax : ax - w, down ? ay : ay - h, w, h);
}

/// Axis-aligned bounds of [a] as drawn (its [Annotation.bounds] turned by its
/// rotation about the pivot).
Rect annotationWorldBounds(Annotation a) {
  final b = a.bounds;
  if (a.rotation == 0) return b;
  final corners = [
    for (final c in [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft])
      rotatePoint(c, a.pivot, a.rotation),
  ];
  var minX = corners.first.dx, maxX = minX;
  var minY = corners.first.dy, maxY = minY;
  for (final c in corners) {
    minX = math.min(minX, c.dx);
    maxX = math.max(maxX, c.dx);
    minY = math.min(minY, c.dy);
    maxY = math.max(maxY, c.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// What happens to the annotations when the image is cropped to [crop]:
/// those entirely outside are dropped; the others (also the ones crossing the
/// border, which the canvas and the export clip) move with the image by
/// `-crop.topLeft` ([Annotation.shiftedWithImage]).
List<Annotation> annotationsAfterCrop(List<Annotation> annotations, Rect crop) {
  final delta = Offset(-crop.left, -crop.top);
  return [
    for (final a in annotations)
      if (annotationWorldBounds(a).overlaps(crop)) a.shiftedWithImage(delta),
  ];
}
