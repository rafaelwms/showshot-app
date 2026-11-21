import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/theme.dart';
import 'capture_mode.dart';
import 'tool_memory.dart';

enum ImageFormat { png, jpg }

/// What happens when the user confirms a selection in the overlay with Enter.
enum AfterCaptureAction { openEditor, copyToClipboard, saveToFile }

/// How saved files are named: by capture time, or prefix + global counter.
enum FileNaming { timestamp, sequence }

/// Glue between the prefix and the counter in sequential names.
enum NameSeparator { underscore, dash, space, none }

/// What "All screens" writes: one file per display, or a single stitched image.
enum AllScreensMode { perScreen, combined }

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
    this.saveToLastFolder = false,
    this.lastSaveDirectory = '',
    this.fileNaming = FileNaming.timestamp,
    this.namePrefix = 'ShowShot',
    this.nameSeparator = NameSeparator.underscore,
    this.nameDigits = 2,
    this.sequenceNext = 1,
    this.askWhereToSave = true,
    this.copyAfterSave = true,
    this.allScreensMode = AllScreensMode.perScreen,
    this.systemNotifications = true,
    this.showMagnifier = true,
    this.afterCaptureAction = AfterCaptureAction.openEditor,
    this.language = AppLanguage.system,
    this.trayLeftClick = TrayAction.area,
    this.editorWindow = EditorWindowMode.maximized,
    this.rememberTools = false,
    this.boldIcons = false,
    this.toolMemory,
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

  /// File naming scheme; the fields below only matter for [FileNaming.sequence].
  final FileNaming fileNaming;

  /// Raw prefix as typed (sanitized when a name is built).
  final String namePrefix;
  final NameSeparator nameSeparator;

  /// Zero-padding width of the counter, 1-5.
  final int nameDigits;

  /// Next counter value. Global: independent of the destination folder.
  final int sequenceNext;

  /// When on, saves go to [lastSaveDirectory] (falling back to the default
  /// folder when it no longer exists).
  final bool saveToLastFolder;

  /// Directory of the most recent successful save ('' = none yet).
  final String lastSaveDirectory;
  final bool copyAfterSave;

  /// Output of the "All screens" action.
  final AllScreensMode allScreensMode;

  /// Report copied/saved/text-recognized as OS notifications (instead of an
  /// in-app toast that a hidden window can't show).
  final bool systemNotifications;
  final bool showMagnifier;
  final AfterCaptureAction afterCaptureAction;
  final AppLanguage language;

  /// Action of a left click on the menu bar / tray icon (macOS, Windows).
  final TrayAction trayLeftClick;
  final EditorWindowMode editorWindow;

  /// Restore the last tool and style values when the editor opens (and keep
  /// [toolMemory] up to date while editing). Off by default.
  final bool rememberTools;

  /// Bold weight for the editor/overlay icons (see `AppIcons`).
  final bool boldIcons;

  /// What the editor last used; kept untouched while [rememberTools] is off.
  final ToolMemory? toolMemory;
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
    CaptureMode.allScreens: HotKey(
      identifier: 'shoshot.allscreens',
      key: PhysicalKeyboardKey.digit5,
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
    FileNaming? fileNaming,
    String? namePrefix,
    NameSeparator? nameSeparator,
    int? nameDigits,
    int? sequenceNext,
    bool? askWhereToSave,
    bool? saveToLastFolder,
    String? lastSaveDirectory,
    bool? copyAfterSave,
    AllScreensMode? allScreensMode,
    bool? systemNotifications,
    bool? showMagnifier,
    AfterCaptureAction? afterCaptureAction,
    AppLanguage? language,
    TrayAction? trayLeftClick,
    EditorWindowMode? editorWindow,
    bool? rememberTools,
    bool? boldIcons,
    ToolMemory? toolMemory,
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
      fileNaming: fileNaming ?? this.fileNaming,
      namePrefix: namePrefix ?? this.namePrefix,
      nameSeparator: nameSeparator ?? this.nameSeparator,
      nameDigits: nameDigits ?? this.nameDigits,
      sequenceNext: sequenceNext ?? this.sequenceNext,
      askWhereToSave: askWhereToSave ?? this.askWhereToSave,
      saveToLastFolder: saveToLastFolder ?? this.saveToLastFolder,
      lastSaveDirectory: lastSaveDirectory ?? this.lastSaveDirectory,
      copyAfterSave: copyAfterSave ?? this.copyAfterSave,
      allScreensMode: allScreensMode ?? this.allScreensMode,
      systemNotifications: systemNotifications ?? this.systemNotifications,
      showMagnifier: showMagnifier ?? this.showMagnifier,
      afterCaptureAction: afterCaptureAction ?? this.afterCaptureAction,
      language: language ?? this.language,
      trayLeftClick: trayLeftClick ?? this.trayLeftClick,
      editorWindow: editorWindow ?? this.editorWindow,
      rememberTools: rememberTools ?? this.rememberTools,
      boldIcons: boldIcons ?? this.boldIcons,
      toolMemory: toolMemory ?? this.toolMemory,
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
    'fileNaming': fileNaming.name,
    'namePrefix': namePrefix,
    'nameSeparator': nameSeparator.name,
    'nameDigits': nameDigits,
    'sequenceNext': sequenceNext,
    'askWhereToSave': askWhereToSave,
    'saveToLastFolder': saveToLastFolder,
    'lastSaveDirectory': lastSaveDirectory,
    'copyAfterSave': copyAfterSave,
    'allScreensMode': allScreensMode.name,
    'systemNotifications': systemNotifications,
    'showMagnifier': showMagnifier,
    'afterCaptureAction': afterCaptureAction.name,
    'language': language.name,
    'trayLeftClick': trayLeftClick.name,
    'editorWindow': editorWindow.name,
    'rememberTools': rememberTools,
    'boldIcons': boldIcons,
    'toolMemory': toolMemory?.toJson(),
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
      fileNaming: FileNaming.values.byNameOr(
        json['fileNaming'],
        FileNaming.timestamp,
      ),
      namePrefix: json['namePrefix'] as String? ?? 'ShowShot',
      nameSeparator: NameSeparator.values.byNameOr(
        json['nameSeparator'],
        NameSeparator.underscore,
      ),
      nameDigits: _atLeast(
        1,
        (json['nameDigits'] as num?)?.toInt() ?? 2,
        max: 5,
      ),
      sequenceNext: _atLeast(1, (json['sequenceNext'] as num?)?.toInt() ?? 1),
      askWhereToSave: json['askWhereToSave'] as bool? ?? true,
      saveToLastFolder: json['saveToLastFolder'] as bool? ?? false,
      lastSaveDirectory: json['lastSaveDirectory'] as String? ?? '',
      copyAfterSave: json['copyAfterSave'] as bool? ?? true,
      allScreensMode: AllScreensMode.values.byNameOr(
        json['allScreensMode'],
        AllScreensMode.perScreen,
      ),
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
      rememberTools: json['rememberTools'] as bool? ?? false,
      boldIcons: json['boldIcons'] as bool? ?? false,
      toolMemory: json['toolMemory'] is Map
          ? ToolMemory.fromJson(
              (json['toolMemory'] as Map).cast<String, dynamic>(),
              AppColors.palette.first.toARGB32(),
            )
          : null,
      recentFiles: (json['recentFiles'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// Clamps [value] to [min]..[max] while keeping the static type `int`.
int _atLeast(int min, int value, {int max = 1 << 30}) =>
    value < min ? min : (value > max ? max : value);

extension _EnumByName<T extends Enum> on Iterable<T> {
  T byNameOr(Object? name, T fallback) {
    if (name is! String) return fallback;
    for (final value in this) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
