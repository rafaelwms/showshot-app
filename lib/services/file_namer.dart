import '../models/app_settings.dart';

/// A generated file name plus the counter value it consumed (null for
/// timestamp names, which don't touch the counter).
class GeneratedName {
  const GeneratedName(this.name, this.usedNumber);

  /// File name with extension, no directory.
  final String name;
  final int? usedNumber;

  /// Counter value to persist after a successful save with this name.
  int? get nextCounter => usedNumber == null ? null : usedNumber! + 1;
}

/// Builds file names. Pure apart from the injected `exists` callback, so it
/// is unit-testable without a file system.
class FileNamer {
  const FileNamer._();

  static const defaultPrefix = 'ShowShot';
  static const maxPrefixLength = 40;

  /// Candidates tried before giving up and using a timestamp name.
  static const maxProbes = 10000;

  // Invalid on Windows (and `/` on every OS), plus control characters.
  static final _invalidChars = RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]');

  /// Removes characters invalid in file names, trims, and falls back to
  /// [defaultPrefix] when nothing is left.
  static String sanitizePrefix(String raw) {
    var value = raw.replaceAll(_invalidChars, '').trim();
    if (value.length > maxPrefixLength) {
      value = value.substring(0, maxPrefixLength).trim();
    }
    // Windows strips trailing dots/spaces from names.
    value = value.replaceAll(RegExp(r'[. ]+$'), '');
    return value.isEmpty ? defaultPrefix : value;
  }

  static final _reserved = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
    caseSensitive: false,
  );

  /// True when the file name's stem is a Windows reserved device name.
  static bool isReservedStem(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    return _reserved.hasMatch(stem);
  }

  static String separatorText(NameSeparator separator) => switch (separator) {
    NameSeparator.underscore => '_',
    NameSeparator.dash => '-',
    NameSeparator.space => ' ',
    NameSeparator.none => '',
  };

  /// `<prefix><separator><zero-padded number>.<ext>`. Numbers wider than
  /// [digits] simply grow.
  static String sequentialName({
    required String prefix,
    required NameSeparator separator,
    required int digits,
    required int number,
    required String extension,
  }) {
    final width = digits < 1 ? 1 : (digits > 5 ? 5 : digits);
    final counter = number.toString().padLeft(width, '0');
    return '${sanitizePrefix(prefix)}${separatorText(separator)}$counter.$extension';
  }

  /// The classic `ShowShot_2026-11-20_13-05-09.png` name. [index] (1-based)
  /// adds a `_<index>` suffix, used when one capture writes several files.
  static String timestampName(String extension, DateTime when, {int? index}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${when.year}-${two(when.month)}-${two(when.day)}_${two(when.hour)}-${two(when.minute)}-${two(when.second)}';
    final suffix = index == null ? '' : '_$index';
    return 'ShowShot_$stamp$suffix.$extension';
  }

  /// Name for the next save. In sequence mode, starts at
  /// `settings.sequenceNext` and skips numbers whose file [exists] in the
  /// destination, falling back to a timestamp name after [maxProbes] tries.
  static Future<GeneratedName> next({
    required AppSettings settings,
    required DateTime now,
    required Future<bool> Function(String fileName) exists,
  }) async {
    final ext = settings.saveFormat.name;
    if (settings.fileNaming == FileNaming.timestamp) {
      return GeneratedName(timestampName(ext, now), null);
    }
    var number = settings.sequenceNext < 1 ? 1 : settings.sequenceNext;
    for (var i = 0; i < maxProbes; i++, number++) {
      final name = sequentialName(
        prefix: settings.namePrefix,
        separator: settings.nameSeparator,
        digits: settings.nameDigits,
        number: number,
        extension: ext,
      );
      if (isReservedStem(name) || await exists(name)) continue;
      return GeneratedName(name, number);
    }
    return GeneratedName(timestampName(ext, now), null);
  }

  /// Names for [count] files written by one capture ("All screens", one file
  /// per display, in display order).
  ///
  /// - Timestamp scheme: the same timestamp for all, plus `_1`, `_2`… by
  ///   position; a lone file gets no suffix.
  /// - Sequence scheme: each file consumes the next free number (taken ones
  ///   are skipped, like [next]).
  ///
  /// The counter to persist afterwards is the last entry's
  /// [GeneratedName.nextCounter] (null when no number was consumed).
  static Future<List<GeneratedName>> nextBatch({
    required AppSettings settings,
    required DateTime now,
    required int count,
    required Future<bool> Function(String fileName) exists,
  }) async {
    final ext = settings.saveFormat.name;
    String stamped(int i) =>
        timestampName(ext, now, index: count > 1 ? i + 1 : null);
    final names = <GeneratedName>[];
    if (settings.fileNaming == FileNaming.timestamp) {
      for (var i = 0; i < count; i++) {
        names.add(GeneratedName(stamped(i), null));
      }
      return names;
    }
    var number = settings.sequenceNext < 1 ? 1 : settings.sequenceNext;
    for (var i = 0; i < count; i++) {
      GeneratedName? found;
      for (var probe = 0; probe < maxProbes; probe++, number++) {
        final name = sequentialName(
          prefix: settings.namePrefix,
          separator: settings.nameSeparator,
          digits: settings.nameDigits,
          number: number,
          extension: ext,
        );
        if (isReservedStem(name) || await exists(name)) continue;
        found = GeneratedName(name, number);
        number++;
        break;
      }
      names.add(found ?? GeneratedName(stamped(i), null));
    }
    return names;
  }

  /// Settings-screen preview: the name the counter would produce right now,
  /// without touching the disk.
  static String preview(AppSettings settings) => sequentialName(
    prefix: settings.namePrefix,
    separator: settings.nameSeparator,
    digits: settings.nameDigits,
    number: settings.sequenceNext,
    extension: settings.saveFormat.name,
  );
}
