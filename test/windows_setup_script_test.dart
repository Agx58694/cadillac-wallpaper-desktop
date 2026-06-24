import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('windows setup script checks and installs required build tools',
      () async {
    final setupScript = await File(
      'scripts/setup_and_build_windows.ps1',
    ).readAsString();
    final releaseScript = await File(
      'scripts/build_windows_release.ps1',
    ).readAsString();
    final oneClickScript = await File(
      'build_windows_one_click.cmd',
    ).readAsString();

    expect(setupScript, contains('Microsoft.VisualStudio.2022.BuildTools'));
    expect(setupScript, contains('Microsoft.VisualStudio.Workload.VCTools'));
    expect(setupScript, contains('Python.Python.3.12'));
    expect(setupScript, contains('Git.Git'));
    expect(setupScript, contains('Microsoft.NuGet'));
    expect(setupScript, contains('flutter_windows_'));
    expect(
        setupScript, contains('pip", "install", "--upgrade", "pip", "Pillow"'));
    expect(setupScript, contains('build_windows_release.ps1'));
    expect(releaseScript, contains(r'$SkipTests'));
    expect(oneClickScript, contains('setup_and_build_windows.ps1'));
    expect(oneClickScript, contains('-ExecutionPolicy Bypass'));
  });
}
