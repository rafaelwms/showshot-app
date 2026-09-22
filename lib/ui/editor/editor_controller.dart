import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/annotation.dart';

enum _DragKind { draw, move, handle }

/// Editor state: annotations, tool, style, selection, undo/redo and zoom.
///
/// All geometry is in image pixel coordinates; the view maps pointer events
/// through [transformation].
class EditorController extends ChangeNotifier {
  EditorController({
    required this.image,
    required this.pixelRatio,
    this.onOcrRegion,
  }) : _style = AnnotationStyle(
         color: AppColors.palette.first,
         strokeWidth: (3 * pixelRatio).roundToDouble(),
         fontSize: (20 * pixelRatio).roundToDouble(),
       ),
       _ocrDraftStyle = AnnotationStyle(
         color: AppColors.cyan,
         strokeWidth: (2 * pixelRatio).roundToDouble(),
       );

  final ui.Image image;
  final double pixelRatio;
  final transformation = TransformationController();

  /// Called with the selected region (image pixel coordinates) when the
  /// user finishes an [ToolType.ocr] drag. The screen owns recognizing and
  /// copying the text — the controller only reports *where*.
  final void Function(Rect rect)? onOcrRegion;

  /// Fixed look for the OCR selection rectangle, independent of the user's
  /// current annotation style — it's a selection, not a drawn shape.
  final AnnotationStyle _ocrDraftStyle;

  static const maxHistory = 100;

  List<Annotation> _annotations = [];
  final List<List<Annotation>> _undo = [];
  final List<List<Annotation>> _redo = [];

  ToolType _tool = ToolType.arrow;
  AnnotationStyle _style;
  String? _selectedId;
  Annotation? _draft;
  int _numberCounter = 1;
  bool _spaceHeld = false;

  // Text editing.
  TextAnnotation? _editingText;
  bool _editingIsNew = false;

  // Drag state.
  _DragKind? _drag;
  Offset? _dragStart;
  Annotation? _dragOriginal;
  int _dragHandle = -1;
  List<Annotation>? _preDragSnapshot;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  List<Annotation> get annotations => _annotations;
  ToolType get tool => _tool;
  AnnotationStyle get style => _style;
  String? get selectedId => _selectedId;
  Annotation? get draft => _draft;
  TextAnnotation? get editingText => _editingText;
  bool get isEditingText => _editingText != null;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasAnnotations => _annotations.isNotEmpty;
  bool get spaceHeld => _spaceHeld;
  bool get panEnabled => _tool == ToolType.hand || _spaceHeld;
  Size get imageSize => Size(image.width.toDouble(), image.height.toDouble());

