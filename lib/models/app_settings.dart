import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'capture_mode.dart';

enum ImageFormat { png, jpg }

/// What happens when the user confirms a selection in the overlay with Enter.
enum AfterCaptureAction { openEditor, copyToClipboard, saveToFile }

enum AppLanguage { system, portuguese, english }

/// How the editor window opens: at a size derived from the capture, maximized
/// (the default — fills the screen but keeps the title bar / Dock), or in the
/// OS full-screen mode (not offered on Windows).
enum EditorWindowMode { normal, maximized, fullScreen }

/// What a left click on the menu bar / tray icon does. The four capture
/// modes start that capture, [openApp] shows the window and [menu] pops up
/// the same menu a left click opens.
enum TrayAction {
  area(CaptureMode.area),
  window(CaptureMode.window),
  fullScreen(CaptureMode.fullScreen),
  text(CaptureMode.text),
  openApp(null),
  menu(null);

  const TrayAction(this.mode);

  /// The capture this action starts, or null for [openApp] / [menu].
  final CaptureMode? mode;
}

/// User preferences. Immutable; use [copyWith] and persist via SettingsService.
class AppSettings {
  const AppSettings({
    required this.hotKeys,
    this.launchAtStartup = false,
    this.showDockIcon = false,
    this.showTaskbarIcon = true,
    this.saveFormat = ImageFormat.png,
    this.jpgQuality = 90,
    this.saveDirectory,
    this.saveDirectoryBookmark,
    this.askWhereToSave = true,
    this.copyAfterSave = true,
    this.systemNotifications = true,
    this.showMagnifier = true,
    this.afterCaptureAction = AfterCaptureAction.openEditor,
    this.language = AppLanguage.system,
    this.trayLeftClick = TrayAction.area,
    this.editorWindow = EditorWindowMode.maximized,
    this.recentFiles = const [],
  });

  final Map<CaptureMode, HotKey?> hotKeys;
  final bool launchAtStartup;
  final bool showDockIcon;
  final bool showTaskbarIcon;
  final ImageFormat saveFormat;
  final int jpgQuality;
  final String? saveDirectory;

  /// macOS only: base64 security-scoped bookmark for [saveDirectory], which
  /// App Sandbox needs to write there again after a relaunch.
  final String? saveDirectoryBookmark;
  final bool askWhereToSave;
  final bool copyAfterSave;

  /// Report copied/saved/text-recognized as OS notifications (instead of an
  /// in-app toast that a hidden window can't show).
  final bool systemNotifications;
  final bool showMagnifier;
  final AfterCaptureAction afterCaptureAction;
  final AppLanguage language;

  /// Action of a left click on the menu bar / tray icon (macOS, Windows).
  final TrayAction trayLeftClick;
  final EditorWindowMode editorWindow;
  final List<String> recentFiles;

  static Map<CaptureMode, HotKey?> defaultHotKeys() => {
    CaptureMode.area: HotKey(
      identifier: 'shoshot.area',
      key: PhysicalKeyboardKey.digit1,
      modifiers: const [HotKeyModifier.control, HotKeyModifier.shift],
    ),
    CaptureMode.window: HotKey(
      identifier: 'shoshot.window',
      key: PhysicalKeyboardKey.digit2,
      modifiers: const [HotKeyModifier.control, HotKeyModifier.shift],
    ),
    CaptureMode.fullScreen: HotKey(
      identifier: 'shoshot.fullscreen',
      key: PhysicalKeyboardKey.digit3,
      modifiers: const [HotKeyModifier.control, HotKeyModifier.shift],
    ),
    CaptureMode.text: HotKey(
      identifier: 'shoshot.text',
      key: PhysicalKeyboardKey.digit4,
      modifiers: const [HotKeyModifier.control, HotKeyModifier.shift],
    ),
  };

  factory AppSettings.defaults() => AppSettings(hotKeys: defaultHotKeys());

