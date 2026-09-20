import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';

/// Rounded, translucent panel used for floating toolbars.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
    this.radius = 16,
    this.color,
    this.blur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (!blur) return body;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: body,
      ),
    );
  }
}

/// Square icon button with tooltip, optional active state and keyboard hint.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.shortcut,
    this.size = 36,
    this.iconSize = 19,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final String? shortcut;
  final double size;
  final double iconSize;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = !enabled
        ? AppColors.textFaint
        : danger
        ? AppColors.danger
        : active
        ? Colors.white
        : AppColors.textMuted;
    return Tooltip(
      message: shortcut == null ? tooltip : '$tooltip  ·  $shortcut',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: active ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      ),
    );
  }
}

/// Primary call-to-action with the accent gradient.
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x557C5CFF),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 18,
              vertical: compact ? 8 : 11,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary, outlined button.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: danger
                  ? AppColors.danger.withValues(alpha: 0.5)
                  : AppColors.borderStrong,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 8 : 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small key-cap style label for shortcut hints.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.light = false});

  final String label;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Custom window chrome: draggable area, title and (non-macOS) window buttons.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({
    super.key,
    this.title,
    this.leading,
    this.trailing,
    this.height = 44,
    this.onClose,
  });

  final Widget? title;
  final Widget? leading;
  final Widget? trailing;
  final double height;

  /// Overrides the default close behaviour (hide window).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: isMac ? 80 : 14, right: 8),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                if (title != null)
                  DefaultTextStyle(
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    child: title!,
                  ),
                const Spacer(),
                ?trailing,
                if (!isMac) ...[
                  const SizedBox(width: 8),
                  _WindowButton(
                    icon: Icons.remove_rounded,
                    onTap: () => windowManager.minimize(),
                  ),
                  _WindowButton(
                    icon: Icons.crop_square_rounded,
                    onTap: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                  _WindowButton(
                    icon: Icons.close_rounded,
                    danger: true,
                    onTap: onClose ?? () => windowManager.close(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: danger
            ? AppColors.danger.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.08),
        child: SizedBox(
          width: 34,
          height: 30,
          child: Icon(icon, size: 16, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// Section label used across home and settings.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textFaint,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// The Show Shot mark: viewfinder brackets with a lens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/app_icon_256.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
