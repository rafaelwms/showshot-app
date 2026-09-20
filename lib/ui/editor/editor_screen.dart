import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../debug/debug_server.dart';
import '../../flow/capture_flow.dart';
import '../../models/annotation.dart';
import '../../services/export_service.dart';
import '../widgets/common.dart';
import 'editor_canvas.dart';
import 'editor_controller.dart';
import 'editor_panels.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorController? _controller;
  final _focusNode = FocusNode();
  final _viewportKey = GlobalKey();
  bool _fitted = false;
  bool _busy = false;
  bool _wasEditingText = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final document = AppScope.of(context).flow.document;
    if (document != null &&
        (_controller == null || _controller!.image != document.image)) {
      _controller?.dispose();
      _controller = EditorController(
        image: document.image,
        pixelRatio: document.pixelRatio,
      );
      DebugHooks.editor = _controller;
      DebugHooks.editorAction = (action) => switch (action) {
        'copy' => _copy(),
        'discard' => _discard(),
        'saveAs' => _save(forceDialog: true),
        _ => _save(),
      };
      _fitted = false;
      if (document.autoSave) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _save(forceDialog: true),
        );
      }
    }
  }

  @override
  void dispose() {
    if (DebugHooks.editor == _controller) {
      DebugHooks.editor = null;
      DebugHooks.editorAction = null;
    }
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Size get _viewportSize =>
      _viewportKey.currentContext?.size ?? const Size(800, 600);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<ui.Image> _renderFinal() async {
    final controller = _controller!;
    controller.commitTextEditing();
    return ExportService.render(controller.image, controller.exportable);
  }

  Future<void> _copy() async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final strings = Strings.of(context);
    try {
      final image = await _renderFinal();
      final ok = await services.export.copyToClipboard(image);
      image.dispose();
      if (!mounted) return;
      _toast(ok ? strings.copied : strings.saveFailed);
      if (ok) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await services.flow.closeEditor(
          message: const FlowMessage(FlowMessageKind.copied),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({bool forceDialog = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final strings = Strings.of(context);
    try {
      final image = await _renderFinal();
      final path = await services.export.save(
        image,
        services.settings.settings,
        forceDialog: forceDialog,
      );
      if (path != null) {
        await services.settings.addRecentFile(path);
        if (services.settings.settings.copyAfterSave) {
          await services.export.copyToClipboard(image);
        }
      }
      image.dispose();
      if (!mounted || path == null) return;
      _toast(strings.savedTo(path));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await services.flow.closeEditor(
        message: FlowMessage(FlowMessageKind.saved, path: path),
      );
    } catch (error) {
      if (mounted) _toast(strings.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final controller = _controller!;
    final strings = Strings.of(context);
    if (controller.hasAnnotations) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.discardConfirmTitle),
          content: Text(strings.discardConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.keepEditing),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(strings.discard),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    await AppScope.of(context).flow.closeEditor();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final controller = _controller;
    if (controller == null) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space && !controller.isEditingText) {
      if (event is KeyDownEvent) controller.setSpaceHeld(true);
      if (event is KeyUpEvent) controller.setSpaceHeld(false);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (controller.isEditingText) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    final command = Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;

    if (command) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? controller.redo() : controller.undo();
      } else if (key == LogicalKeyboardKey.keyY) {
        controller.redo();
      } else if (key == LogicalKeyboardKey.keyC) {
        _copy();
      } else if (key == LogicalKeyboardKey.keyS) {
        _save(forceDialog: shift);
      } else if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add) {
        controller.zoomBy(1.25, _viewportSize);
      } else if (key == LogicalKeyboardKey.minus) {
        controller.zoomBy(0.8, _viewportSize);
      } else if (key == LogicalKeyboardKey.digit0) {
        controller.fitTo(_viewportSize);
      } else if (key == LogicalKeyboardKey.digit1) {
        controller.actualSize(_viewportSize);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (controller.selectedId != null) {
        controller.selectAnnotation(null);
      } else {
        _discard();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      controller.deleteSelected();
      return KeyEventResult.handled;
    }

    final tool = switch (key) {
      LogicalKeyboardKey.keyV => ToolType.select,
      LogicalKeyboardKey.keyH => ToolType.hand,
      LogicalKeyboardKey.keyA => ToolType.arrow,
      LogicalKeyboardKey.keyL => ToolType.line,
      LogicalKeyboardKey.keyR => ToolType.rect,
      LogicalKeyboardKey.keyE => ToolType.ellipse,
      LogicalKeyboardKey.keyP => ToolType.pen,
      LogicalKeyboardKey.keyM => ToolType.marker,
      LogicalKeyboardKey.keyT => ToolType.text,
      LogicalKeyboardKey.keyN => ToolType.number,
      LogicalKeyboardKey.keyB => ToolType.blur,
      _ => null,
    };
    if (tool != null) {
      controller.setTool(tool);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final strings = Strings.of(context);
    if (controller == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            // Shortcuts live on the screen's focus node; take it back once an
            // inline text editor closes.
            if (_wasEditingText && !controller.isEditingText) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_focusNode.hasFocus) _focusNode.requestFocus();
              });
            }
            _wasEditingText = controller.isEditingText;
            return Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.4),
                        radius: 1.4,
                        colors: [context.palette.surface, context.palette.bg],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 44),
                      child: _buildViewport(controller),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _buildTitleBar(controller, strings),
                ),
                Positioned(
                  left: 14,
                  top: 64,
                  bottom: 84,
                  child: Center(child: ToolRail(controller: controller)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Center(child: PropertiesBar(controller: controller)),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: ZoomControls(
                    controller: controller,
                    viewportSize: () => _viewportSize,
                  ),
                ),
                if (_busy)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Color(0x33000000),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.cyan,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTitleBar(EditorController controller, Strings strings) {
    final command = Platform.isMacOS ? '⌘' : 'Ctrl+';
    return Container(
      color: context.palette.bg.withValues(alpha: 0.85),
      child: WindowTitleBar(
        onClose: _discard,
        leading: const BrandMark(size: 20),
        title: Text(
          '${strings.editorTitle}  ·  ${controller.image.width} × ${controller.image.height}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToolButton(
              icon: Icons.undo_rounded,
              tooltip: strings.undo,
              shortcut: '${command}Z',
              onPressed: controller.canUndo ? controller.undo : null,
              size: 32,
            ),
            ToolButton(
              icon: Icons.redo_rounded,
              tooltip: strings.redo,
              shortcut: '$command⇧Z',
              onPressed: controller.canRedo ? controller.redo : null,
              size: 32,
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: '',
              icon: Icon(
                Icons.more_horiz_rounded,
                color: context.palette.textMuted,
                size: 20,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'saveAs':
                    _save(forceDialog: true);
                  case 'clear':
                    controller.clearAll();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'saveAs',
                  child: Text('${strings.saveAs}  ($command⇧S)'),
                ),
                PopupMenuItem(value: 'clear', child: Text(strings.clearAll)),
              ],
            ),
            const SizedBox(width: 6),
            GhostButton(
              label: strings.discard,
              compact: true,
              danger: true,
              onPressed: _discard,
            ),
            const SizedBox(width: 8),
            GhostButton(
              label: strings.copyToClipboard,
              icon: Icons.copy_rounded,
              compact: true,
              onPressed: _copy,
            ),
            const SizedBox(width: 8),
            AccentButton(
              label: strings.saveToFile,
              icon: Icons.save_alt_rounded,
              compact: true,
              onPressed: () => _save(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewport(EditorController controller) {
    return LayoutBuilder(
      key: _viewportKey,
      builder: (context, constraints) {
        if (!_fitted && constraints.biggest.width > 0) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => controller.fitTo(constraints.biggest),
          );
        }
        return Listener(
          // Two-finger trackpad scroll pans even while a drawing tool is active.
          onPointerSignal: (event) {
            if (event is PointerScrollEvent &&
                event.kind == PointerDeviceKind.trackpad &&
                !controller.panEnabled) {
              final matrix = controller.transformation.value.clone()
                ..leftTranslateByDouble(
                  -event.scrollDelta.dx,
                  -event.scrollDelta.dy,
                  0,
                  1,
                );
              controller.transformation.value = matrix;
            }
          },
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: controller.transformation,
              panEnabled: controller.panEnabled,
              scaleEnabled: true,
              constrained: false,
              minScale: 0.05,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: _EditorCanvas(controller: controller),
            ),
          ),
        );
      },
    );
  }
}

