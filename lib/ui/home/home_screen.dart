import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../flow/capture_flow.dart';
import '../../models/capture_mode.dart';
import '../../services/hotkey_service.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingMessage());
  }

  void _showPendingMessage() {
    if (!mounted) return;
    final services = AppScope.of(context);
    final message = services.flow.lastMessage;
    if (message == null) return;
    services.flow.consumeMessage();
    final strings = Strings.of(context);
    final text = switch (message.kind) {
      FlowMessageKind.copied => strings.copied,
      FlowMessageKind.saved => strings.savedTo(message.path ?? ''),
      FlowMessageKind.saveFailed => strings.saveFailed,
      FlowMessageKind.captureFailed => strings.captureFailed,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final strings = Strings.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.9, -1.2),
            radius: 1.6,
            colors: [Color(0xFF1B1F3A), AppColors.bg],
          ),
        ),
        child: Column(
          children: [
            WindowTitleBar(
              title: Text(strings.appName),
              trailing: ToolButton(
                icon: Icons.tune_rounded,
                tooltip: strings.settings,
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  services.flow,
                  services.settings,
                  services.hotkeys,
                ]),
                builder: (context, _) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _showPendingMessage(),
                  );
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 860;
                      const left = _CaptureColumn();
                      const right = _RecentColumn();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 11, child: left),
                                  const SizedBox(width: 28),
                                  const Expanded(flex: 8, child: right),
                                ],
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    left,
                                    const SizedBox(height: 24),
                                    right,
                                  ],
                                ),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureColumn extends StatelessWidget {
  const _CaptureColumn();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final strings = Strings.of(context);
    final settings = services.settings.settings;
    final flow = services.flow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const BrandMark(size: 52),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (rect) =>
                      AppColors.accentGradient.createShader(rect),
                  child: Text(
                    strings.appName,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                Text(
                  strings.tagline,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 26),
        if (flow.permissionMissing) ...[
          const _PermissionBanner(),
          const SizedBox(height: 16),
        ],
        for (final mode in CaptureMode.values) ...[
          _CaptureCard(
            mode: mode,
            hotKeyText: hotKeyLabel(settings.hotKeys[mode]),
            hotKeyFailed: services.hotkeys.failed.contains(mode),
            enabled: !flow.busy,
            onTap: () => flow.start(mode),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppColors.textFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.runsInBackground,
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        if (Platform.isLinux)
          FutureBuilder(
            future: services.native.platformInfo(),
            builder: (context, snapshot) {
              if (snapshot.data?.isWayland != true) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.waylandWarning,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _CaptureCard extends StatefulWidget {
  const _CaptureCard({
    required this.mode,
    required this.hotKeyText,
    required this.hotKeyFailed,
    required this.enabled,
    required this.onTap,
  });

  final CaptureMode mode;
  final String hotKeyText;
  final bool hotKeyFailed;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CaptureCard> createState() => _CaptureCardState();
}

class _CaptureCardState extends State<_CaptureCard> {
  bool _hover = false;

  IconData get _icon => switch (widget.mode) {
    CaptureMode.area => Icons.highlight_alt_rounded,
    CaptureMode.window => Icons.web_asset_rounded,
    CaptureMode.fullScreen => Icons.desktop_windows_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceRaised : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? AppColors.violet.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                      color: Color(0x337C5CFF),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _hover ? AppColors.accentGradient : null,
                  color: _hover ? null : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.modeName(widget.mode),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.modeDescription(widget.mode),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: widget.hotKeyFailed
                    ? strings.shortcutRegisterFailed
                    : '',
                child: Opacity(
                  opacity: widget.hotKeyFailed ? 0.4 : 1,
                  child: KeyCap(widget.hotKeyText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final native = AppScope.of(context).native;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                strings.permissionTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            strings.permissionBody,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              AccentButton(
                label: strings.permissionOpenSettings,
                compact: true,
                onPressed: native.openScreenAccessSettings,
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: strings.permissionRequest,
                compact: true,
                onPressed: native.requestScreenAccess,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentColumn extends StatelessWidget {
  const _RecentColumn();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final strings = Strings.of(context);
    final files = services.settings.settings.recentFiles
        .where((p) => File(p).existsSync())
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 12),
          child: SectionLabel(strings.recentCaptures),
        ),
        Expanded(
          child: files.isEmpty
              ? Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        color: AppColors.textFaint,
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        strings.noRecentCaptures,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: files.length,
                  itemBuilder: (context, index) =>
                      _RecentTile(path: files[index]),
                ),
        ),
      ],
    );
  }
}

class _RecentTile extends StatefulWidget {
  const _RecentTile({required this.path});

  final String path;

  @override
  State<_RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends State<_RecentTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final strings = Strings.of(context);
    final name = widget.path.split(Platform.pathSeparator).last;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => services.native.revealFile(widget.path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(widget.path),
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.surfaceRaised),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _hover ? 1 : 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC000000)],
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: strings.removeFromList,
                        child: InkWell(
                          onTap: () =>
                              services.settings.removeRecentFile(widget.path),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
