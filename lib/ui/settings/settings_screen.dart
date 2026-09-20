import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../debug/debug_server.dart';
import '../../models/app_settings.dart';
import '../../models/capture_mode.dart';
import '../../services/export_service.dart';
import '../widgets/common.dart';
import 'hotkey_field.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _defaultDir;

  @override
  void initState() {
    super.initState();
    DebugHooks.settingsBack = _goBack;
    ExportService.defaultDirectory().then((dir) {
      if (mounted) setState(() => _defaultDir = dir.path);
    });
  }

  @override
  void dispose() {
    if (DebugHooks.settingsBack == _goBack) DebugHooks.settingsBack = null;
    super.dispose();
  }

  // Settings opened from within the app (the Home gear icon) sits on top of
  // a Home route to pop back to. Opened directly (tray menu →
  // "Configurações…") it is the only route on the stack, so there is
  // nothing to pop — `maybePop` would silently do nothing there.
  void _goBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      AppScope.of(context).flow.showHome();
    }
  }

  void _onRecordingChanged(bool recording) {
    final hotkeys = AppScope.of(context).hotkeys;
    if (recording) {
      hotkeys.suspend();
    } else {
      hotkeys.resume();
    }
  }

  Future<void> _chooseFolder() async {
    final services = AppScope.of(context);
    final current = services.settings.settings.saveDirectory ?? _defaultDir;
    final path = await getDirectoryPath(initialDirectory: current);
    if (path != null) {
      await services.settings.update((s) => s.copyWith(saveDirectory: path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    // The whole screen rebuilds on every settings change (not just the inner
    // controls) so that picking a new language updates every label here
    // immediately, instead of only the widgets that read `settings.xxx`
    // fields directly.
    return ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.hotkeys]),
      builder: (context, _) {
        final strings = Strings.of(context);
        final settings = services.settings.settings;
        return Scaffold(
          body: Column(
            children: [
              WindowTitleBar(
                leading: ToolButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: strings.back,
                  onPressed: _goBack,
                ),
                title: Text(strings.settings),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    Future<void> update(
                      AppSettings Function(AppSettings) mutate,
                    ) => services.settings.update(mutate);

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 4, 28, 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Section(
                                title: strings.sectionGeneral,
                                children: [
                                  _SettingRow(
                                    title: strings.launchAtStartup,
                                    subtitle: strings.launchAtStartupHint,
                                    trailing: Switch(
                                      value: settings.launchAtStartup,
                                      onChanged: (v) => update(
                                        (s) => s.copyWith(launchAtStartup: v),
                                      ),
                                    ),
                                  ),
                                  if (Platform.isMacOS)
                                    _SettingRow(
                                      title: strings.showDockIcon,
                                      subtitle: strings.showDockIconHint,
                                      trailing: Switch(
                                        value: settings.showDockIcon,
                                        onChanged: (v) => update(
                                          (s) => s.copyWith(showDockIcon: v),
                                        ),
                                      ),
                                    ),
                                  _SettingRow(
                                    title: strings.language,
                                    trailing: _Dropdown<AppLanguage>(
                                      value: settings.language,
                                      items: {
                                        AppLanguage.system:
                                            strings.languageSystem,
                                        AppLanguage.portuguese:
                                            strings.languagePortuguese,
                                        AppLanguage.english:
                                            strings.languageEnglish,
                                      },
                                      onChanged: (v) => update(
                                        (s) => s.copyWith(language: v),
                                      ),
                                    ),
                                  ),
                                  _SettingRow(
                                    title: strings.showMagnifier,
                                    subtitle: strings.showMagnifierHint,
                                    trailing: Switch(
                                      value: settings.showMagnifier,
                                      onChanged: (v) => update(
                                        (s) => s.copyWith(showMagnifier: v),
                                      ),
                                    ),
                                  ),
                                  _SettingRow(
                                    title: strings.afterCapture,
                                    subtitle: strings.afterCaptureHint,
                                    trailing: _Dropdown<AfterCaptureAction>(
                                      value: settings.afterCaptureAction,
                                      items: {
                                        for (final action
                                            in AfterCaptureAction.values)
                                          action: strings.afterCaptureOption(
                                            action,
                                          ),
                                      },
                                      onChanged: (v) => update(
                                        (s) =>
                                            s.copyWith(afterCaptureAction: v),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _Section(
                                title: strings.sectionShortcuts,
                                footer: strings.shortcutsHint,
                                children: [
                                  for (final mode in CaptureMode.values)
                                    _SettingRow(
                                      title: strings.modeName(mode),
                                      subtitle: strings.modeDescription(mode),
                                      trailing: HotkeyField(
                                        value: settings.hotKeys[mode],
                                        identifier: 'shoshot.${mode.name}',
                                        failed: services.hotkeys.failed
                                            .contains(mode),
                                        onRecordingChanged: _onRecordingChanged,
                                        onChanged: (hotKey) => update(
                                          (s) => s.copyWith(
                                            hotKeys: {
                                              ...s.hotKeys,
                                              mode: hotKey,
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () => update(
                                        (s) => s.copyWith(
                                          hotKeys: AppSettings.defaultHotKeys(),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.restart_alt_rounded,
                                        size: 16,
                                      ),
                                      label: Text(strings.resetDefaults),
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            context.palette.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _Section(
                                title: strings.sectionSaving,
                                children: [
                                  _SettingRow(
                                    title: strings.saveFormat,
                                    trailing: SegmentedButton<ImageFormat>(
                                      showSelectedIcon: false,
                                      style: SegmentedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        selectedBackgroundColor:
                                            context.palette.accentStart,
                                        selectedForegroundColor: Colors.white,
                                        foregroundColor:
                                            context.palette.textMuted,
                                        side: BorderSide(
                                          color: context.palette.borderStrong,
                                        ),
                                      ),
                                      segments: const [
                                        ButtonSegment(
                                          value: ImageFormat.png,
                                          label: Text('PNG'),
                                        ),
                                        ButtonSegment(
                                          value: ImageFormat.jpg,
                                          label: Text('JPG'),
                                        ),
                                      ],
                                      selected: {settings.saveFormat},
                                      onSelectionChanged: (v) => update(
                                        (s) => s.copyWith(saveFormat: v.first),
                                      ),
                                    ),
                                  ),
                                  if (settings.saveFormat == ImageFormat.jpg)
                                    _SettingRow(
                                      title: strings.jpgQuality,
                                      trailing: SizedBox(
                                        width: 220,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Slider(
                                                value: settings.jpgQuality
                                                    .toDouble(),
                                                min: 40,
                                                max: 100,
                                                divisions: 12,
                                                onChanged: (v) => update(
                                                  (s) => s.copyWith(
                                                    jpgQuality: v.round(),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 34,
                                              child: Text(
                                                '${settings.jpgQuality}',
                                                textAlign: TextAlign.end,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  _SettingRow(
                                    title: strings.saveDirectory,
                                    subtitle:
                                        settings.saveDirectory ??
                                        _defaultDir ??
                                        strings.saveDirectoryDefault,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GhostButton(
                                          label: strings.chooseFolder,
                                          compact: true,
                                          onPressed: _chooseFolder,
                                        ),
                                        if (settings.saveDirectory != null)
                                          IconButton(
                                            tooltip: strings.resetDefaults,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => update(
                                              (s) => s.copyWith(
                                                clearSaveDirectory: true,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.restart_alt_rounded,
                                              size: 18,
                                            ),
                                            color: context.palette.textMuted,
                                          ),
                                      ],
                                    ),
                                  ),
                                  _SettingRow(
                                    title: strings.askWhereToSave,
                                    subtitle: strings.askWhereToSaveHint,
                                    trailing: Switch(
                                      value: settings.askWhereToSave,
                                      onChanged: (v) => update(
                                        (s) => s.copyWith(askWhereToSave: v),
                                      ),
                                    ),
                                  ),
                                  _SettingRow(
                                    title: strings.copyAfterSave,
                                    subtitle: strings.copyAfterSaveHint,
                                    trailing: Switch(
                                      value: settings.copyAfterSave,
                                      onChanged: (v) => update(
                                        (s) => s.copyWith(copyAfterSave: v),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _Section(
                                title: strings.sectionAbout,
                                children: [
                                  Row(
                                    children: [
                                      const BrandMark(size: 44),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              strings.appName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            Text(
                                              '${strings.version} 1.0.0 · ${strings.madeBy}',
                                              style: TextStyle(
                                                color:
                                                    context.palette.textMuted,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      GhostButton(
                                        label: strings.website,
                                        icon: Icons.open_in_new_rounded,
                                        compact: true,
                                        onPressed: () => _openUrl(
                                          'https://showshot.rafaelwms.com',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: SectionLabel(title),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.palette.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: children[i],
                  ),
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: Text(
                footer!,
                style: TextStyle(
                  color: context.palette.textFaint,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: context.palette.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        trailing,
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.borderStrong),
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        style: TextStyle(
          color: context.palette.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        iconEnabledColor: context.palette.textMuted,
        isDense: true,
        items: [
          for (final entry in items.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
