import 'package:flutter/material.dart';

import '../../core/app_icons.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/annotation.dart';
import '../widgets/common.dart';
import 'editor_controller.dart';

class _ToolSpec {
  const _ToolSpec(this.tool, this.icon, this.shortcut);
  final ToolType tool;
  final IconData icon;
  final String shortcut;
}

/// The rail's tools, in order, with icons of the current weight.
List<_ToolSpec> _toolSpecs(AppIcons i) => [
  _ToolSpec(ToolType.select, i.select, 'V'),
  _ToolSpec(ToolType.hand, i.hand, 'H'),
  _ToolSpec(ToolType.arrow, i.arrow, 'A'),
  // lineSegment is already drawn on the diagonal: no extra rotation.
  _ToolSpec(ToolType.line, i.line, 'L'),
  _ToolSpec(ToolType.rect, i.rect, 'R'),
  _ToolSpec(ToolType.ellipse, i.ellipse, 'E'),
  _ToolSpec(ToolType.pen, i.pen, 'P'),
  _ToolSpec(ToolType.marker, i.marker, 'M'),
  _ToolSpec(ToolType.text, i.text, 'T'),
  _ToolSpec(ToolType.number, i.number, 'N'),
  _ToolSpec(ToolType.blur, i.blur, 'B'),
  _ToolSpec(ToolType.stamp, i.stamp, 'S'),
  _ToolSpec(ToolType.ocr, i.ocr, 'O'),
];

String toolName(Strings strings, ToolType tool) => switch (tool) {
  ToolType.select => strings.toolSelect,
  ToolType.hand => strings.toolHand,
  ToolType.arrow => strings.toolArrow,
  ToolType.line => strings.toolLine,
  ToolType.rect => strings.toolRect,
  ToolType.ellipse => strings.toolEllipse,
  ToolType.pen => strings.toolPen,
  ToolType.marker => strings.toolMarker,
  ToolType.text => strings.toolText,
  ToolType.number => strings.toolNumber,
  ToolType.blur => strings.toolBlur,
  ToolType.stamp => strings.toolStamp,
  ToolType.ocr => strings.extractText,
};