  AppSettings copyWith({
    Map<CaptureMode, HotKey?>? hotKeys,
    bool? launchAtStartup,
    bool? showDockIcon,
    bool? showTaskbarIcon,
    ImageFormat? saveFormat,
    int? jpgQuality,
    String? saveDirectory,
    String? saveDirectoryBookmark,
    bool clearSaveDirectory = false,
    bool? askWhereToSave,
    bool? copyAfterSave,
    bool? systemNotifications,
    bool? showMagnifier,
    AfterCaptureAction? afterCaptureAction,
    AppLanguage? language,
    TrayAction? trayLeftClick,
    EditorWindowMode? editorWindow,
    List<String>? recentFiles,
  }) {
    return AppSettings(
      hotKeys: hotKeys ?? this.hotKeys,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      showDockIcon: showDockIcon ?? this.showDockIcon,
      showTaskbarIcon: showTaskbarIcon ?? this.showTaskbarIcon,
      saveFormat: saveFormat ?? this.saveFormat,
      jpgQuality: jpgQuality ?? this.jpgQuality,
      saveDirectory: clearSaveDirectory
          ? null
          : (saveDirectory ?? this.saveDirectory),
      saveDirectoryBookmark: clearSaveDirectory
          ? null
          : (saveDirectoryBookmark ?? this.saveDirectoryBookmark),
      askWhereToSave: askWhereToSave ?? this.askWhereToSave,
      copyAfterSave: copyAfterSave ?? this.copyAfterSave,
      systemNotifications: systemNotifications ?? this.systemNotifications,
      showMagnifier: showMagnifier ?? this.showMagnifier,
      afterCaptureAction: afterCaptureAction ?? this.afterCaptureAction,
      language: language ?? this.language,
      trayLeftClick: trayLeftClick ?? this.trayLeftClick,
      editorWindow: editorWindow ?? this.editorWindow,
      recentFiles: recentFiles ?? this.recentFiles,
    );
  }

  Map<String, dynamic> toJson() => {
    'hotKeys': {
      for (final entry in hotKeys.entries)
        entry.key.name: entry.value?.toJson(),
    },
    'launchAtStartup': launchAtStartup,
    'showDockIcon': showDockIcon,
    'showTaskbarIcon': showTaskbarIcon,
    'saveFormat': saveFormat.name,
    'jpgQuality': jpgQuality,
    'saveDirectory': saveDirectory,
    'saveDirectoryBookmark': saveDirectoryBookmark,
    'askWhereToSave': askWhereToSave,
    'copyAfterSave': copyAfterSave,
    'systemNotifications': systemNotifications,
    'showMagnifier': showMagnifier,
    'afterCaptureAction': afterCaptureAction.name,
    'language': language.name,
    'trayLeftClick': trayLeftClick.name,
    'editorWindow': editorWindow.name,
    'recentFiles': recentFiles,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    final rawHotKeys = json['hotKeys'] as Map<String, dynamic>? ?? const {};
    final hotKeys = <CaptureMode, HotKey?>{};
    for (final mode in CaptureMode.values) {
      if (rawHotKeys.containsKey(mode.name)) {
        final raw = rawHotKeys[mode.name];
        hotKeys[mode] = raw == null
            ? null
            : HotKey.fromJson((raw as Map).cast<String, dynamic>());
      } else {
        hotKeys[mode] = defaults.hotKeys[mode];
      }
    }
    return AppSettings(
      hotKeys: hotKeys,
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
      showDockIcon: json['showDockIcon'] as bool? ?? false,
      showTaskbarIcon: json['showTaskbarIcon'] as bool? ?? true,
      saveFormat: ImageFormat.values.byNameOr(
        json['saveFormat'],
        ImageFormat.png,
      ),
      jpgQuality: (json['jpgQuality'] as num?)?.toInt() ?? 90,
      saveDirectory: json['saveDirectory'] as String?,
      saveDirectoryBookmark: json['saveDirectoryBookmark'] as String?,
      askWhereToSave: json['askWhereToSave'] as bool? ?? true,
      copyAfterSave: json['copyAfterSave'] as bool? ?? true,
      systemNotifications: json['systemNotifications'] as bool? ?? true,
      showMagnifier: json['showMagnifier'] as bool? ?? true,
      afterCaptureAction: AfterCaptureAction.values.byNameOr(
        json['afterCaptureAction'],
        AfterCaptureAction.openEditor,
      ),
      language: AppLanguage.values.byNameOr(
        json['language'],
        AppLanguage.system,
      ),
      trayLeftClick: TrayAction.values.byNameOr(
        json['trayLeftClick'],
        TrayAction.area,
      ),
      editorWindow: EditorWindowMode.values.byNameOr(
        json['editorWindow'],
        EditorWindowMode.maximized,
      ),
      recentFiles: (json['recentFiles'] as List?)?.cast<String>() ?? const [],
    );
  }
}

extension _EnumByName<T extends Enum> on Iterable<T> {
  T byNameOr(Object? name, T fallback) {
    if (name is! String) return fallback;
    for (final value in this) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
