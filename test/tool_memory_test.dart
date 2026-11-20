import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoshot/models/annotation.dart';
import 'package:shoshot/models/app_settings.dart';
import 'package:shoshot/models/tool_memory.dart';

const _style = AnnotationStyle(
  color: Color(0xCC112233),
  strokeWidth: 10, // 5 logical px at ratio 2
  opacity: 0.6,
  filled: true,
  fontSize: 60, // 30 logical px at ratio 2
  smoothing: 0.25,
);

ToolMemory _capture({
  ToolMemory? previous,
  ToolType tool = ToolType.rect,
  double ratio = 2,
}) => ToolMemory.capture(
  previous: previous,
  tool: tool,
  style: _style,
  pixelRatio: ratio,
);

void main() {
  test('capture stores logical sizes and ARGB color', () {
    final m = _capture();
    expect(m.tool, 'rect');
    expect(m.colorArgb, 0xCC112233);
    expect(m.strokeWidth, 5);
    expect(m.fontSize, 30);
  });

  test('restoring at another pixelRatio keeps the logical size', () {
    final style = _capture(ratio: 2).toStyle(1);
    expect(style.strokeWidth, 5);
    expect(style.fontSize, 30);
    expect(style.color.toARGB32(), 0xCC112233);
    expect(_capture(ratio: 2).toStyle(3).strokeWidth, 15);
  });

  test('JSON round-trip', () {
    final m = _capture();
    final back = ToolMemory.fromJson(
      jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      0xFF000000,
    );
    expect(back.sameAs(m), isTrue);
    expect(back.toolType, ToolType.rect);
  });

  test('AppSettings round-trip, default off, old prefs without the keys', () {
    expect(AppSettings.defaults().rememberTools, isFalse);
    final s = AppSettings.defaults().copyWith(
      rememberTools: true,
      toolMemory: _capture(),
    );
    final back = AppSettings.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
    );
    expect(back.rememberTools, isTrue);
    expect(back.toolMemory!.sameAs(_capture()), isTrue);

    final old = AppSettings.fromJson(<String, dynamic>{});
    expect(old.rememberTools, isFalse);
    expect(old.toolMemory, isNull);
  });

  test('unknown tool name is ignored', () {
    final m = ToolMemory.fromJson({'tool': 'laser'}, 0xFF000000);
    expect(m.toolType, isNull);
    expect(m.colorArgb, 0xFF000000);
    expect(m.strokeWidth, 3);
  });

  test('transient tool keeps the previous remembered tool', () {
    final prev = _capture(tool: ToolType.pen);
    expect(_capture(previous: prev, tool: ToolType.ocr).tool, 'pen');
    expect(_capture(tool: ToolType.ocr).toolType, isNull);
    // A stored OCR tool (tampered prefs) is never restored.
    expect(ToolMemory.fromJson({'tool': 'ocr'}, 0xFF000000).toolType, isNull);
  });

  test('restored values are clamped to the slider ranges', () {
    final m = ToolMemory.fromJson({
      'strokeWidth': 500,
      'fontSize': 1,
      'opacity': 0,
      'smoothing': 7,
    }, 0xFF000000);
    final s = m.toStyle(2);
    expect(s.strokeWidth, 48);
    expect(s.fontSize, 16);
    expect(s.opacity, 0.1);
    expect(s.smoothing, 1);
  });
}
