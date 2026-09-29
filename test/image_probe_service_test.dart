import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/models/package_build_request.dart';
import 'package:cadillac_wallpaper_desktop/src/services/image_probe_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  test('inspects required 2198x367 PNG dimensions and alpha range', () async {
    final tempDir = await Directory.systemTemp.createTemp('image_probe_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'master.png'));

    final image = img.Image(width: 2198, height: 367, numChannels: 4);
    img.fill(image, color: img.ColorUint8.rgba(10, 20, 30, 255));
    image.setPixelRgba(0, 0, 10, 20, 30, 0);
    await file.writeAsBytes(img.encodePng(image));

    final probe = await ImageProbeService().inspect(file.path);

    expect(probe.width, 2198);
    expect(probe.height, 367);
    expect(probe.hasAlpha, isTrue);
    expect(probe.alphaMin, 0);
    expect(probe.alphaMax, 255);
    expect(probe.isRequiredPreviewSize, isTrue);
    expect(probe.sourceMode, WallpaperSourceMode.legacy);
  });

  test('recognizes native and legacy sizes without accepting mixed geometry',
      () {
    expect(
        WallpaperSourceMode.fromSize(8960, 1320), WallpaperSourceMode.native);
    expect(WallpaperSourceMode.fromSize(2198, 367), WallpaperSourceMode.legacy);
    expect(WallpaperSourceMode.fromSize(8920, 1320), isNull);
    expect(WallpaperSourceMode.fromSize(8960, 367), isNull);
    const transparentNative = ImageProbe(
      path: 'native.png',
      width: 8960,
      height: 1320,
      hasAlpha: true,
      alphaMin: 0,
      alphaMax: 255,
    );
    expect(transparentNative.isSupportedSize, isTrue);
    expect(transparentNative.isValidForBuild, isFalse);
  });

  test('rejects a JPEG renamed with a PNG extension', () async {
    final tempDir = await Directory.systemTemp.createTemp('image_probe_jpeg_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'renamed.png'));
    await file.writeAsBytes(img.encodeJpg(img.Image(width: 8, height: 8)));

    await expectLater(
        ImageProbeService().inspect(file.path), throwsFormatException);
  });

  test('throws a format exception for unreadable image files', () async {
    final tempDir = await Directory.systemTemp.createTemp('image_probe_bad_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File(p.join(tempDir.path, 'bad.png'));
    await file.writeAsString('not a png');

    expect(
      () => ImageProbeService().inspect(file.path),
      throwsA(isA<FormatException>()),
    );
  });
}
