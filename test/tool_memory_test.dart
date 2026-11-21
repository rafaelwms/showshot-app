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
  textAlign: TextAlign.center,
  brushSize: 80, // 40 logical px at ratio 2
  hardness: 0.25,
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
    expect(m.textAlign, TextAlign.center);
    expect(m.brushSize, 40);
    expect(m.hardness, 0.25);
  });

  test('restoring at another pixelRatio keeps the logical size', () {
    final style = _capture(ratio: 2).toStyle(1);
    expect(style.strokeWidth, 5);
    expect(style.fontSize, 30);
    expect(style.color.toARGB32(), 0xCC112233);
    expect(_capture(ratio: 2).toStyle(3).strokeWidth, 15);
    expect(style.brushSize, 40);
    expect(_capture(ratio: 2).toStyle(3).brushSize, 120);
  });

  test('JSON round-trip', () {
    final m = _capture();
    final back = ToolMemory.fromJson(
      jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      0xFF000000,
    );
    expect(back.sameAs(m), isTrue);
    expect(back.toolType, ToolType.rect);
    expect(back.textAlign, TextAlign.center);
    expect(back.toStyle(2).textAlign, TextAlign.center);
    expect(back.brushSize, 40);
    expect(back.hardness, 0.25);
    expect(back.toStyle(2).hardness, 0.25);
  });

  test('stamp is a persistent tool; old prefs get brush defaults', () {
    final m = _capture(tool: ToolType.stamp);
    expect(m.tool, 'stamp');
    expect(m.toolType, ToolType.stamp);
    final old = ToolMemory.fromJson({'tool': 'blur'}, 0xFF000000);
    expect(old.brushSize, 40);
    expect(old.hardness, 0.5);
    expect(old.toStyle(1).brushSize, 40);
    // A wrong type falls back to the default too.
    expect(ToolMemory.fromJson({'hardness': 'soft'}, 0xFF000000).hardness, 0.5);
  });

  test('textAlign defaults to left when missing, unknown or unsupported', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {'textAlign': 'justify'},
      {'textAlign': 3},
    ]) {
      expect(ToolMemory.fromJson(json, 0xFF000000).textAlign, TextAlign.left);
    }
    expect(
      ToolMemory.fromJson({'textAlign': 'right'}, 0xFF000000).textAlign,
      TextAlign.right,
    );
    // Unsupported alignments are stored as left.
    final m = ToolMemory.capture(
      tool: ToolType.text,
      style: _style.copyWith(textAlign: TextAlign.justify),
      pixelRatio: 1,
    );
    expect(m.textAlign, TextAlign.left);
  });

  test('textLineOffset places lines inside the box', () {
    expect(textLineOffset(TextAlign.left, 40, 100), 0);
    expect(textLineOffset(TextAlign.center, 40, 100), 30);
    expect(textLineOffset(TextAlign.right, 40, 100), 60);
    // The widest line fills the box: always at 0.
    expect(textLineOffset(TextAlign.right, 100, 100), 0);
    expect(textLineOffset(TextAlign.center, 100, 100), 0);
    // A line wider than the box never gets a negative offset.
    expect(textLineOffset(TextAlign.center, 120, 100), 0);
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
      'brushSize': 900,
      'hardness': 3,
    }, 0xFF000000);
    final s = m.toStyle(2);
    expect(s.strokeWidth, 48);
    expect(s.fontSize, 16);
    expect(s.opacity, 0.1);
    expect(s.smoothing, 1);
    expect(s.brushSize, 400);
    expect(s.hardness, 1);
    expect(
      ToolMemory.fromJson({'brushSize': 1}, 0xFF000000).toStyle(2).brushSize,
      8,
    );
  });
}
