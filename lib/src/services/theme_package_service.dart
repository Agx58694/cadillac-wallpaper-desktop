import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_build_request.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_library_entry.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_package_request.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class ThemePackageService {
  Future<ThemeLibraryEntry> createThemePackage(
      ThemePackageRequest request) async {
    final otaBytes = await File(request.otaZipPath).readAsBytes();
    final ota = ZipDecoder().decodeBytes(otaBytes);
    final root = _wallpaperRoot(ota);
    final report = jsonDecode(await File(request.reportPath).readAsString());
    if (report is! Map<String, dynamic>) {
      throw const FormatException('打包报告不是 JSON object');
    }
    if (report['wallpaper_root'] != null && report['wallpaper_root'] != root) {
      throw const FormatException('打包报告与最终 OTA ZIP 的壁纸目录不一致');
    }

    final lightPreviewName = '$root/light_preview_image.png';
    final darkPreviewName = '$root/dark_preview_image.png';
    final reportPreviews = report['preview_paths'];
    if (reportPreviews != null &&
        (reportPreviews is! Map ||
            reportPreviews['light'] != lightPreviewName ||
            reportPreviews['dark'] != darkPreviewName)) {
      throw const FormatException('打包报告与最终 OTA ZIP 的预览路径不一致');
    }
    final lightPreview = _previewBytes(ota, lightPreviewName);
    final darkPreview = _previewBytes(ota, darkPreviewName);

    final lightSize = await _imageSize(request.lightMasterPath);
    final darkSize = await _imageSize(request.darkMasterPath);
    if (lightSize[0] != darkSize[0] || lightSize[1] != darkSize[1]) {
      throw const FormatException('日夜母图尺寸必须相同');
    }
    final sourceMode = WallpaperSourceMode.fromSize(lightSize[0], lightSize[1]);
    if (sourceMode == null) {
      throw const FormatException('母图尺寸只支持 8960×1320 或 2198×367');
    }
    final reportSize = report['source_size'];
    if (reportSize != null &&
        (reportSize is! List ||
            reportSize.length != 2 ||
            reportSize[0] != lightSize[0] ||
            reportSize[1] != lightSize[1])) {
      throw const FormatException('打包报告与母图尺寸不一致');
    }
    if (report['source_mode'] != null &&
        report['source_mode'] != sourceMode.name) {
      throw const FormatException('打包报告与母图模式不一致');
    }

    final dimensions = '${lightSize[0]}x${lightSize[1]}';
    final lightMasterName = 'masters/light_master_$dimensions.png';
    final darkMasterName = 'masters/dark_master_$dimensions.png';
    final themeId = _themeId(request.displayName, request.createdAt);
    final themeDir =
        Directory(p.join(request.libraryRootPath, 'themes', themeId));
    final packageDir = Directory(p.join(themeDir.path, 'package'));
    final cacheDir = Directory(p.join(themeDir.path, 'library-cache'));
    await packageDir.create(recursive: true);
    await cacheDir.create(recursive: true);

    final lightThumbnail = File(p.join(cacheDir.path, 'thumbnail_light.png'));
    final darkThumbnail = File(p.join(cacheDir.path, 'thumbnail_dark.png'));
    await _writeThumbnail(lightPreview, lightThumbnail.path);
    await _writeThumbnail(darkPreview, darkThumbnail.path);

    final manifest = _manifest(
      themeId,
      request,
      sourceSize: lightSize,
      sourceMode: sourceMode,
      wallpaperRoot: root,
      lightMasterName: lightMasterName,
      darkMasterName: darkMasterName,
    );
    final archive = Archive();
    await _addString(archive, 'cwtheme/manifest.json', manifest);
    _addBytes(
      archive,
      'cwtheme/previews/light_preview_2198x367.png',
      lightPreview,
    );
    _addBytes(
      archive,
      'cwtheme/previews/dark_preview_2198x367.png',
      darkPreview,
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
      'cwtheme/$lightMasterName',
      request.lightMasterPath,
    );
    await _addFile(
      archive,
      'cwtheme/$darkMasterName',
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

Map<String, dynamic> _manifest(
  String themeId,
  ThemePackageRequest request, {
  required List<int> sourceSize,
  required WallpaperSourceMode sourceMode,
  required String wallpaperRoot,
  required String lightMasterName,
  required String darkMasterName,
}) {
  final parts = wallpaperRoot.split('/');
  final targetRoot = parts[0];
  final targetFolder = parts[1];
  return <String, dynamic>{
    'schemaVersion': 1,
    'themeId': themeId,
    'displayName': request.displayName,
    'author': request.author,
    'notes': request.notes,
    'createdAt': request.createdAt.toIso8601String(),
    'sourceSize': sourceSize,
    'sourceMode': sourceMode.name,
    'packageType': 'cadillac_ota6_wallpaper',
    'payload': 'payload/ota_wallpaper.zip',
    'lightPreview': 'previews/light_preview_2198x367.png',
    'darkPreview': 'previews/dark_preview_2198x367.png',
    'lightThumbnail': 'previews/thumbnail_light.png',
    'darkThumbnail': 'previews/thumbnail_dark.png',
    'lightMaster': lightMasterName,
    'darkMaster': darkMasterName,
    'report': 'report/package-report.json',
    'checks': request.reportSummary.toManifestChecks(),
    'checkDetails': request.reportSummary.toStatusMap(),
    'androidInstall': <String, dynamic>{
      'targetRoot': '/sdcard/Download/paper/$targetRoot',
      'targetFolder': targetFolder,
      'payloadZip': 'payload/ota_wallpaper.zip',
      'payloadFolderInZip': wallpaperRoot,
      'requiresManualSelectionInCarSettings': false,
    },
  };
}

String _wallpaperRoot(Archive archive) {
  final names = <String>{};
  final roots = <String>{};
  final previewPattern = RegExp(
    r'^([A-Fa-f0-9]{32})/(cadi_wallpaper[A-Za-z0-9_-]*)/light_preview_image\.png$',
  );
  for (final file in archive.files) {
    final name = file.name;
    final components = name.split('/');
    if (name.startsWith('/') ||
        name.contains('//') ||
        name.contains('\\') ||
        components.any((part) => part == '.' || part == '..') ||
        !names.add(name)) {
      throw FormatException('OTA ZIP 含不安全或重复路径: $name');
    }
    final match = previewPattern.firstMatch(name);
    if (match != null) roots.add('${match[1]}/${match[2]}');
  }
  if (roots.length != 1) {
    throw const FormatException('OTA ZIP 必须有唯一的壁纸预览目录');
  }
  final root = roots.single;
  for (final file in archive.files) {
    if (file.isFile && !file.name.startsWith('$root/')) {
      throw FormatException('OTA ZIP 文件超出壁纸目录: ${file.name}');
    }
  }
  return root;
}

Uint8List _previewBytes(Archive archive, String path) {
  final file = archive.findFile(path);
  if (file == null || !file.isFile) {
    throw FormatException('OTA ZIP 缺少预览图: $path');
  }
  final bytes = Uint8List.fromList(file.content);
  final image = img.decodeImage(bytes);
  if (image == null || image.width != 2198 || image.height != 367) {
    throw FormatException('OTA ZIP 预览图尺寸错误: $path');
  }
  return bytes;
}

Future<List<int>> _imageSize(String path) async {
  final image = img.decodeImage(await File(path).readAsBytes());
  if (image == null) throw FormatException('无法读取母图 PNG: $path');
  return <int>[image.width, image.height];
}

void _addBytes(Archive archive, String path, Uint8List bytes) {
  archive.addFile(ArchiveFile.bytes(path, bytes));
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

Future<void> _writeThumbnail(Uint8List sourceBytes, String outputPath) async {
  final source = img.decodeImage(sourceBytes);
  if (source == null) {
    throw const FormatException('无法读取最终 OTA ZIP 中的预览 PNG');
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
