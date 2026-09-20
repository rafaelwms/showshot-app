import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../services/hotkey_service.dart';

/// Click-to-record shortcut field.
class HotkeyField extends StatefulWidget {
  const HotkeyField({
    super.key,
    required this.value,
    required this.identifier,
    required this.onChanged,
    required this.onRecordingChanged,
    this.failed = false,
  });

  final HotKey? value;
  final String identifier;
  final ValueChanged<HotKey?> onChanged;
  final ValueChanged<bool> onRecordingChanged;
  final bool failed;

  @override
  State<HotkeyField> createState() => _HotkeyFieldState();
}

class _HotkeyFieldState extends State<HotkeyField> {
  final _focusNode = FocusNode();
  bool _recording = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setRecording(bool value) {
    if (_recording == value) return;
    setState(() => _recording = value);
    widget.onRecordingChanged(value);
  }

  static final _modifierKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_recording || event is! KeyDownEvent) return KeyEventResult.ignored;
    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.escape) {
      _setRecording(false);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.backspace ||
        logical == LogicalKeyboardKey.delete) {
      widget.onChanged(null);
      _setRecording(false);
      return KeyEventResult.handled;
    }
    if (_modifierKeys.contains(logical)) return KeyEventResult.handled;

    final pressed = HardwareKeyboard.instance;
    final modifiers = <HotKeyModifier>[
      if (pressed.isControlPressed) HotKeyModifier.control,
      if (pressed.isShiftPressed) HotKeyModifier.shift,
      if (pressed.isAltPressed) HotKeyModifier.alt,
      if (pressed.isMetaPressed) HotKeyModifier.meta,
    ];
    final isFunctionKey =
        logical.keyId >= LogicalKeyboardKey.f1.keyId &&
        logical.keyId <= LogicalKeyboardKey.f24.keyId;
    if (modifiers.isEmpty &&
        !isFunctionKey &&
        logical != LogicalKeyboardKey.printScreen) {
      // Refuse plain keys: they would hijack normal typing system-wide.
      return KeyEventResult.handled;
    }
    widget.onChanged(
      HotKey(
        identifier: widget.identifier,
        key: event.physicalKey,
        modifiers: modifiers,
      ),
    );
    _setRecording(false);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final label = _recording ? strings.pressKeys : hotKeyLabel(widget.value);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        if (!focused) _setRecording(false);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: widget.failed
                ? strings.shortcutRegisterFailed
                : strings.recordShortcut,
            child: GestureDetector(
              onTap: () {
                _focusNode.requestFocus();
                _setRecording(true);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minWidth: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _recording
                      ? AppColors.violet.withValues(alpha: 0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _recording
                        ? AppColors.violet
                        : widget.failed
                        ? AppColors.danger
                        : AppColors.borderStrong,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.failed && !_recording) ...[
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _recording ? AppColors.violet : AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: strings.clearShortcut,
            visualDensity: VisualDensity.compact,
            onPressed: widget.value == null
                ? null
                : () => widget.onChanged(null),
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