/// The image-sized canvas placed inside the InteractiveViewer.
class _EditorCanvas extends StatefulWidget {
  const _EditorCanvas({required this.controller});

  final EditorController controller;

  @override
  State<_EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<_EditorCanvas> {
  Offset? _hover;

  EditorController get controller => widget.controller;

  MouseCursor _cursor() {
    if (controller.panEnabled) return SystemMouseCursors.grab;
    switch (controller.tool) {
      case ToolType.select:
        final p = _hover;
        if (p != null && controller.isOverHandle(p)) {
          return SystemMouseCursors.precise;
        }
        if (p != null && controller.isOverAnnotation(p)) {
          return SystemMouseCursors.move;
        }
        return SystemMouseCursors.basic;
      case ToolType.text:
        return SystemMouseCursors.text;
      case ToolType.hand:
        return SystemMouseCursors.grab;
      default:
        return SystemMouseCursors.precise;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = controller.imageSize;
    final editing = controller.editingText;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: MouseRegion(
        cursor: _cursor(),
        onHover: (event) {
          if (controller.tool == ToolType.select) {
            setState(() => _hover = event.localPosition);
          }
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (event.buttons != kPrimaryMouseButton) return;
            controller.pointerDown(event.localPosition);
          },
          onPointerMove: (event) => controller.pointerMove(
            event.localPosition,
            shift: HardwareKeyboard.instance.isShiftPressed,
          ),
          onPointerUp: (event) => controller.pointerUp(event.localPosition),
          onPointerCancel: (event) => controller.pointerUp(event.localPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: EditorCanvasPainter(
                      image: controller.image,
                      annotations: controller.paintable,
                      selected: controller.selected,
                      zoom: controller.zoom,
                      repaint: controller.transformation,
                    ),
                  ),
                ),
              ),
              if (editing != null)
                Positioned(
                  left: editing.position.dx - 6,
                  top: editing.position.dy - 6,
                  child: _TextEditorBox(
                    key: ValueKey(editing.id),
                    annotation: editing,
                    maxWidth: (size.width - editing.position.dx + 6).clamp(
                      120.0,
                      size.width,
                    ),
                    onChanged: controller.updateEditingText,
                    onCommit: controller.commitTextEditing,
                    onCancel: controller.cancelTextEditing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextEditorBox extends StatefulWidget {
  const _TextEditorBox({
    super.key,
    required this.annotation,
    required this.maxWidth,
    required this.onChanged,
    required this.onCommit,
    required this.onCancel,
  });

  final TextAnnotation annotation;
  final double maxWidth;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onCancel;

  @override
  State<_TextEditorBox> createState() => _TextEditorBoxState();
}

class _TextEditorBoxState extends State<_TextEditorBox> {
  late final TextEditingController _text = TextEditingController(
    text: widget.annotation.text,
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      widget.onCommit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.annotation.style;
    final strings = Strings.of(context);
    return Focus(
      onKeyEvent: _onKey,
      child: Container(
        constraints: BoxConstraints(minWidth: 80, maxWidth: widget.maxWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.cyan, width: 1.5),
          color: Colors.black.withValues(alpha: 0.15),
        ),
        child: IntrinsicWidth(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            maxLines: null,
            cursorColor: AppColors.cyan,
            style: TextAnnotation.textStyle(style),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.all(6),
              hintText: strings.textPlaceholder,
              hintStyle: TextAnnotation.textStyle(style.copyWith(opacity: 0.4)),
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}
