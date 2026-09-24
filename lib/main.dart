import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'debug/debug_server.dart';
import 'flow/capture_flow.dart';
import 'services/capture_service.dart';
import 'services/export_service.dart';
import 'services/hotkey_service.dart';
import 'services/native_bridge.dart';
import 'services/ocr_service.dart';
import 'services/settings_service.dart';
import 'services/startup_service.dart';
import 'services/system_theme_service.dart';
import 'services/tray_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  final settings = await SettingsService.load();
  final native = NativeBridge.instance;
  final capture = CaptureService(native);
  final export = ExportService(native)
    ..onBookmarkRefreshed = (bookmark) =>
        settings.update((s) => s.copyWith(saveDirectoryBookmark: bookmark));
  final ocr = OcrService(native);
  final flow = CaptureFlow(
    settings: settings,
    native: native,
    capture: capture,
    export: export,
    ocr: ocr,
  );
  final hotkeys = HotkeyService(settings: settings, onTrigger: flow.start);
  final tray = TrayService(
    settings: settings,
    onCapture: flow.start,
    onOpen: flow.showHome,
    onSettings: flow.openSettings,
    onQuit: flow.quit,
  );
  final startup = StartupService(settings);
  final systemTheme = SystemThemeService(native);
  // Read before the first frame so the app never flashes the fallback
  // accent color before swapping to the real OS one.
  await systemTheme.init();

  final startHidden =
      args.contains(StartupService.launchArg) || args.contains('--hidden');

  const options = WindowOptions(
    size: CaptureFlow.homeSize,
    minimumSize: CaptureFlow.minSize,
    center: true,
    title: 'Show Shot',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    if (!startHidden) {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  final services = AppServices(
    settings: settings,
    flow: flow,
    hotkeys: hotkeys,
    tray: tray,
    startup: startup,
    native: native,
    export: export,
    ocr: ocr,
    systemTheme: systemTheme,
  );
  runApp(ShoShotApp(services: services));

  // Background integrations can come up after the first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await DebugCommandServer.start(services);
    await tray.init();
    await hotkeys.init();
    await startup.init();
    if (Platform.isMacOS) {
      await native.setDockIconVisible(settings.settings.showDockIcon);
      settings.addListener(
        () => native.setDockIconVisible(settings.settings.showDockIcon),
      );
    }
  });
}
