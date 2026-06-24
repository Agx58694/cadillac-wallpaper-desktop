import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundles the Windows astcenc executable for release builds', () async {
    const assetPath = 'packager/tools/windows/astcenc.exe';
    final pubspec = await File('pubspec.yaml').readAsString();
    final appSource = await File('lib/src/app.dart').readAsString();

    expect(File(assetPath).existsSync(), isTrue);
    expect(pubspec, contains(assetPath));
    expect(appSource, contains(assetPath));
  });
}
