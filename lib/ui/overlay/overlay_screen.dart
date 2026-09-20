import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../debug/debug_server.dart';
import '../../flow/capture_flow.dart';
import '../../models/app_settings.dart';
import '../../models/capture_mode.dart';
import '../../models/capture_session.dart';
import '../../models/window_info.dart';
import '../widgets/common.dart';
import 'overlay_painter.dart';

enum _DragKind { create, move, resize }

/// Full-screen selection UI drawn over the frozen screenshot.
class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  final _focusNode = FocusNode();

  Offset? _cursor;
  Rect? _selection;
  WindowInfo? _hoverWindow;

  _DragKind? _drag;
  Offset? _anchor;
  Rect? _dragOriginal;
  int _handleIndex = -1;
  bool _moved = false;
  bool _completing = false;

  static const _handleHitRadius = 9.0;
  static const _magnifierSize = 132.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
    DebugHooks.overlaySelect = (rect) => setState(() {
      _selection = rect;
      _hoverWindow = null;
    });
    DebugHooks.overlayConfirm = _finish;
    DebugHooks.overlayHover = (point) => setState(() {
      _cursor = point;
      _hoverWindow = _selection == null ? _session?.windowAt(point) : null;
    });
  }

  @override
  void dispose() {
    DebugHooks.overlaySelect = null;
    DebugHooks.overlayConfirm = null;
    DebugHooks.overlayHover = null;
    _focusNode.dispose();
    super.dispose();
  }

  CaptureSession? get _session => AppScope.of(context).flow.session;

  /// True while the overlay is a pure window picker: no magnifier, crosshair
  /// or precision cursor make sense here since the whole window is the
  /// target, not a pixel — the camera badge replaces the system cursor.
  bool get _isWindowPickPhase =>
      _session?.mode == CaptureMode.window && _selection == null;

  // ---------------------------------------------------------------------------
  // Pointer handling
  // ---------------------------------------------------------------------------

  Rect _clamp(Rect rect, Size size) {
    final full = Offset.zero & size;
    return rect.intersect(full);
  }

  int _hitHandle(Offset p) {
    final sel = _selection;
    if (sel == null) return -1;
    final handles = OverlayPainter.handlesFor(sel);
    for (var i = 0; i < handles.length; i++) {
      if ((handles[i] - p).distance <= _handleHitRadius) return i;
    }
    return -1;
  }

  void _onHover(PointerHoverEvent event) {
    if (_completing) return;
    setState(() {
      _cursor = event.localPosition;
      _hoverWindow = _selection == null
          ? _session?.windowAt(event.localPosition)
          : null;
    });
  }

  void _onDown(PointerDownEvent event) {
    if (_completing) return;
    _focusNode.requestFocus();
    final p = event.localPosition;
    if (event.buttons == kSecondaryMouseButton) {
      if (_selection != null) {
        setState(() {
          _selection = null;
          _hoverWindow = _session?.windowAt(p);
        });
      } else {
        _finish(OverlayAction.cancel);
      }
      return;
    }
    if (event.buttons != kPrimaryMouseButton) return;

    final handle = _hitHandle(p);
    setState(() {
      _cursor = p;
      _moved = false;
      _anchor = p;
      if (handle >= 0) {
        _drag = _DragKind.resize;
        _handleIndex = handle;
        _dragOriginal = _selection;
      } else if (_selection != null && _selection!.contains(p)) {
        _drag = _DragKind.move;
        _dragOriginal = _selection;
      } else {
        _drag = _DragKind.create;
        _selection = null;
        _hoverWindow = _session?.windowAt(p);
      }
    });
  }

  void _onMove(PointerMoveEvent event) {
    if (_drag == null || _anchor == null || _completing) return;
    final p = event.localPosition;
    final size = context.size ?? Size.zero;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if ((p - _anchor!).distance > 3) _moved = true;

    final isWindowMode = _session?.mode == CaptureMode.window;
    setState(() {
      _cursor = p;
      switch (_drag!) {
        case _DragKind.create:
          if (isWindowMode) {
            // Window mode is a picker, not a free-form area selector: keep
            // the hover highlight following the cursor and never build an
            // arbitrary rectangle, even if the click wobbles a few pixels.
            _hoverWindow = _session?.windowAt(p);
            return;
          }
          if (!_moved) return;
          var end = p;
          if (shift) {
            final d = math.max(
              (p.dx - _anchor!.dx).abs(),
              (p.dy - _anchor!.dy).abs(),
            );
            end = Offset(
              _anchor!.dx + d * (p.dx >= _anchor!.dx ? 1 : -1),
              _anchor!.dy + d * (p.dy >= _anchor!.dy ? 1 : -1),
            );
          }
          _selection = _clamp(Rect.fromPoints(_anchor!, end), size);
          _hoverWindow = null;
        case _DragKind.move:
          final original = _dragOriginal!;
          var moved = original.shift(p - _anchor!);
          final dx = moved.left < 0
              ? -moved.left
              : moved.right > size.width
              ? size.width - moved.right
              : 0.0;
          final dy = moved.top < 0
              ? -moved.top
              : moved.bottom > size.height
              ? size.height - moved.bottom
              : 0.0;
          moved = moved.shift(Offset(dx, dy));
          _selection = moved;
        case _DragKind.resize:
          _selection = _clamp(_resized(_dragOriginal!, _handleIndex, p), size);
      }
    });
  }

  Rect _resized(Rect original, int handle, Offset p) {
    var left = original.left,
        top = original.top,
        right = original.right,
        bottom = original.bottom;
    switch (handle) {
      case 0:
        left = p.dx;
        top = p.dy;
      case 1:
        top = p.dy;
      case 2:
        right = p.dx;
        top = p.dy;
      case 3:
        right = p.dx;
      case 4:
        right = p.dx;
        bottom = p.dy;
      case 5:
        bottom = p.dy;
      case 6:
        left = p.dx;
        bottom = p.dy;
      case 7:
        left = p.dx;
    }
    return Rect.fromPoints(Offset(left, top), Offset(right, bottom));
  }

  void _onUp(PointerUpEvent event) {
    if (_drag == null || _completing) return;
    final isWindowMode = _session?.mode == CaptureMode.window;
    setState(() {
      // Window mode always resolves to the window under the cursor, even if
      // the click wobbled past the "did it drag" threshold. Area mode only
      // does this for a genuinely un-dragged (plain) click.
      if (_drag == _DragKind.create && (isWindowMode || !_moved)) {
        final window = _session?.windowAt(event.localPosition);
        if (window != null) {
          _selection = window.bounds;
          _hoverWindow = null;
        }
      }
      if (_selection != null &&
          (_selection!.width < 3 || _selection!.height < 3)) {
        _selection = null;
      }
      if (_selection == null) {
        _hoverWindow = _session?.windowAt(event.localPosition);
      }
      _drag = null;
      _anchor = null;
      _dragOriginal = null;
      _handleIndex = -1;
      _moved = false;
    });
  }

  MouseCursor _cursorFor(Offset? p) {
    if (_isWindowPickPhase) return SystemMouseCursors.none;
    if (p == null || _selection == null) return SystemMouseCursors.precise;
    if (_drag == _DragKind.move) return SystemMouseCursors.grabbing;
    final handle = _drag == _DragKind.resize ? _handleIndex : _hitHandle(p);
    switch (handle) {
      case 0:
      case 4:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case 2:
      case 6:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case 1:
      case 5:
        return SystemMouseCursors.resizeUpDown;
      case 3:
      case 7:
        return SystemMouseCursors.resizeLeftRight;
    }
    if (_selection!.contains(p)) return SystemMouseCursors.move;
    return SystemMouseCursors.precise;
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final command = Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final size = context.size ?? Size.zero;

    if (key == LogicalKeyboardKey.escape) {
      _finish(OverlayAction.cancel);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _confirmDefault();
    } else if (key == LogicalKeyboardKey.space) {
      setState(() {
        _selection = Offset.zero & size;
        _hoverWindow = null;
      });
    } else if (command && key == LogicalKeyboardKey.keyC) {
      _finish(OverlayAction.copy);
    } else if (command && key == LogicalKeyboardKey.keyS) {
      _finish(OverlayAction.save);
    } else if (command && key == LogicalKeyboardKey.keyE) {
      _finish(OverlayAction.edit);
    } else if (_selection != null && _isArrow(key)) {
      final step = keyboard.isShiftPressed ? 10.0 : 1.0;
      final delta = switch (key) {
        LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
        LogicalKeyboardKey.arrowRight => Offset(step, 0),
        LogicalKeyboardKey.arrowUp => Offset(0, -step),
        _ => Offset(0, step),
      };
      setState(() => _selection = _clamp(_selection!.shift(delta), size));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool _isArrow(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown;

  void _confirmDefault() {
    final action = AppScope.of(context).settings.settings.afterCaptureAction;
    _finish(switch (action) {
      AfterCaptureAction.openEditor => OverlayAction.edit,
      AfterCaptureAction.copyToClipboard => OverlayAction.copy,
      AfterCaptureAction.saveToFile => OverlayAction.save,
    });
  }

  void _finish(OverlayAction action) {
    if (_completing) return;
    _completing = true;
    final size = context.size ?? Size.zero;
    final rect = action == OverlayAction.cancel
        ? null
        : (_selection ?? (Offset.zero & size));
    AppScope.of(context).flow.completeOverlay(OverlayResult(action, rect));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final session = services.flow.session;
    final strings = Strings.of(context);
    if (session == null) {
      return const ColoredBox(color: Colors.black);
    }
    final showMagnifier = services.settings.settings.showMagnifier;
    final dragging = _drag != null;
    final isWindowPickPhase = _isWindowPickPhase;
    final magnifierVisible =
        showMagnifier &&
        !isWindowPickPhase &&
        _cursor != null &&
        (_selection == null ||
            _drag == _DragKind.create ||
            _drag == _DragKind.resize);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return MouseRegion(
            cursor: _cursorFor(_cursor),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Pointer handling lives on its own layer, below the floating
                // UI (action bar, hint, magnifier). A `Listener` reports every
                // raw pointer event that lands within its bounds even when a
                // descendant widget (like a toolbar button) already handled
                // it — so the toolbar must be a *sibling*, not a child, or
                // every click on it would also start a new selection here.
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerHover: _onHover,
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: RawImage(
                          image: session.image,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                      ),
                      CustomPaint(
                        painter: OverlayPainter(
                          selection: _selection,
                          hoverWindow: _hoverWindow,
                          cursor: _cursor,
                          pixelRatio: session.pixelRatio,
                          dragging: dragging,
                          showHandles: _selection != null && !dragging,
                          showCrosshair: !isWindowPickPhase,
                        ),
                      ),
                    ],
                  ),
                ),
                if (magnifierVisible) _buildMagnifier(session, size),
                if (isWindowPickPhase && _cursor != null) _buildCameraCursor(),
                _buildHint(strings, session.mode, size),
                if (_selection != null && !dragging)
                  _buildActionBar(strings, size),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMagnifier(CaptureSession session, Size size) {
    final cursor = _cursor!;
    const gap = 22.0;
    const labelHeight = 26.0;
    var left = cursor.dx + gap;
    var top = cursor.dy + gap;
    if (left + _magnifierSize > size.width - 8) {
      left = cursor.dx - gap - _magnifierSize;
    }
    if (top + _magnifierSize + labelHeight > size.height - 8) {
      top = cursor.dy - gap - _magnifierSize - labelHeight;
    }
    final px = (cursor.dx * session.pixelRatio).round();
    final py = (cursor.dy * session.pixelRatio).round();
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _magnifierSize,
              height: _magnifierSize,
              child: CustomPaint(
                painter: MagnifierPainter(
                  image: session.image,
                  cursor: cursor,
                  pixelRatio: session.pixelRatio,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xE6161A2B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.palette.border),
              ),
              child: Text(
                '$px, $py',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Replaces the system cursor while picking a window: a small camera
  /// badge that tracks the pointer, since the precision crosshair/magnifier
  /// don't make sense when the whole window — not a pixel — is the target.
  Widget _buildCameraCursor() {
    final p = _cursor!;
    return Positioned(
      left: p.dx + 14,
      top: p.dy + 14,
      child: IgnorePointer(
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: context.palette.accentGradient,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.photo_camera_rounded,
            size: 15,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildHint(Strings strings, CaptureMode mode, Size size) {
    final visible = _selection == null && _drag == null;
    final isWindowMode = mode == CaptureMode.window;
    final primary = isWindowMode ? strings.hintClickWindow : strings.hintDrag;
    // Window mode never drags a rectangle, so the "click a window" tip only
    // makes sense as a secondary hint in area mode.
    final secondary = isWindowMode ? null : strings.hintClickWindow;
    // Keep the hint away from the cursor so it never blocks the target.
    final nearTop = _cursor != null && _cursor!.dy < 120;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      top: nearTop ? null : 24,
      bottom: nearTop ? 24 : null,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: Center(
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              radius: 14,
              blur: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isWindowMode
                        ? Icons.web_asset_rounded
                        : Icons.highlight_alt_rounded,
                    size: 16,
                    color: AppColors.cyan,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    primary,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (secondary != null) ...[
                    _dot(),
                    Text(
                      secondary,
                      style: TextStyle(
                        color: context.palette.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  _dot(),
                  const KeyCap('Space', light: true),
                  const SizedBox(width: 6),
                  Text(
                    strings.hintSpace,
                    style: TextStyle(
                      color: context.palette.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  _dot(),
                  const KeyCap('Esc', light: true),
                  const SizedBox(width: 6),
                  Text(
                    strings.hintEsc,
                    style: TextStyle(
                      color: context.palette.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot() => Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: Text('·', style: TextStyle(color: context.palette.textFaint)),
  );

  Widget _buildActionBar(Strings strings, Size size) {
    final sel = _selection!;
    const barHeight = 44.0;
    // The bar sizes itself to its content (see `mainAxisSize.min` below); this
    // is only an estimate used to keep it from being positioned off-screen.
    const estimatedWidth = 200.0;
    const gap = 10.0;
    double top;
    if (sel.bottom + gap + barHeight <= size.height - 8) {
      top = sel.bottom + gap;
    } else if (sel.top - gap - barHeight >= 8) {
      top = sel.top - gap - barHeight;
    } else {
      top = sel.bottom - gap - barHeight;
    }
    final left = (sel.right - estimatedWidth)
        .clamp(8.0, math.max(8.0, size.width - estimatedWidth - 8))
        .toDouble();
    final command = Platform.isMacOS ? '⌘' : 'Ctrl+';

    return Positioned(
      left: left,
      top: top,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        radius: 14,
        blur: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToolButton(
              icon: Icons.close_rounded,
              tooltip: strings.cancel,
              shortcut: 'Esc',
              onPressed: () => _finish(OverlayAction.cancel),
              danger: true,
            ),
            const SizedBox(width: 2),
            ToolButton(
              icon: Icons.save_alt_rounded,
              tooltip: strings.save,
              shortcut: '${command}S',
              onPressed: () => _finish(OverlayAction.save),
            ),
            const SizedBox(width: 2),
            ToolButton(
              icon: Icons.copy_rounded,
              tooltip: strings.copy,
              shortcut: '${command}C',
              onPressed: () => _finish(OverlayAction.copy),
            ),
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: context.palette.borderStrong,
            ),
            ToolButton(
              icon: Icons.brush_rounded,
              tooltip: strings.edit,
              shortcut: '${command}E',
              active: true,
              onPressed: () => _finish(OverlayAction.edit),
            ),
          ],
        ),
      ),
    );
  }
}
