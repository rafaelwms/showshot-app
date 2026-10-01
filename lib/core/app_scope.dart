import 'package:flutter/widgets.dart';

import '../flow/capture_flow.dart';
import '../services/export_service.dart';
import '../services/hotkey_service.dart';
import '../services/native_bridge.dart';
import '../services/ocr_service.dart';
import '../services/settings_service.dart';
import '../services/startup_service.dart';
import '../services/system_theme_service.dart';
import '../services/tray_service.dart';

/// Bag of long-lived services shared across the widget tree.
class AppServices {
  const AppServices({
    required this.settings,
    required this.flow,
    required this.hotkeys,
    required this.tray,
    required this.startup,
    required this.native,
    required this.export,
    required this.ocr,
    required this.systemTheme,
  });

  final SettingsService settings;
  final CaptureFlow flow;
  final HotkeyService hotkeys;
  final TrayService tray;
  final StartupService startup;
  final NativeBridge native;
  final ExportService export;
  final OcrService ocr;
  final SystemThemeService systemTheme;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
