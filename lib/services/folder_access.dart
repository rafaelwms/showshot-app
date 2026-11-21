import 'dart:io';

/// Pure decisions about macOS sandbox folder permissions (unit-tested).
class FolderAccess {
  const FolderAccess._();

  /// Path without trailing separators, for comparisons.
  static String normalize(String path) {
    var p = path;
    while (p.length > 1 && (p.endsWith('/') || p.endsWith('\\'))) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// True when [path] is [root] or inside it.
  static bool isWithin(String path, String root) {
    final p = normalize(path);
    final r = normalize(root);
    if (r.isEmpty) return false;
    final prefix = r.endsWith('/') ? r : '$r${Platform.pathSeparator}';
    return p == r || p.startsWith(prefix);
  }

  /// Whether to show the "allow this folder" panel after a Save As into
  /// [folder]: not when this launch already has access to it ([accessible]:
  /// configured or last-folder bookmark resolved, or a previous grant), not
  /// when the user already cancelled it ([declined]), and not inside a
  /// [freeRoots] folder the sandbox entitlements already cover (Pictures).
  /// All sets hold [normalize]d paths.
  static bool needsPrompt({
    required String folder,
    required Set<String> accessible,
    required Set<String> declined,
    Iterable<String> freeRoots = const [],
  }) {
    final f = normalize(folder);
    if (f.isEmpty) return false;
    if (accessible.contains(f) || declined.contains(f)) return false;
    for (final root in freeRoots) {
      if (isWithin(f, root)) return false;
    }
    return true;
  }
}
