import 'dart:convert';
import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/models/theme_library_entry.dart';
import 'package:path/path.dart' as p;

class ThemeLibraryStore {
  const ThemeLibraryStore({required this.rootDirectory});

  final String rootDirectory;

  String get indexPath => p.join(rootDirectory, 'library.json');

  Future<List<ThemeLibraryEntry>> loadEntries() async {
    final file = File(indexPath);
    if (!file.existsSync()) {
      return const <ThemeLibraryEntry>[];
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      return const <ThemeLibraryEntry>[];
    }

    return decoded
        .whereType<Map>()
        .map((entry) => ThemeLibraryEntry.fromJson(
              entry
                  .map((key, dynamic value) => MapEntry(key.toString(), value)),
              basePath: rootDirectory,
            ))
        .where((entry) => entry.themeId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveEntries(List<ThemeLibraryEntry> entries) async {
    final file = File(indexPath);
    await file.parent.create(recursive: true);
    final ordered = entries.toList(growable: false)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        ordered
            .map((entry) => entry.toJson(basePath: rootDirectory))
            .toList(growable: false),
      ),
    );
  }

  Future<void> upsertEntry(ThemeLibraryEntry entry) async {
    final entries = await loadEntries();
    final next = <ThemeLibraryEntry>[
      entry,
      ...entries.where((current) => current.themeId != entry.themeId),
    ];
    await saveEntries(next);
  }

  Future<void> deleteTheme(String themeId) async {
    final entries = await loadEntries();
    final entry = entries.where((item) => item.themeId == themeId).firstOrNull;
    if (entry != null) {
      final themeDir =
          Directory(p.join(rootDirectory, 'themes', entry.themeId));
      if (themeDir.existsSync()) {
        await themeDir.delete(recursive: true);
      }
    }
    await saveEntries(
      entries.where((item) => item.themeId != themeId).toList(growable: false),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
