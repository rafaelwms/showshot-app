import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'capture_mode.dart';

enum ImageFormat { png, jpg }

/// What happens when the user confirms a selection in the overlay with Enter.
enum AfterCaptureAction { openEditor, copyToClipboard, saveToFile }

enum AppLanguage { system, portuguese, english }

/// User preferences. Immutable; use [copyWith] and persist via SettingsService.
class AppSettings {
  const AppSettings({
    required this.hotKeys,
    this.launchAtStartup = false,
    this.showDockIcon = false,
    this.saveFormat = ImageFormat.png,
    this.jpgQuality = 90,
    this.saveDirectory,
    this.askWhereToSave = true,
    this.copyAfterSave = true,
    this.showMagnifier = true,
    this.afterCaptureAction = AfterCaptureAction.openEditor,
    this.language = AppLanguage.system,
    this.recentFiles = const [],
  });

  final Map<CaptureMode, HotKey?> hotKeys;
  final bool launchAtStartup;
  final bool showDockIcon;
  final ImageFormat saveFormat;
  final int jpgQuality;
  final String? saveDirectory;
  final bool askWhereToSave;
  final bool copyAfterSave;
  final bool showMagnifier;
  final AfterCaptureAction afterCaptureAction;
  final AppLanguage language;
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
  };

  factory AppSettings.defaults() => AppSettings(hotKeys: defaultHotKeys());

  AppSettings copyWith({
    Map<CaptureMode, HotKey?>? hotKeys,
    bool? launchAtStartup,
    bool? showDockIcon,
    ImageFormat? saveFormat,
    int? jpgQuality,
    String? saveDirectory,
    bool clearSaveDirectory = false,
    bool? askWhereToSave,
    bool? copyAfterSave,
    bool? showMagnifier,
    AfterCaptureAction? afterCaptureAction,
    AppLanguage? language,
    List<String>? recentFiles,
  }) {
    return AppSettings(
      hotKeys: hotKeys ?? this.hotKeys,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      showDockIcon: showDockIcon ?? this.showDockIcon,
      saveFormat: saveFormat ?? this.saveFormat,
      jpgQuality: jpgQuality ?? this.jpgQuality,
      saveDirectory: clearSaveDirectory
          ? null
          : (saveDirectory ?? this.saveDirectory),
      askWhereToSave: askWhereToSave ?? this.askWhereToSave,
      copyAfterSave: copyAfterSave ?? this.copyAfterSave,
      showMagnifier: showMagnifier ?? this.showMagnifier,
      afterCaptureAction: afterCaptureAction ?? this.afterCaptureAction,
      language: language ?? this.language,
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
    'saveFormat': saveFormat.name,
    'jpgQuality': jpgQuality,
    'saveDirectory': saveDirectory,
    'askWhereToSave': askWhereToSave,
    'copyAfterSave': copyAfterSave,
    'showMagnifier': showMagnifier,
    'afterCaptureAction': afterCaptureAction.name,
    'language': language.name,
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
      saveFormat: ImageFormat.values.byNameOr(
        json['saveFormat'],
        ImageFormat.png,
      ),
      jpgQuality: (json['jpgQuality'] as num?)?.toInt() ?? 90,
      saveDirectory: json['saveDirectory'] as String?,
      askWhereToSave: json['askWhereToSave'] as bool? ?? true,
      copyAfterSave: json['copyAfterSave'] as bool? ?? true,
      showMagnifier: json['showMagnifier'] as bool? ?? true,
      afterCaptureAction: AfterCaptureAction.values.byNameOr(
        json['afterCaptureAction'],
        AfterCaptureAction.openEditor,
      ),
      language: AppLanguage.values.byNameOr(
        json['language'],
        AppLanguage.system,
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