/// Vertical floating tool palette.
class ToolRail extends StatelessWidget {
  const ToolRail({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final tools = _toolSpecs(AppIcons.of(context));
    return GlassPanel(
      padding: const EdgeInsets.all(6),
      radius: 14,
      // The rail is placed between a fixed top/bottom inset (see
      // editor_screen.dart), so it has a bounded max height but no fixed
      // one — this scrolls instead of overflowing once there isn't room for
      // every tool (small editor windows, or more tools added later),
      // while staying its natural shrink-wrapped size otherwise.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tools.length; i++) ...[
              if (i == 2 || i == 8) const _RailDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: _RailButton(
                  spec: tools[i],
                  label: toolName(strings, tools[i].tool),
                  active: controller.tool == tools[i].tool,
                  onPressed: () => controller.setTool(tools[i].tool),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.spec,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final _ToolSpec spec;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label  ·  ${spec.shortcut}',
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: active ? context.palette.accentGradient : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              spec.icon,
              size: AppIcons.railSize,
              color: active ? Colors.white : context.palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: context.palette.borderStrong,
    );
  }
}

/// Bottom floating bar: colors, stroke, opacity, fill and font size.
class PropertiesBar extends StatelessWidget {
  const PropertiesBar({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final icons = AppIcons.of(context);
    final style = controller.style;
    final tool = controller.tool;
    final selected = controller.selected;
    final targetIsShape = selected is ShapeAnnotation
        ? (selected.kind == ShapeKind.rect ||
              selected.kind == ShapeKind.ellipse)
        : (tool == ToolType.rect || tool == ToolType.ellipse);
    final targetIsText =
        selected is TextAnnotation ||
        tool == ToolType.text ||
        controller.isEditingText;
    final targetIsBlur = selected is ShapeAnnotation
        ? selected.kind == ShapeKind.blur
        : tool == ToolType.blur;
    final targetIsFreehand = selected is StrokeAnnotation
        ? true
        : selected == null && (tool == ToolType.pen || tool == ToolType.marker);
    final targetIsStamp = selected is StampAnnotation
        ? true
        : selected == null && tool == ToolType.stamp;
    final showColor = !targetIsBlur && !targetIsStamp && tool != ToolType.hand;
    final ratio = controller.pixelRatio;

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      radius: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showColor) ...[
            for (final color in AppColors.palette)
              _Swatch(
                color: color,
                selected: color.toARGB32() == style.color.toARGB32(),
                onTap: () => controller.setStyle(style.copyWith(color: color)),
              ),
            _CustomColorButton(
              color: style.color,
              isCustom: !AppColors.palette.any(
                (c) => c.toARGB32() == style.color.toARGB32(),
              ),
              onChanged: (c) => controller.setStyle(style.copyWith(color: c)),
            ),
            const _BarDivider(),
          ],
          if (targetIsStamp) ...[
            _LabeledSlider(
              icon: icons.strokeWidth,
              label: strings.brushSize,
              value: (style.brushSize / ratio).clamp(4, 200),
              min: 4,
              max: 200,
              display: '${(style.brushSize / ratio).round()}',
              onChanged: (v) => controller.setStyle(
                style.copyWith(brushSize: (v * ratio).roundToDouble()),
              ),
            ),
            const _BarDivider(),
            _LabeledSlider(
              icon: icons.blur,
              label: strings.hardness,
              value: style.hardness,
              min: 0,
              max: 1,
              display: '${(style.hardness * 100).round()}%',
              onChanged: (v) => controller.setStyle(
                style.copyWith(hardness: (v * 20).round() / 20),
              ),
            ),
          ] else
            _LabeledSlider(
              icon: icons.strokeWidth,
              label: targetIsBlur ? strings.toolBlur : strings.strokeWidth,
              value: (style.strokeWidth / ratio).clamp(1, 24),
              min: 1,
              max: 24,
              display: '${(style.strokeWidth / ratio).round()}',
              onChanged: (v) => controller.setStyle(
                style.copyWith(strokeWidth: (v * ratio).roundToDouble()),
              ),
            ),
          if (targetIsFreehand) ...[
            const _BarDivider(),
            _LabeledSlider(
              icon: icons.smoothing,
              label: strings.smoothing,
              value: style.smoothing,
              min: 0,
              max: 1,
              display: style.smoothing <= 0
                  ? strings.smoothingOff
                  : '${(style.smoothing * 100).round()}%',
              onChanged: (v) => controller.setStyle(
                style.copyWith(smoothing: (v * 20).round() / 20),
              ),
            ),
          ],
          if (!targetIsBlur) ...[
            const _BarDivider(),
            _LabeledSlider(
              icon: icons.opacity,
              label: strings.opacity,
              value: style.opacity,
              min: 0.1,
              max: 1,
              display: '${(style.opacity * 100).round()}%',
              onChanged: (v) => controller.setStyle(style.copyWith(opacity: v)),
            ),
          ],
          if (tool == ToolType.stamp &&
              selected == null &&
              !controller.hasStampSource) ...[
            const _BarDivider(),
            Text(
              strings.stampNoSourceHint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.palette.textMuted,
              ),
            ),
          ],
          if (targetIsShape) ...[
            const _BarDivider(),
            ToolButton(
              icon: style.filled ? icons.fill : icons.noFill,
              iconSize: AppIcons.buttonSize,
              tooltip: strings.fill,
              active: style.filled,
              size: 32,
              onPressed: () =>
                  controller.setStyle(style.copyWith(filled: !style.filled)),
            ),
          ],
          if (targetIsText) ...[
            const _BarDivider(),
            _LabeledSlider(
              icon: icons.fontSize,
              label: strings.fontSize,
              value: (style.fontSize / ratio).clamp(8, 96),
              min: 8,
              max: 96,
              display: '${(style.fontSize / ratio).round()}',
              onChanged: (v) => controller.setStyle(
                style.copyWith(fontSize: (v * ratio).roundToDouble()),
              ),
            ),
            const SizedBox(width: 8),
            _AlignSegmented(
              value: style.textAlign,
              labels: (
                strings.alignLeft,
                strings.alignCenter,
                strings.alignRight,
              ),
              onChanged: (a) =>
                  controller.setStyle(style.copyWith(textAlign: a)),
            ),
          ],
          if (selected != null) ...[
            const _BarDivider(),
            ToolButton(
              icon: icons.delete,
              iconSize: AppIcons.buttonSize,
              tooltip: strings.delete,
              shortcut: 'Del',
              size: 32,
              danger: true,
              onPressed: controller.deleteSelected,
            ),
          ],
        ],
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: context.palette.borderStrong,
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 22,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.25),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({
    required this.color,
    required this.isCustom,
    required this.onChanged,
  });

