import 'dart:ui';

/// A top-level window visible on screen, front-most first.
///
/// [bounds] uses the same global coordinate space as `DisplayInfo.bounds`.
class WindowInfo {
  const WindowInfo({
    required this.id,
    required this.title,
    required this.app,
    required this.bounds,
  });

  final int id;
  final String title;
  final String app;
  final Rect bounds;

  String get label {
    if (app.isNotEmpty && title.isNotEmpty && app != title) {
      return '$app — $title';
    }
    if (title.isNotEmpty) return title;
    return app;
  }

  WindowInfo copyWith({Rect? bounds}) =>
      WindowInfo(id: id, title: title, app: app, bounds: bounds ?? this.bounds);

  factory WindowInfo.fromMap(Map<Object?, Object?> map) => WindowInfo(
    id: (map['id'] as num).toInt(),
    title: map['title'] as String? ?? '',
    app: map['app'] as String? ?? '',
    bounds: Rect.fromLTWH(
      (map['x'] as num).toDouble(),
      (map['y'] as num).toDouble(),
      (map['width'] as num).toDouble(),
      (map['height'] as num).toDouble(),
    ),
  );
}
