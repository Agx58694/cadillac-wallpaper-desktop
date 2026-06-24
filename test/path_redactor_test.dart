import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/services/path_redactor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('redacts home, temp, and Windows user paths in log text', () {
    final home = Platform.environment['HOME'];
    final fallbackHome = p.posix.join('/', 'Users', 'localuser');
    final homePath = home == null ? fallbackHome : p.join(home, 'secret');
    final tempPath = p.join(Directory.systemTemp.path, 'cadillac-run');
    final windowsHome = p.windows.join('C:', 'Users', 'alice');
    final windowsPath =
        p.windows.join(windowsHome, 'Pictures', 'wallpaper.png');

    final redacted = redactSensitivePaths(
      'home=$homePath temp=$tempPath win=$windowsPath',
    );

    if (home != null) {
      expect(redacted, isNot(contains(home)));
    }
    expect(redacted, isNot(contains(Directory.systemTemp.path)));
    expect(redacted, isNot(contains(windowsHome)));
    expect(redacted, contains('<HOME>'));
    expect(redacted, contains('<TEMP>'));
  });
}