  final Color color;
  final bool isCustom;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    return Tooltip(
      message: strings.color,
      child: GestureDetector(
        onTap: () async {
          final picked = await showDialog<Color>(
            context: context,
            builder: (context) => _ColorPickerDialog(initial: color),
          );
          if (picked != null) onChanged(picked);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFFF3B5C),
                  Color(0xFFFFE156),
                  Color(0xFF34D399),
                  Color(0xFF3B82F6),
                  Color(0xFFF472B6),
                  Color(0xFFFF3B5C),
                ],
              ),
              border: Border.all(
                color: isCustom
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.25),
                width: isCustom ? 2.5 : 1,
              ),
            ),
            child: isCustom
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                  )
                : Icon(
                    AppIcons.of(context).add,
                    size: AppIcons.tinySize,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AppIcons.inlineSize,
            color: context.palette.textMuted,
          ),
          SizedBox(
            width: 110,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              display,
              style: TextStyle(
                fontSize: 11.5,
                color: context.palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zoom in/out/fit controls.
class ZoomControls extends StatelessWidget {
  const ZoomControls({
    super.key,
    required this.controller,
    required this.viewportSize,
  });

  final EditorController controller;
  final Size Function() viewportSize;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final icons = AppIcons.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      radius: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolButton(
            icon: icons.remove,
            iconSize: AppIcons.buttonSize,
            tooltip: strings.zoomOut,
            size: 30,
            onPressed: () => controller.zoomBy(0.8, viewportSize()),
          ),
          Tooltip(
            message: strings.zoomActual,
            child: InkWell(
              onTap: () => controller.actualSize(viewportSize()),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 52,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${(controller.zoom * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
          ToolButton(
            icon: icons.add,
            iconSize: AppIcons.buttonSize,
            tooltip: strings.zoomIn,
            size: 30,
            onPressed: () => controller.zoomBy(1.25, viewportSize()),
          ),
          ToolButton(
            icon: icons.fitScreen,
            iconSize: AppIcons.buttonSize,
            tooltip: strings.zoomFit,
            size: 30,
            onPressed: () => controller.fitTo(viewportSize()),
          ),
        ],
      ),
    );
  }
}

/// Minimal HSV color picker.
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(widget.initial),
  );

  String _hexOf(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  void _update(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hex.text = _hexOf(hsv.toColor());
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(strings.color),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SaturationValueBox(hsv: _hsv, onChanged: _update),
            const SizedBox(height: 12),
            _HueSlider(
              hue: _hsv.hue,
              onChanged: (h) => _update(_hsv.withHue(h)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.palette.borderStrong),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(
                      prefixText: '#',
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    onChanged: (value) {
                      final clean = value.replaceAll('#', '');
                      if (clean.length == 6) {
                        final parsed = int.tryParse(clean, radix: 16);
                        if (parsed != null) {
                          setState(
                            () => _hsv = HSVColor.fromColor(
                              Color(0xFF000000 | parsed),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        AccentButton(
          label: strings.done,
          compact: true,
          onPressed: () => Navigator.pop(context, color),
        ),
      ],
    );
  }
}

class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _handle(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 160);
        return GestureDetector(
          onPanDown: (d) => _handle(d.localPosition, size),
          onPanUpdate: (d) => _handle(d.localPosition, size),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hsv.saturation * size.width - 7,
                  top: (1 - hsv.value) * size.height - 7,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void handle(Offset local) =>
            onChanged((local.dx / width).clamp(0.0, 1.0) * 360);
        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            height: 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(
                        colors: [
                          for (var i = 0; i <= 6; i++)
                            HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hue / 360 * width - 9,
                  top: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Compact left/center/right segmented control for text alignment.
class _AlignSegmented extends StatelessWidget {
  const _AlignSegmented({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final TextAlign value;
  final (String, String, String) labels;
  final ValueChanged<TextAlign> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, TextAlign align) {
      return ToolButton(
        icon: icon,
        iconSize: AppIcons.buttonSize,
        tooltip: tooltip,
        active: value == align,
        size: 32,
        onPressed: () => onChanged(align),
      );
    }

    final icons = AppIcons.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(icons.alignLeft, labels.$1, TextAlign.left),
        button(icons.alignCenter, labels.$2, TextAlign.center),
        button(icons.alignRight, labels.$3, TextAlign.right),
      ],
    );
  }
}
