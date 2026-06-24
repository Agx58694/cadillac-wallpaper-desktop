import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_report_summary.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_package_request.dart';
import 'package:cadillac_wallpaper_desktop/src/services/theme_package_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  test('creates cwtheme with manifest, previews, masters, payload, and report',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('cwtheme_service_');
    addTearDown(() => tempDir.delete(recursive: true));

    final lightMaster = File(p.join(tempDir.path, 'light_master.png'));
    final darkMaster = File(p.join(tempDir.path, 'dark_master.png'));
    final lightPreview = File(p.join(tempDir.path, 'light_preview_image.png'));
    final darkPreview = File(p.join(tempDir.path, 'dark_preview_image.png'));
    final otaZip = File(p.join(tempDir.path, 'ota_wallpaper.zip'));
    final report = File(p.join(tempDir.path, 'package-report.json'));

    await _writePng(lightMaster, 0xffd9ecff);
    await _writePng(darkMaster, 0xff101827);
    await _writePng(lightPreview, 0xffd9ecff);
    await _writePng(darkPreview, 0xff101827);
    await otaZip.writeAsBytes(<int>[80, 75, 3, 4]);
    await report.writeAsString(jsonEncode(<String, dynamic>{
      'zip_test_bad_file': null,
      'zip_names_identical_order': true,
      'pngs': <String, dynamic>{},
      'kzb': <String, dynamic>{
        'source_kzb_size': 1,
        'patched_kzb_size': 1,
        'record0_preserved': true,
        'record_offsets_same': <bool>[true],
      },
    }));

    final service = ThemePackageService();
    final entry = await service.createThemePackage(
      ThemePackageRequest(
        displayName: 'Night Drive',
        author: 'Cadillac Lab',
        notes: 'For Android sync',
        createdAt: DateTime.utc(2026, 6, 22, 8, 30),
        lightMasterPath: lightMaster.path,
        darkMasterPath: darkMaster.path,
        lightPreviewPath: lightPreview.path,
        darkPreviewPath: darkPreview.path,
        otaZipPath: otaZip.path,
        reportPath: report.path,
        reportSummary: PackageReportSummary.fromJson(
          jsonDecode(await report.readAsString()) as Map<String, dynamic>,
        ),
        libraryRootPath: tempDir.path,
      ),
    );

    final archive = ZipDecoder().decodeBytes(
      await File(entry.cwthemePath).readAsBytes(),
    );
    final names = archive.files.map((file) => file.name).toSet();

    expect(names, contains('cwtheme/manifest.json'));
    expect(names, contains('cwtheme/previews/light_preview_2198x367.png'));
    expect(names, contains('cwtheme/previews/dark_preview_2198x367.png'));
    expect(names, contains('cwtheme/previews/thumbnail_light.png'));
    expect(names, contains('cwtheme/previews/thumbnail_dark.png'));
    expect(names, contains('cwtheme/masters/light_master_2198x367.png'));
    expect(names, contains('cwtheme/masters/dark_master_2198x367.png'));
    expect(names, contains('cwtheme/payload/ota_wallpaper.zip'));
    expect(names, contains('cwtheme/report/package-report.json'));

    final manifestFile = archive.findFile('cwtheme/manifest.json')!;
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;

    expect(manifest['displayName'], 'Night Drive');
    expect(manifest['packageType'], 'cadillac_ota6_wallpaper');
    expect(manifest['payload'], 'payload/ota_wallpaper.zip');
    expect(manifest['androidInstall']['requiresManualSelectionInCarSettings'],
        isTrue);
    expect(File(entry.lightThumbnailPath).existsSync(), isTrue);
    expect(File(entry.darkThumbnailPath).existsSync(), isTrue);

    final packageDir = Directory(p.dirname(entry.cwthemePath));
    expect(p.basename(packageDir.path), 'package');
    expect(
      packageDir
          .listSync()
          .whereType<File>()
          .map((file) => p.basename(file.path))
          .toList(),
      <String>[p.basename(entry.cwthemePath)],
    );
    expect(p.basename(p.dirname(entry.lightThumbnailPath)), 'library-cache');
    expect(p.basename(p.dirname(entry.darkThumbnailPath)), 'library-cache');
  });
}

Future<void> _writePng(File file, int color) async {
  final image = img.Image(width: 2198, height: 367);
  img.fill(image,
      color: img.ColorUint32.rgba(
        (color >> 16) & 0xff,
        (color >> 8) & 0xff,
        color & 0xff,
        (color >> 24) & 0xff,
      ));
  await file.writeAsBytes(img.encodePng(image));
}
