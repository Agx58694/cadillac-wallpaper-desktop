import 'dart:convert';
import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/models/theme_library_entry.dart';
import 'package:cadillac_wallpaper_desktop/src/services/theme_library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('persists theme history until the user deletes it', () async {
    final tempDir = await Directory.systemTemp.createTemp('theme_library_');
    addTearDown(() => tempDir.delete(recursive: true));

    final store = ThemeLibraryStore(rootDirectory: tempDir.path);
    final themeDir = Directory(p.join(tempDir.path, 'themes', 'theme-1'));
    final packageDir = Directory(p.join(themeDir.path, 'package'));
    final cacheDir = Directory(p.join(themeDir.path, 'library-cache'));
    final buildDir = Directory(p.join(tempDir.path, 'builds', 'theme-1'));
    await packageDir.create(recursive: true);
    await cacheDir.create(recursive: true);
    await buildDir.create(recursive: true);
    final themeFile = File(p.join(packageDir.path, 'theme-1.cwtheme'));
    final thumbnailFile = File(p.join(cacheDir.path, 'thumbnail_light.png'));
    final darkThumbnailFile = File(p.join(cacheDir.path, 'thumbnail_dark.png'));
    final otaFile = File(p.join(buildDir.path, 'ota_wallpaper.zip'));
    final reportFile = File(p.join(buildDir.path, 'package-report.json'));
    await themeFile.writeAsBytes(<int>[1, 2, 3]);
    await thumbnailFile.writeAsBytes(<int>[4, 5, 6]);
    await darkThumbnailFile.writeAsBytes(<int>[7, 8, 9]);
    await otaFile.writeAsBytes(<int>[10, 11, 12]);
    await reportFile.writeAsString('{}');

    final entry = ThemeLibraryEntry(
      themeId: 'theme-1',
      displayName: 'My Theme',
      author: 'Tester',
      notes: 'Saved locally',
      createdAt: DateTime.utc(2026, 6, 22),
      cwthemePath: themeFile.path,
      otaZipPath: otaFile.path,
      reportPath: reportFile.path,
      lightThumbnailPath: thumbnailFile.path,
      darkThumbnailPath: darkThumbnailFile.path,
      allChecksPassed: true,
      checkStatuses: const <String, bool>{'zip_integrity': true},
    );

    await store.saveEntries(<ThemeLibraryEntry>[entry]);
    final indexJson = await File(store.indexPath).readAsString();
    final loaded = await store.loadEntries();

    expect(indexJson, isNot(contains(tempDir.path)));
    expect(loaded, hasLength(1));
    expect(loaded.single.themeId, 'theme-1');
    expect(loaded.single.displayName, 'My Theme');
    expect(loaded.single.cwthemePath, themeFile.path);
    expect(loaded.single.otaZipPath, otaFile.path);
    expect(loaded.single.reportPath, reportFile.path);

    await store.deleteTheme('theme-1');

    expect(await store.loadEntries(), isEmpty);
    expect(themeDir.existsSync(), isFalse);
  });

  test('rewrites legacy absolute library paths as relative paths', () async {
    final tempDir = await Directory.systemTemp.createTemp('theme_library_');
    addTearDown(() => tempDir.delete(recursive: true));

    final store = ThemeLibraryStore(rootDirectory: tempDir.path);
    final themePath = p.join(
      tempDir.path,
      'themes',
      'legacy-theme',
      'package',
      'legacy-theme.cwtheme',
    );
    await File(store.indexPath).parent.create(recursive: true);
    await File(store.indexPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<Map<String, dynamic>>[
        <String, dynamic>{
          'themeId': 'legacy-theme',
          'displayName': 'Legacy Theme',
          'author': '',
          'notes': '',
          'createdAt': DateTime.utc(2026, 6, 22).toIso8601String(),
          'cwthemePath': themePath,
          'otaZipPath': p.join(tempDir.path, 'builds', 'legacy.zip'),
          'reportPath': p.join(tempDir.path, 'builds', 'report.json'),
          'lightThumbnailPath': p.join(tempDir.path, 'cache', 'light.png'),
          'darkThumbnailPath': p.join(tempDir.path, 'cache', 'dark.png'),
          'allChecksPassed': true,
          'checkStatuses': <String, bool>{'zip_integrity': true},
        },
      ]),
    );

    final loaded = await store.loadEntries();
    await store.saveEntries(loaded);
    final migratedJson = await File(store.indexPath).readAsString();

    expect(loaded.single.cwthemePath, themePath);
    expect(migratedJson, isNot(contains(tempDir.path)));
    expect(migratedJson, contains('legacy-theme.cwtheme'));
  });
}
