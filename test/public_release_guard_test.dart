import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public source does not bundle private OTA template zips', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final gitignore = await File('.gitignore').readAsString();
    final buildKitScript =
        await File('scripts/make_windows_build_kit.sh').readAsString();

    expect(pubspec, isNot(contains('packager/templates/')));
    expect(gitignore, contains('packager/templates/*.zip'));
    expect(buildKitScript, contains('packager/templates/*.zip'));
    expect(buildKitScript, contains('CADILLAC_INCLUDE_PRIVATE_TEMPLATE'));
  });

  test('public docs do not contain local user paths', () async {
    final docs = <String>[
      'README.md',
      'CONTRIBUTING.md',
      'SECURITY.md',
      'DISCLAIMER.md',
      'THIRD_PARTY_NOTICES.md',
      'docs/open-source-release-checklist.md',
      'WINDOWS_BUILD_README.txt',
    ];
    final localPathPattern = RegExp(
      r'(/Users/[A-Za-z0-9._-]+|C:\\Users\\[A-Za-z0-9._-]+)',
    );

    for (final path in docs) {
      final content = await File(path).readAsString();
      expect(content, isNot(matches(localPathPattern)), reason: path);
    }
  });
}
