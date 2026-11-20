import 'package:flutter_test/flutter_test.dart';
import 'package:shoshot/models/app_settings.dart';
import 'package:shoshot/services/export_service.dart';

/// Resolves with a fake file system: [existing] holds the folders that exist.
Future<String> resolve({
  required Set<String> existing,
  required List<String> created,
  bool useLast = true,
  String? last = '/last',
  String? configured,
}) {
  return ExportService.resolveSaveDirectoryPath(
    useLastFolder: useLast,
    lastDirectory: last,
    configuredDirectory: configured,
    builtInDefault: () async => '/pictures/ShowShot',
    exists: (p) async => existing.contains(p),
    create: (p) async {
      created.add(p);
      existing.add(p);
    },
  );
}

void main() {
  group('resolveSaveDirectoryPath', () {
    test('step 1: uses the last folder when it exists', () async {
      final created = <String>[];
      final result = await resolve(
        existing: {'/last', '/pictures/ShowShot'},
        created: created,
      );
      expect(result, '/last');
      expect(created, isEmpty);
    });

    test('step 2: last folder gone -> configured folder', () async {
      final result = await resolve(
        existing: {'/custom', '/pictures/ShowShot'},
        created: [],
        configured: '/custom',
      );
      expect(result, '/custom');
    });

    test('step 2: last folder gone, nothing configured -> built-in', () async {
      final created = <String>[];
      final result = await resolve(
        existing: {'/pictures/ShowShot'},
        created: created,
      );
      expect(result, '/pictures/ShowShot');
      expect(created, isEmpty);
    });

    test('step 3: nothing exists -> creates the built-in default', () async {
      final created = <String>[];
      final result = await resolve(
        existing: <String>{},
        created: created,
        configured: '/custom',
      );
      expect(result, '/pictures/ShowShot');
      expect(created, ['/pictures/ShowShot']);
    });

    test('switch off ignores the last folder', () async {
      final result = await resolve(
        existing: {'/last', '/custom'},
        created: [],
        useLast: false,
        configured: '/custom',
      );
      expect(result, '/custom');
    });

    test('empty / null last folder is skipped', () async {
      final result = await resolve(
        existing: {'/pictures/ShowShot'},
        created: [],
        last: '',
      );
      expect(result, '/pictures/ShowShot');
    });

    test('switch off still creates a missing default folder', () async {
      final created = <String>[];
      await resolve(existing: <String>{}, created: created, useLast: false);
      expect(created, ['/pictures/ShowShot']);
    });
  });

  group('AppSettings last-folder fields', () {
    test('defaults when absent from old JSON', () {
      final s = AppSettings.fromJson(const {});
      expect(s.saveToLastFolder, isFalse);
      expect(s.lastSaveDirectory, '');
    });

    test('JSON round-trip and copyWith', () {
      final s = AppSettings.defaults().copyWith(
        saveToLastFolder: true,
        lastSaveDirectory: '/x/y',
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.saveToLastFolder, isTrue);
      expect(back.lastSaveDirectory, '/x/y');
    });
  });
}
