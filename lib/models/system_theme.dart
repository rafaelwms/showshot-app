import 'dart:ui';

/// The user's OS accent color, as exposed by System Settings (macOS),
/// Personalization > Colors (Windows 11) or the desktop portal
/// (Linux/GNOME).
///
/// Light/dark mode itself is **not** read here: Flutter's engine already
/// detects that on every desktop platform (`PlatformDispatcher
/// .platformBrightness`, which `ThemeMode.system` uses) — no native code
/// needed for it. This type exists only for the one signal Flutter has no
/// built-in API for.
class SystemAccent {
  const SystemAccent(this.color);

  final Color color;

  /// Used before the native bridge answers (or where reading the OS accent
  /// isn't implemented) — the app's original fixed violet.
  static const fallback = SystemAccent(Color(0xFF7C5CFF));

  @override
  bool operator ==(Object other) =>
      other is SystemAccent && other.color.toARGB32() == color.toARGB32();

  @override
  int get hashCode => color.toARGB32();

  @override
  String toString() => 'SystemAccent($color)';
}