  Annotation? get selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final a in _annotations) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Annotations to paint (the one being edited as text is hidden; the draft
  /// is appended on top).
  List<Annotation> get paintable => [
    for (final a in _annotations)
      if (a.id != _editingText?.id) a,
    ?_draft,
  ];

  /// Everything that should end up in the exported image.
  List<Annotation> get exportable => _annotations;

  /// Current scale factor. Reads the X axis directly: `getMaxScaleOnAxis`
  /// would report 1.0 for any zoom below 100% because the Z axis stays at 1.
  double get zoom => transformation.value.storage[0];

  // ---------------------------------------------------------------------------
  // Tool & style
  // ---------------------------------------------------------------------------

  void setTool(ToolType tool) {
    if (_tool == tool) return;
    commitTextEditing();
    _tool = tool;
    if (tool != ToolType.select) _selectedId = null;
    notifyListeners();
  }

  void setStyle(AnnotationStyle style) {
    _style = style;
    final current = selected;
    if (current != null) {
      _pushHistory();
      _replace(current.withStyle(style));
    } else if (_editingText != null) {
      _editingText = _editingText!.withStyle(style) as TextAnnotation;
    }
    notifyListeners();
  }

  void setSpaceHeld(bool held) {
    if (_spaceHeld == held) return;
    _spaceHeld = held;
    notifyListeners();
  }

  void selectAnnotation(String? id) {
    _selectedId = id;
    if (id != null) {
      final current = selected;
      if (current != null) _style = current.style;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  void _pushHistory([List<Annotation>? snapshot]) {
    _undo.add(snapshot ?? List.of(_annotations));
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    commitTextEditing();
    if (_undo.isEmpty) return;
    _redo.add(List.of(_annotations));
    _annotations = _undo.removeLast();
    _selectedId = null;
    notifyListeners();
  }

  void redo() {
    commitTextEditing();
    if (_redo.isEmpty) return;
    _undo.add(List.of(_annotations));
    _annotations = _redo.removeLast();
    _selectedId = null;
    notifyListeners();
  }

  void deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    _pushHistory();
    _annotations = _annotations.where((a) => a.id != id).toList();
    _selectedId = null;
    notifyListeners();
  }

  void clearAll() {
    commitTextEditing();
    if (_annotations.isEmpty) return;
    _pushHistory();
    _annotations = [];
    _selectedId = null;
    _numberCounter = 1;
    notifyListeners();
  }

  void _replace(Annotation annotation) {
    _annotations = [
      for (final a in _annotations) a.id == annotation.id ? annotation : a,
    ];
  }

  // ---------------------------------------------------------------------------
  // Pointer interaction (image coordinates)
  // ---------------------------------------------------------------------------

  double _tolerance() => 8 / math.max(zoom, 0.01);

  void pointerDown(Offset p) {
    if (panEnabled) return;
    switch (_tool) {
      case ToolType.hand:
        return;
      case ToolType.select:
        _selectAt(p);
      case ToolType.text:
        _startText(p);
      case ToolType.number:
        commitTextEditing();
        _pushHistory();
        _annotations = [
          ..._annotations,
          NumberAnnotation(
            id: newAnnotationId(),
            style: _style,
            center: p,
            number: _numberCounter++,
          ),
        ];
        notifyListeners();
      case ToolType.pen:
      case ToolType.marker:
        commitTextEditing();
        _draft = StrokeAnnotation(
          id: newAnnotationId(),
          style: _style,
          points: [p],
          marker: _tool == ToolType.marker,
        );
        _drag = _DragKind.draw;
        _dragStart = p;
        notifyListeners();
      case ToolType.arrow:
      case ToolType.line:
      case ToolType.rect:
      case ToolType.ellipse:
      case ToolType.blur:
        commitTextEditing();
        _draft = ShapeAnnotation(
          id: newAnnotationId(),
          style: _style,
          kind: switch (_tool) {
            ToolType.arrow => ShapeKind.arrow,
            ToolType.line => ShapeKind.line,
            ToolType.rect => ShapeKind.rect,
            ToolType.ellipse => ShapeKind.ellipse,
            _ => ShapeKind.blur,
          },
          start: p,
          end: p,
        );
        _drag = _DragKind.draw;
        _dragStart = p;
        notifyListeners();
      case ToolType.ocr:
        commitTextEditing();
        _draft = ShapeAnnotation(
          id: newAnnotationId(),
          style: _ocrDraftStyle,
          kind: ShapeKind.rect,
          start: p,
          end: p,
        );
        _drag = _DragKind.draw;
        _dragStart = p;
        notifyListeners();
    }
  }

  void _selectAt(Offset p) {
    commitTextEditing();
    final tolerance = _tolerance();
    final current = selected;
    if (current != null) {
      final handles = current.handles;
      for (var i = 0; i < handles.length; i++) {
        if ((handles[i] - p).distance <= tolerance * 1.5) {
          _drag = _DragKind.handle;
          _dragHandle = i;
          _dragStart = p;
          _dragOriginal = current;
          _preDragSnapshot = List.of(_annotations);
          return;
        }
      }
    }
    // Topmost annotation wins.
    for (final a in _annotations.reversed) {
      if (a.hitTest(p, tolerance)) {
        _selectedId = a.id;
        _style = a.style;
        _drag = _DragKind.move;
        _dragStart = p;
        _dragOriginal = a;
        _preDragSnapshot = List.of(_annotations);
        notifyListeners();
        return;
      }
    }
    _selectedId = null;
    notifyListeners();
  }

  void pointerMove(Offset p, {bool shift = false}) {
    if (_drag == null || _dragStart == null) return;
    switch (_drag!) {
      case _DragKind.draw:
        final draft = _draft;
        if (draft is ShapeAnnotation) {
          _draft = draft.copyWith(
            end: shift ? _constrain(draft.start, p, draft.isLinear) : p,
          );
        } else if (draft is StrokeAnnotation) {
          if ((draft.points.last - p).distance >= 1.5) {
            _draft = draft.appended(p);
          }
        }
      case _DragKind.move:
        final original = _dragOriginal!;
        _replace(original.translated(p - _dragStart!));
      case _DragKind.handle:
        final original = _dragOriginal!;
        var target = p;
        if (shift && original is ShapeAnnotation) {
          final anchor = original.isLinear
              ? (_dragHandle == 0 ? original.end : original.start)
              : original.handles[(_dragHandle + 2) % 4];
          target = _constrain(anchor, p, original.isLinear);
        }
        _replace(original.withHandle(_dragHandle, target));
    }
    notifyListeners();
  }

  void pointerUp(Offset p) {
    if (_drag == null) return;
    switch (_drag!) {
      case _DragKind.draw:
        final draft = _draft;
        _draft = null;
        if (draft != null && !draft.isDegenerate) {
          if (_tool == ToolType.ocr && draft is ShapeAnnotation) {
            // Not an annotation: report the region and leave nothing behind.
            onOcrRegion?.call(draft.rect);
          } else {
            _pushHistory();
            _annotations = [..._annotations, draft];
          }
        }
      case _DragKind.move:
      case _DragKind.handle:
        final original = _dragOriginal;
        final now = selected;
        if (original != null &&
            now != null &&
            !identical(original, now) &&
            _preDragSnapshot != null) {
          _pushHistory(_preDragSnapshot);
        }
    }
    _drag = null;
    _dragStart = null;
    _dragOriginal = null;
    _dragHandle = -1;
    _preDragSnapshot = null;
    notifyListeners();
  }

  /// Shift constraint: 45° increments for lines, squares for boxes.
  Offset _constrain(Offset anchor, Offset p, bool linear) {
    final d = p - anchor;
    if (linear) {
      final angle = math.atan2(d.dy, d.dx);
      final snapped = (angle / (math.pi / 4)).round() * (math.pi / 4);
      final length = d.distance;
      return anchor + Offset(math.cos(snapped), math.sin(snapped)) * length;
    }
    final side = math.max(d.dx.abs(), d.dy.abs());
    return anchor + Offset(side * d.dx.sign, side * d.dy.sign);
  }

  /// Handles under [p] for the selected annotation (used for cursor feedback).
  bool isOverHandle(Offset p) {
    final current = selected;
    if (current == null) return false;
    final tolerance = _tolerance() * 1.5;
    return current.handles.any((h) => (h - p).distance <= tolerance);
  }

  bool isOverAnnotation(Offset p) {
    final tolerance = _tolerance();
    return _annotations.any((a) => a.hitTest(p, tolerance));
  }

  // ---------------------------------------------------------------------------
  // Text editing
  // ---------------------------------------------------------------------------

  void _startText(Offset p) {
    commitTextEditing();
    final tolerance = _tolerance();
    for (final a in _annotations.reversed) {
      if (a is TextAnnotation && a.hitTest(p, tolerance)) {
        beginTextEdit(a);
        return;
      }
    }
    _editingText = TextAnnotation(
      id: newAnnotationId(),
      style: _style,
      position: p,
      text: '',
    );
    _editingIsNew = true;
    _selectedId = null;
    notifyListeners();
  }

  void beginTextEdit(TextAnnotation annotation) {
    commitTextEditing();
    _editingText = annotation;
    _editingIsNew = false;
    _style = annotation.style;
    _selectedId = null;
    _tool = ToolType.text;
    notifyListeners();
  }

  void updateEditingText(String text) {
    final editing = _editingText;
    if (editing == null) return;
    _editingText = editing.copyWith(text: text);
  }

  void commitTextEditing() {
    final editing = _editingText;
    if (editing == null) return;
    _editingText = null;
    if (editing.text.trim().isEmpty) {
      if (!_editingIsNew) {
        _pushHistory();
        _annotations = _annotations.where((a) => a.id != editing.id).toList();
      }
    } else if (_editingIsNew) {
      _pushHistory();
      _annotations = [..._annotations, editing];
    } else {
      _pushHistory();
      _replace(editing);
    }
    _editingIsNew = false;
    notifyListeners();
  }

  void cancelTextEditing() {
    if (_editingText == null) return;
    _editingText = null;
    _editingIsNew = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Zoom
  // ---------------------------------------------------------------------------

  void fitTo(Size viewport, {double padding = 48}) {
    if (viewport.isEmpty) return;
    final scale = math
        .min(
          (viewport.width - padding * 2) / image.width,
          (viewport.height - padding * 2) / image.height,
        )
        .clamp(0.02, 1.0);
    _setZoom(scale, viewport);
  }

  void actualSize(Size viewport) => _setZoom(1.0, viewport);

  void zoomBy(double factor, Size viewport) {
    final target = (zoom * factor).clamp(0.05, 8.0);
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final scene = transformation.toScene(center);
    final matrix = Matrix4.identity()
      ..translateByDouble(
        center.dx - scene.dx * target,
        center.dy - scene.dy * target,
        0,
        1,
      )
      ..scaleByDouble(target, target, target, 1);
    transformation.value = matrix;
    notifyListeners();
  }

  void _setZoom(double scale, Size viewport) {
    final dx = (viewport.width - image.width * scale) / 2;
    final dy = (viewport.height - image.height * scale) / 2;
    transformation.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
    notifyListeners();
  }

  @override
  void dispose() {
    transformation.dispose();
    super.dispose();
  }
}
