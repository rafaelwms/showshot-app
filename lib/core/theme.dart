import 'package:flutter/material.dart';

/// Show Shot design tokens — a dark, glassy UI with a violet→cyan accent.
class AppColors {
  AppColors._();

  static const bg = Color(0xFF0E1018);
  static const surface = Color(0xFF161A2B);
  static const surfaceRaised = Color(0xFF1E2337);
  static const surfaceOverlay = Color(0xCC161A2B);
  static const border = Color(0x1AFFFFFF);
  static const borderStrong = Color(0x33FFFFFF);
  static const text = Color(0xFFF2F4FF);
  static const textMuted = Color(0xFF9AA3C2);
  static const textFaint = Color(0xFF5F6786);
  static const violet = Color(0xFF7C5CFF);
  static const cyan = Color(0xFF22D3EE);
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFFB7185);
  static const warning = Color(0xFFFBBF24);

  static const accentGradient = LinearGradient(
    colors: [violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.violet,
      secondary: AppColors.cyan,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
      outline: AppColors.borderStrong,
      surfaceContainerHighest: AppColors.surfaceRaised,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      iconTheme: const IconThemeData(color: AppColors.text, size: 20),
      dividerColor: AppColors.border,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 1500),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        activeTrackColor: AppColors.violet,
        inactiveTrackColor: AppColors.borderStrong,
        thumbColor: AppColors.text,
        overlayColor: Color(0x337C5CFF),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.violet
              : AppColors.surfaceRaised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.violet
              : AppColors.borderStrong,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: const TextStyle(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
        width: 480,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: const TextStyle(color: AppColors.text, fontSize: 13),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.violet),
        ),
      ),
    );
  }
}
