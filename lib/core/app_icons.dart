import 'package:flutter/widgets.dart';

import 'phosphor_glyphs.dart';

/// Single source of the editor/overlay icons (Phosphor), in either the
/// Regular or the Bold weight (`AppSettings.boldIcons`).
///
/// Read it with [AppIcons.of]: the lookup depends on [AppIconsScope] (placed
/// above the Navigator in `app.dart`), so every widget that calls it rebuilds
/// when the setting flips — even ones created through a `const` constructor.
class AppIcons {
  const AppIcons(this.bold);

  /// True for the Bold weight.
  final bool bold;

  static const regular = AppIcons(false);
  static const boldWeight = AppIcons(true);

  static AppIcons of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppIconsScope>();
    return scope?.icons ?? regular;
  }

  // Optical sizes. Phosphor glyphs fill their box more than Material's (which
  // carry ~2px of padding), so every size here is ~1px below the old Material
  // value to keep the visual weight of the toolbars unchanged. Use these
  // constants instead of literals.

  /// Tool rail glyphs (was 19 with Material).
  static const double railSize = 18;

  /// Icon buttons in bars (`ToolButton`; was 19).
  static const double buttonSize = 18;

  /// Icon next to a label in Ghost/Accent buttons (was 17).
  static const double labelButtonSize = 16;

  /// Small icon beside a slider (was 16).
  static const double inlineSize = 15;

  /// The "..." menu in the editor title bar (was 20).
  static const double menuSize = 19;

  /// Window chrome buttons (was 16).
  static const double windowButtonSize = 15;

  /// The "+" inside the custom-color swatch (was 14).
  static const double tinySize = 13;

  /// Overlay hint / camera badge icons (were 16 / 15).
  static const double hintSize = 15;
  static const double badgeSize = 14;

  IconData _p(IconData regularIcon, IconData boldIcon) =>
      bold ? boldIcon : regularIcon;

  // Tools.
  IconData get select => _p(PhosphorRegular.cursor, PhosphorBold.cursor);
  IconData get hand => _p(PhosphorRegular.hand, PhosphorBold.hand);
  IconData get arrow =>
      _p(PhosphorRegular.arrowUpRight, PhosphorBold.arrowUpRight);
  IconData get line =>
      _p(PhosphorRegular.lineSegment, PhosphorBold.lineSegment);
  IconData get rect => _p(PhosphorRegular.square, PhosphorBold.square);
  IconData get ellipse => _p(PhosphorRegular.circle, PhosphorBold.circle);
  IconData get pen =>
      _p(PhosphorRegular.pencilSimpleLine, PhosphorBold.pencilSimpleLine);
  IconData get marker =>
      _p(PhosphorRegular.highlighter, PhosphorBold.highlighter);
  IconData get text => _p(PhosphorRegular.textT, PhosphorBold.textT);
  IconData get number =>
      _p(PhosphorRegular.numberCircleOne, PhosphorBold.numberCircleOne);
  IconData get blur => _p(PhosphorRegular.dropHalf, PhosphorBold.dropHalf);
  IconData get ocr => _p(PhosphorRegular.scan, PhosphorBold.scan);

  // Future tools (M6/M1).
  IconData get crop => _p(PhosphorRegular.crop, PhosphorBold.crop);
  IconData get stamp => _p(PhosphorRegular.stamp, PhosphorBold.stamp);

  // Actions.
  IconData get undo => _p(
    PhosphorRegular.arrowCounterClockwise,
    PhosphorBold.arrowCounterClockwise,
  );
  IconData get redo =>
      _p(PhosphorRegular.arrowClockwise, PhosphorBold.arrowClockwise);
  IconData get more => _p(PhosphorRegular.dotsThree, PhosphorBold.dotsThree);
  IconData get copy => _p(PhosphorRegular.copy, PhosphorBold.copy);
  IconData get save =>
      _p(PhosphorRegular.downloadSimple, PhosphorBold.downloadSimple);

  /// Close / discard / cancel.
  IconData get close => _p(PhosphorRegular.x, PhosphorBold.x);
  IconData get discard => close;
  IconData get confirm => _p(PhosphorRegular.check, PhosphorBold.check);
  IconData get fitScreen =>
      _p(PhosphorRegular.cornersOut, PhosphorBold.cornersOut);
  IconData get add => _p(PhosphorRegular.plus, PhosphorBold.plus);
  IconData get remove => _p(PhosphorRegular.minus, PhosphorBold.minus);
  IconData get delete => _p(PhosphorRegular.trash, PhosphorBold.trash);

  /// Overlay "extract text" button (same glyph as the OCR tool).
  IconData get extractText => ocr;

  /// Overlay "edit" button (open the editor): the pen, not the highlighter.
  IconData get edit => pen;

  // Properties bar.
  IconData get strokeWidth =>
      _p(PhosphorRegular.lineVertical, PhosphorBold.lineVertical);
  IconData get opacity => _p(PhosphorRegular.drop, PhosphorBold.drop);
  IconData get fill =>
      _p(PhosphorRegular.paintBucket, PhosphorBold.paintBucket);

  /// "Not filled": a prohibition sign reads as "no fill" more clearly than a
  /// dashed circle, and unlike the bucket it can't be mistaken for "on".
  IconData get noFill => _p(PhosphorRegular.prohibit, PhosphorBold.prohibit);
  IconData get fontSize => _p(PhosphorRegular.textAa, PhosphorBold.textAa);
  IconData get smoothing => _p(PhosphorRegular.waveSine, PhosphorBold.waveSine);
  IconData get alignLeft =>
      _p(PhosphorRegular.textAlignLeft, PhosphorBold.textAlignLeft);
  IconData get alignCenter =>
      _p(PhosphorRegular.textAlignCenter, PhosphorBold.textAlignCenter);
  IconData get alignRight =>
      _p(PhosphorRegular.textAlignRight, PhosphorBold.textAlignRight);

  // Window chrome and overlay.
  IconData get minimize => remove;
  IconData get maximize => rect;
  IconData get camera => _p(PhosphorRegular.camera, PhosphorBold.camera);
  IconData get appWindow =>
      _p(PhosphorRegular.appWindow, PhosphorBold.appWindow);
  IconData get selection =>
      _p(PhosphorRegular.selection, PhosphorBold.selection);

  /// Every getter, for the unit test (both weights must resolve).
  List<IconData> get all => [
    select,
    hand,
    arrow,
    line,
    rect,
    ellipse,
    pen,
    marker,
    text,
    number,
    blur,
    ocr,
    crop,
    stamp,
    undo,
    redo,
    more,
    copy,
    save,
    close,
    discard,
    confirm,
    fitScreen,
    add,
    remove,
    delete,
    extractText,
    edit,
    strokeWidth,
    opacity,
    fill,
    noFill,
    fontSize,
    smoothing,
    alignLeft,
    alignCenter,
    alignRight,
    minimize,
    maximize,
    camera,
    appWindow,
    selection,
  ];

  @override
  bool operator ==(Object other) => other is AppIcons && other.bold == bold;

  @override
  int get hashCode => bold.hashCode;
}

/// Publishes the current [AppIcons] weight to the tree.
class AppIconsScope extends InheritedWidget {
  const AppIconsScope({super.key, required this.icons, required super.child});

  final AppIcons icons;

  @override
  bool updateShouldNotify(AppIconsScope oldWidget) => icons != oldWidget.icons;
}
