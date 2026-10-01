import 'package:flutter/material.dart';

/// Design tokens that do **not** depend on the OS theme: the annotation
/// color palette (a fixed creative-tool swatch set, like Photoshop's
/// default colors — it shouldn't reshuffle when the user changes their
/// desktop accent color) and the semantic status colors used for meaning
/// (danger/success/warning), which stay legible and recognizable regardless
/// of light/dark or accent.
class AppColors {
  AppColors._();

  static const danger = Color(0xFFFB7185);
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);

  /// Default annotation palette shown in the editor.
  static const palette = <Color>[
    Color(0xFFFF3B5C),
    Color(0xFFFF9F1C),
    Color(0xFFFFE156),
    Color(0xFF34D399),
    Color(0xFF22D3EE),
    Color(0xFF3B82F6),
    Color(0xFF7C5CFF),
    Color(0xFFF472B6),
    Color(0xFFFFFFFF),
    Color(0xFF111111),
  ];

  /// Fixed accent used only by canvas-level `CustomPainter` chrome (overlay
  /// selection border, camera-cursor badge, editor selection handles) —
  /// painted directly over arbitrary screenshot content, where a muted or
  /// pastel OS accent color could lose contrast. App *widget* chrome (
  /// buttons, panels, dialogs) uses the OS-driven `AppPalette` below instead.
  static const violet = Color(0xFF7C5CFF);
  static const cyan = Color(0xFF22D3EE);
}

/// OS-theme-driven design tokens for app *widget* chrome (Home, Settings,
/// dialogs, toolbars) — everything painted by Material widgets rather than
/// a `CustomPainter`. One instance is built for light and one for dark, both
/// seeded from the OS accent color, and exposed via
/// `Theme.of(context).extension<AppPalette>()` (see the `palette` getter
/// below) so it interpolates smoothly on an animated theme change like any
/// other `ThemeExtension`.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accentStart,
    required this.accentEnd,
  });

  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceOverlay;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textFaint;

  /// The two ends of the brand gradient — derived from the OS accent color's
  /// own Material tonal palette, so a red accent gives a red-ish gradient, a
  /// green one a green-ish gradient, etc., instead of always violet→cyan.
  final Color accentStart;
  final Color accentEnd;

  LinearGradient get accentGradient => LinearGradient(
    colors: [accentStart, accentEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  factory AppPalette.fromScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return AppPalette(
      bg: scheme.surface,
      surface: dark ? scheme.surfaceContainerLow : scheme.surfaceContainer,
      surfaceRaised: dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerHighest,
      surfaceOverlay: (dark ? scheme.surfaceContainerHigh : scheme.surface)
          .withValues(alpha: 0.8),
      border: scheme.outlineVariant.withValues(alpha: dark ? 0.35 : 0.6),
      borderStrong: scheme.outlineVariant.withValues(alpha: dark ? 0.6 : 0.9),
      text: scheme.onSurface,
      textMuted: scheme.onSurfaceVariant,
      textFaint: scheme.onSurfaceVariant.withValues(alpha: 0.65),
      accentStart: scheme.primary,
      accentEnd: HSLColor.fromColor(scheme.primary)
          .withHue((HSLColor.fromColor(scheme.primary).hue + 40) % 360)
          .toColor(),
    );
  }

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? accentStart,
    Color? accentEnd,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      accentStart: accentStart ?? this.accentStart,
      accentEnd: accentEnd ?? this.accentEnd,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accentStart: Color.lerp(accentStart, other.accentStart, t)!,
      accentEnd: Color.lerp(accentEnd, other.accentEnd, t)!,
    );
  }
}

/// Shorthand for `Theme.of(context).extension<AppPalette>()!` used
/// throughout the widget chrome.
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

class AppTheme {
  AppTheme._();

  /// Builds a full [ThemeData] seeded from [accent] (the OS accent color,
  /// or [AppColors.violet] as a fixed fallback) for the given [brightness].
  static ThemeData build({
    required Brightness brightness,
    required Color accent,
  }) {
    final generated = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    // `ColorScheme.fromSeed` remaps the seed onto Material's tonal palette —
    // in dark mode that means a much lighter, desaturated "primary" than the
    // seed itself (this is deliberate, for on-dark-surface contrast, but it
    // means the accent color no longer reads as *the same blue* the user
    // picked in System Settings). Keep the generated tonal palette for
    // everything else (surfaces, outlines, containers) but force `primary`
    // back to the literal accent, so switches/sliders/selection highlights
    // genuinely match the rest of the OS rather than a Material derivative.
    final onAccent = accent.computeLuminance() > 0.55
        ? const Color(0xFF111111)
        : Colors.white;
    final scheme = generated.copyWith(
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accent,
      onPrimaryContainer: onAccent,
      secondary: accent,
    );
    final palette = AppPalette.fromScheme(scheme);
    final dark = brightness == Brightness.dark;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.compact,
      extensions: [palette],
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
      iconTheme: IconThemeData(color: palette.text, size: 20),
      dividerColor: palette.border,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 1500),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        textStyle: TextStyle(color: palette.text, fontSize: 12),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: palette.accentStart,
        inactiveTrackColor: palette.borderStrong,
        thumbColor: palette.text,
        overlayColor: palette.accentStart.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (dark ? Colors.white : palette.accentStart)
              : palette.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentStart
              : palette.surfaceRaised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentStart
              : palette.borderStrong,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
        ),
        titleTextStyle: TextStyle(
          color: palette.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: palette.textMuted, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: TextStyle(color: palette.text),
        behavior: SnackBarBehavior.floating,
        width: 480,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border),
        ),
        textStyle: TextStyle(color: palette.text, fontSize: 13),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.accentStart),
        ),
      ),
    );
  }
}
