import 'package:flutter_test/flutter_test.dart';
import 'package:shoshot/models/app_settings.dart';
import 'package:shoshot/services/file_namer.dart';

final _now = DateTime(2026, 11, 20, 13, 5, 9);

AppSettings seq({
  String prefix = 'ARQUIVO',
  NameSeparator sep = NameSeparator.underscore,
  int digits = 2,
  int next = 1,
  ImageFormat format = ImageFormat.png,
}) => AppSettings.defaults().copyWith(
  fileNaming: FileNaming.sequence,
  namePrefix: prefix,
  nameSeparator: sep,
  nameDigits: digits,
  sequenceNext: next,
  saveFormat: format,
);

Future<GeneratedName> nextWith(AppSettings s, Set<String> taken) =>
    FileNamer.next(
      settings: s,
      now: _now,
      exists: (n) async => taken.contains(n),
    );

void main() {
  group('formatting', () {
    test('default padding and separator', () async {
      final r = await nextWith(seq(), {});
      expect(r.name, 'ARQUIVO_01.png');
      expect(r.usedNumber, 1);
      expect(r.nextCounter, 2);
    });

    test('dash, 3 digits, jpg', () async {
      final r = await nextWith(
        seq(
          prefix: 'FOTO',
          sep: NameSeparator.dash,
          digits: 3,
          next: 3,
          format: ImageFormat.jpg,
        ),
        {},
      );
      expect(r.name, 'FOTO-003.jpg');
    });

    test('space and no separator', () async {
      expect(
        (await nextWith(seq(sep: NameSeparator.space), {})).name,
        'ARQUIVO 01.png',
      );
      expect(
        (await nextWith(seq(sep: NameSeparator.none), {})).name,
        'ARQUIVO01.png',
      );
    });

    test('numbers outgrowing the padding get longer', () async {
      expect((await nextWith(seq(next: 100), {})).name, 'ARQUIVO_100.png');
      expect(
        (await nextWith(seq(digits: 1, next: 12), {})).name,
        'ARQUIVO_12.png',
      );
      expect(
        (await nextWith(seq(digits: 5, next: 7), {})).name,
        'ARQUIVO_00007.png',
      );
    });

    test('preview matches the first name', () {
      expect(FileNamer.preview(seq()), 'ARQUIVO_01.png');
    });
  });

  group('sanitizePrefix', () {
    test('removes invalid characters', () {
      expect(FileNamer.sanitizePrefix(r'a\b/c:d*e?f"g<h>i|j'), 'abcdefghij');
    });
    test('removes control characters and trims', () {
      expect(FileNamer.sanitizePrefix('  Foto\u0000\n\t '), 'Foto');
    });
    test('empty after cleaning falls back to default', () {
      expect(FileNamer.sanitizePrefix(''), 'ShowShot');
      expect(FileNamer.sanitizePrefix('  ?*:  '), 'ShowShot');
    });
    test('trailing dots are dropped', () {
      expect(FileNamer.sanitizePrefix('Foto..'), 'Foto');
    });
    test('keeps accents and inner spaces', () {
      expect(FileNamer.sanitizePrefix('Tela do Pão'), 'Tela do Pão');
    });
    test('used by the generator', () async {
      expect((await nextWith(seq(prefix: 'a/b'), {})).name, 'ab_01.png');
      expect((await nextWith(seq(prefix: '///'), {})).name, 'ShowShot_01.png');
    });
  });

  group('reserved names', () {
    test('skips Windows device names', () async {
      final r = await nextWith(
        seq(prefix: 'com', sep: NameSeparator.none, digits: 1, next: 1),
        {},
      );
      expect(r.name, 'com10.png');
      expect(r.usedNumber, 10);
      final l = await nextWith(
        seq(prefix: 'LPT', sep: NameSeparator.none, digits: 1, next: 9),
        {},
      );
      expect(l.name, 'LPT10.png');
    });
  });

  group('skip existing', () {
    test('skips taken numbers', () async {
      final r = await nextWith(seq(), {
        'ARQUIVO_01.png',
        'ARQUIVO_02.png',
        'ARQUIVO_04.png',
      });
      expect(r.name, 'ARQUIVO_03.png');
      expect(r.nextCounter, 4);
    });

    test('starts from the stored counter', () async {
      final r = await nextWith(seq(next: 5), {'ARQUIVO_05.png'});
      expect(r.name, 'ARQUIVO_06.png');
    });

    test('gives up after maxProbes and falls back to a timestamp', () async {
      var calls = 0;
      final r = await FileNamer.next(
        settings: seq(),
        now: _now,
        exists: (_) async {
          calls++;
          return true;
        },
      );
      expect(calls, FileNamer.maxProbes);
      expect(r.name, 'ShowShot_2026-11-20_13-05-09.png');
      expect(r.usedNumber, isNull);
      expect(r.nextCounter, isNull);
    });
  });

  group('timestamp mode', () {
    test('unchanged format, never touches the file system', () async {
      final r = await FileNamer.next(
        settings: AppSettings.defaults(),
        now: _now,
        exists: (_) async => fail('exists must not be called'),
      );
      expect(r.name, 'ShowShot_2026-11-20_13-05-09.png');
      expect(r.usedNumber, isNull);
    });

    test('jpg extension', () async {
      final r = await FileNamer.next(
        settings: AppSettings.defaults().copyWith(saveFormat: ImageFormat.jpg),
        now: _now,
        exists: (_) async => false,
      );
      expect(r.name, 'ShowShot_2026-11-20_13-05-09.jpg');
    });
  });

  group('AppSettings naming fields', () {
    test('defaults for old JSON', () {
      final s = AppSettings.fromJson(const {});
      expect(s.fileNaming, FileNaming.timestamp);
      expect(s.namePrefix, 'ShowShot');
      expect(s.nameSeparator, NameSeparator.underscore);
      expect(s.nameDigits, 2);
      expect(s.sequenceNext, 1);
    });

    test('JSON round-trip', () {
      final back = AppSettings.fromJson(
        seq(
          prefix: 'FOTO',
          sep: NameSeparator.none,
          digits: 4,
          next: 42,
        ).toJson(),
      );
      expect(back.fileNaming, FileNaming.sequence);
      expect(back.namePrefix, 'FOTO');
      expect(back.nameSeparator, NameSeparator.none);
      expect(back.nameDigits, 4);
      expect(back.sequenceNext, 42);
    });

    test('out-of-range values are clamped', () {
      final s = AppSettings.fromJson(const {
        'nameDigits': 99,
        'sequenceNext': -5,
        'fileNaming': 'bogus',
      });
      expect(s.nameDigits, 5);
      expect(s.sequenceNext, 1);
      expect(s.fileNaming, FileNaming.timestamp);
    });
  });
}
