import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_library_entry.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_package_request.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class ThemePackageService {
  Future<ThemeLibraryEntry> createThemePackage(
      ThemePackageRequest request) async {
    final themeId = _themeId(request.displayName, request.createdAt);
    final themeDir =
        Directory(p.join(request.libraryRootPath, 'themes', themeId));
    final packageDir = Directory(p.join(themeDir.path, 'package'));
    final cacheDir = Directory(p.join(themeDir.path, 'library-cache'));
    await packageDir.create(recursive: true);
    await cacheDir.create(recursive: true);

    final lightThumbnail = File(p.join(cacheDir.path, 'thumbnail_light.png'));
    final darkThumbnail = File(p.join(cacheDir.path, 'thumbnail_dark.png'));
    await _writeThumbnail(request.lightPreviewPath, lightThumbnail.path);
    await _writeThumbnail(request.darkPreviewPath, darkThumbnail.path);

    final manifest = _manifest(themeId, request);
    final archive = Archive();
    await _addString(archive, 'cwtheme/manifest.json', manifest);
    await _addFile(
      archive,
      'cwtheme/previews/light_preview_2198x367.png',
      request.lightPreviewPath,
    );
    await _addFile(
      archive,
      'cwtheme/previews/dark_preview_2198x367.png',
      request.darkPreviewPath,
    );
    await _addFile(
      archive,
      'cwtheme/previews/thumbnail_light.png',
      lightThumbnail.path,
    );
    await _addFile(
      archive,
      'cwtheme/previews/thumbnail_dark.png',
      darkThumbnail.path,
    );
    await _addFile(
      archive,
      'cwtheme/masters/light_master_2198x367.png',
      request.lightMasterPath,
    );
    await _addFile(
      archive,
      'cwtheme/masters/dark_master_2198x367.png',
      request.darkMasterPath,
    );
    await _addFile(
      archive,
      'cwtheme/payload/ota_wallpaper.zip',
      request.otaZipPath,
      noCompress: true,
    );
    await _addFile(
      archive,
      'cwtheme/report/package-report.json',
      request.reportPath,
    );

    final cwthemePath = p.join(packageDir.path, '$themeId.cwtheme');
    await File(cwthemePath).writeAsBytes(ZipEncoder().encode(archive));

    return ThemeLibraryEntry(
      themeId: themeId,
      displayName: request.displayName,
      author: request.author,
      notes: request.notes,
      createdAt: request.createdAt,
      cwthemePath: cwthemePath,
      otaZipPath: request.otaZipPath,
      reportPath: request.reportPath,
      lightThumbnailPath: lightThumbnail.path,
      darkThumbnailPath: darkThumbnail.path,
      allChecksPassed: request.reportSummary.allPassed,
      checkStatuses: request.reportSummary.toStatusMap(),
    );
  }
}

Map<String, dynamic> _manifest(String themeId, ThemePackageRequest request) {
  return <String, dynamic>{
    'schemaVersion': 1,
    'themeId': themeId,
    'displayName': request.displayName,
    'author': request.author,
    'notes': request.notes,
    'createdAt': request.createdAt.toIso8601String(),
    'sourceSize': <int>[2198, 367],
    'packageType': 'cadillac_ota6_wallpaper',
    'payload': 'payload/ota_wallpaper.zip',
    'lightPreview': 'previews/light_preview_2198x367.png',
    'darkPreview': 'previews/dark_preview_2198x367.png',
    'lightThumbnail': 'previews/thumbnail_light.png',
    'darkThumbnail': 'previews/thumbnail_dark.png',
    'report': 'report/package-report.json',
    'checks': request.reportSummary.toManifestChecks(),
    'checkDetails': request.reportSummary.toStatusMap(),
    'androidInstall': <String, dynamic>{
      'targetRoot': '/sdcard/Download/paper/BFA3A0F4596C4C57A6BCDC1EB3348932',
      'targetFolder': 'cadi_wallpaper05111930',
      'payloadZip': 'payload/ota_wallpaper.zip',
      'payloadFolderInZip':
          'BFA3A0F4596C4C57A6BCDC1EB3348932/cadi_wallpaper05111930',
      'requiresManualSelectionInCarSettings': true,
    },
  };
}

Future<void> _addString(
  Archive archive,
  String archivePath,
  Map<String, dynamic> content,
) async {
  archive.addFile(
    ArchiveFile.string(
      archivePath,
      const JsonEncoder.withIndent('  ').convert(content),
    ),
  );
}

Future<void> _addFile(
  Archive archive,
  String archivePath,
  String sourcePath, {
  bool noCompress = false,
}) async {
  final bytes = await File(sourcePath).readAsBytes();
  archive.addFile(
    noCompress
        ? ArchiveFile.noCompress(archivePath, bytes.length, bytes)
        : ArchiveFile.bytes(archivePath, bytes),
  );
}

Future<void> _writeThumbnail(String sourcePath, String outputPath) async {
  final source = img.decodeImage(await File(sourcePath).readAsBytes());
  if (source == null) {
    throw FormatException('无法读取预览 PNG: $sourcePath');
  }

  final thumbnail = img.copyResize(
    source,
    width: 640,
    interpolation: img.Interpolation.average,
  );
  await File(outputPath).writeAsBytes(img.encodePng(thumbnail));
}

String _themeId(String displayName, DateTime createdAt) {
  final slug = displayName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final prefix = slug.isEmpty ? 'theme' : slug;
  final stamp = createdAt
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[-:]'), '')
      .replaceAll(RegExp(r'\.\d+Z$'), 'Z');
  return '$prefix-$stamp';
}
