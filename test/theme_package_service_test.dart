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
    await _writePng(lightPreview, 0xff99bbdd);
    await _writePng(darkPreview, 0xff334455);
    const wallpaperRoot = '0123456789ABCDEF0123456789ABCDEF/cadi_wallpaper_new';
    final ota = Archive();
    ota.addFile(ArchiveFile.bytes(
      '$wallpaperRoot/light_preview_image.png',
      await lightPreview.readAsBytes(),
    ));
    ota.addFile(ArchiveFile.bytes(
      '$wallpaperRoot/dark_preview_image.png',
      await darkPreview.readAsBytes(),
    ));
    await otaZip.writeAsBytes(ZipEncoder().encode(ota));
    await report.writeAsString(jsonEncode(<String, dynamic>{
      'source_mode': 'legacy',
      'source_size': <int>[2198, 367],
      'wallpaper_root': wallpaperRoot,
      'preview_paths': <String, String>{
        'light': '$wallpaperRoot/light_preview_image.png',
        'dark': '$wallpaperRoot/dark_preview_image.png',
      },
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
    expect(
      archive.findFile('cwtheme/previews/light_preview_2198x367.png')!.content,
      await lightPreview.readAsBytes(),
    );

    final manifestFile = archive.findFile('cwtheme/manifest.json')!;
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;

    expect(manifest['displayName'], 'Night Drive');
    expect(manifest['packageType'], 'cadillac_ota6_wallpaper');
    expect(manifest['payload'], 'payload/ota_wallpaper.zip');
    expect(manifest['sourceSize'], <int>[2198, 367]);
    expect(manifest['sourceMode'], 'legacy');
    expect(manifest['lightMaster'], 'masters/light_master_2198x367.png');
    expect(manifest['androidInstall']['targetRoot'],
        '/sdcard/Download/paper/0123456789ABCDEF0123456789ABCDEF');
    expect(manifest['androidInstall']['targetFolder'], 'cadi_wallpaper_new');
    expect(manifest['androidInstall']['payloadFolderInZip'], wallpaperRoot);
    expect(manifest['androidInstall']['requiresManualSelectionInCarSettings'],
        isFalse);
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

  test('rejects an unsafe final OTA ZIP path before creating a theme',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('cwtheme_unsafe_');
    addTearDown(() => tempDir.delete(recursive: true));
    final otaZip = File(p.join(tempDir.path, 'ota.zip'));
    final ota = Archive();
    ota.addFile(
        ArchiveFile.bytes('../light_preview_image.png', <int>[1, 2, 3]));
    await otaZip.writeAsBytes(ZipEncoder().encode(ota));
    final report = File(p.join(tempDir.path, 'report.json'));
    await report.writeAsString('{}');

    await expectLater(
      ThemePackageService().createThemePackage(ThemePackageRequest(
        displayName: 'Unsafe',
        author: '',
        notes: '',
        createdAt: DateTime.utc(2026),
        lightMasterPath: 'unused.png',
        darkMasterPath: 'unused.png',
        otaZipPath: otaZip.path,
        reportPath: report.path,
        reportSummary: PackageReportSummary.fromJson(const <String, dynamic>{}),
        libraryRootPath: tempDir.path,
      )),
      throwsFormatException,
    );
  });

  test('stores native masters with native size and payload path', () async {
    final tempDir = await Directory.systemTemp.createTemp('cwtheme_native_');
    addTearDown(() => tempDir.delete(recursive: true));
    final nativeMaster = File(p.join(tempDir.path, 'native.png'));
    final nativeImage = img.Image(width: 8960, height: 1320, numChannels: 3);
    await nativeMaster.writeAsBytes(img.encodePng(nativeImage));

    final preview = File(p.join(tempDir.path, 'preview.png'));
    await _writePng(preview, 0xff223344);
    const wallpaperRoot =
        'ABCDEF0123456789ABCDEF0123456789/cadi_wallpaper_native';
    final ota = Archive();
    final previewBytes = await preview.readAsBytes();
    ota.addFile(ArchiveFile.bytes(
        '$wallpaperRoot/light_preview_image.png', previewBytes));
    ota.addFile(ArchiveFile.bytes(
        '$wallpaperRoot/dark_preview_image.png', previewBytes));
    final otaZip = File(p.join(tempDir.path, 'ota.zip'));
    await otaZip.writeAsBytes(ZipEncoder().encode(ota));
    final report = File(p.join(tempDir.path, 'report.json'));
    await report.writeAsString(jsonEncode(<String, dynamic>{
      'source_mode': 'native',
      'source_size': <int>[8960, 1320],
      'wallpaper_root': wallpaperRoot,
      'preview_paths': <String, String>{
        'light': '$wallpaperRoot/light_preview_image.png',
        'dark': '$wallpaperRoot/dark_preview_image.png',
      },
    }));

    final entry = await ThemePackageService().createThemePackage(
      ThemePackageRequest(
        displayName: 'Native',
        author: '',
        notes: '',
        createdAt: DateTime.utc(2026),
        lightMasterPath: nativeMaster.path,
        darkMasterPath: nativeMaster.path,
        otaZipPath: otaZip.path,
        reportPath: report.path,
        reportSummary: PackageReportSummary.fromJson(const <String, dynamic>{}),
        libraryRootPath: tempDir.path,
      ),
    );
    final archive = ZipDecoder().decodeBytes(
      await File(entry.cwthemePath).readAsBytes(),
    );
    final manifest = jsonDecode(utf8.decode(
      archive.findFile('cwtheme/manifest.json')!.content,
    )) as Map<String, dynamic>;

    expect(manifest['sourceSize'], <int>[8960, 1320]);
    expect(manifest['sourceMode'], 'native');
    expect(manifest['lightMaster'], 'masters/light_master_8960x1320.png');
    expect(archive.findFile('cwtheme/masters/light_master_8960x1320.png'),
        isNotNull);
    expect(manifest['androidInstall']['payloadFolderInZip'], wallpaperRoot);
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
