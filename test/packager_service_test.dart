import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/models/package_build_request.dart';
import 'package:cadillac_wallpaper_desktop/src/services/wallpaper_packager_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('finds bundled packager resources from the project assets', () {
    final script = WallpaperPackagerService.bundledAssetPath(
      'packager/cadillac_wallpaper_packager.py',
    );

    expect(script, isNotNull);
    expect(File(script!).existsSync(), isTrue);
  });

  test('builds a shared CLI invocation for both desktop modes', () async {
    final calls = <ProcessCall>[];
    final tempDir = await Directory.systemTemp.createTemp('packager_service_');
    addTearDown(() => tempDir.delete(recursive: true));

    final report = File(p.join(tempDir.path, 'package-report.json'));
    await report.writeAsString('{"zip_test_bad_file":null}');

    final service = WallpaperPackagerService(
      pythonExecutable: 'python3',
      packagerScript: p.join(tempDir.path, 'cadillac_wallpaper_packager.py'),
      processRunner: (command, arguments, workingDirectory, {onOutput}) async {
        calls.add(ProcessCall(command, arguments, workingDirectory));
        return ProcessResult(42, 0, '{"ok":true}', '');
      },
    );

    final result = await service.buildPackage(
      PackageBuildRequest(
        lightImagePath: '/images/light.png',
        darkImagePath: '/images/dark.png',
        outputZipPath: p.join(tempDir.path, 'wallpaper.zip'),
        workDirPath: p.join(tempDir.path, 'work'),
        reportPath: report.path,
      ),
    );

    expect(result.reportPath, report.path);
    expect(calls, hasLength(1));
    expect(calls.single.command, 'python3');
    expect(
      calls.single.arguments,
      containsAllInOrder(<String>[
        p.join(tempDir.path, 'cadillac_wallpaper_packager.py'),
        '--light-image',
        '/images/light.png',
        '--dark-image',
        '/images/dark.png',
        '--output-zip',
        p.join(tempDir.path, 'wallpaper.zip'),
        '--work-dir',
        p.join(tempDir.path, 'work'),
        '--report',
        report.path,
      ]),
    );
  });

  test('throws when the packager process fails', () async {
    final tempDir = await Directory.systemTemp.createTemp('packager_fail_');
    addTearDown(() => tempDir.delete(recursive: true));

    final service = WallpaperPackagerService(
      pythonExecutable: 'python3',
      packagerScript: p.join(tempDir.path, 'cadillac_wallpaper_packager.py'),
      processRunner: (command, arguments, workingDirectory, {onOutput}) async {
        return ProcessResult(7, 2, 'stdout text', 'stderr text');
      },
    );

    expect(
      () => service.buildPackage(
        PackageBuildRequest(
          lightImagePath: '/images/light.png',
          darkImagePath: '/images/dark.png',
          outputZipPath: p.join(tempDir.path, 'wallpaper.zip'),
          workDirPath: p.join(tempDir.path, 'work'),
          reportPath: p.join(tempDir.path, 'package-report.json'),
        ),
      ),
      throwsA(isA<PackagerException>()),
    );
  });

  test('redacts sensitive paths from packager failures', () async {
    final tempDir = await Directory.systemTemp.createTemp('packager_redact_');
    addTearDown(() => tempDir.delete(recursive: true));
    final home =
        Platform.environment['HOME'] ?? p.posix.join('/', 'Users', 'localuser');

    final service = WallpaperPackagerService(
      pythonExecutable: 'python3',
      packagerScript: p.join(tempDir.path, 'cadillac_wallpaper_packager.py'),
      processRunner: (command, arguments, workingDirectory, {onOutput}) async {
        return ProcessResult(
          8,
          2,
          'stdout path $home/Pictures/light.png',
          'stderr path $home/Library/private.txt',
        );
      },
    );

    try {
      await service.buildPackage(
        PackageBuildRequest(
          lightImagePath: p.join(home, 'Pictures', 'light.png'),
          darkImagePath: p.join(home, 'Pictures', 'dark.png'),
          outputZipPath: p.join(tempDir.path, 'wallpaper.zip'),
          workDirPath: p.join(tempDir.path, 'work'),
          reportPath: p.join(tempDir.path, 'package-report.json'),
        ),
      );
      fail('expected PackagerException');
    } on PackagerException catch (error) {
      final message = error.toString();
      expect(message, isNot(contains(home)));
      expect(message, contains('<HOME>'));
    }
  });

  test('wraps process start errors as packager exceptions', () async {
    final tempDir = await Directory.systemTemp.createTemp('packager_start_');
    addTearDown(() => tempDir.delete(recursive: true));

    final service = WallpaperPackagerService(
      pythonExecutable: 'python3',
      packagerScript: p.join(tempDir.path, 'cadillac_wallpaper_packager.py'),
      processRunner: (command, arguments, workingDirectory, {onOutput}) async {
        throw const FileSystemException('missing working directory');
      },
    );

    expect(
      () => service.buildPackage(
        PackageBuildRequest(
          lightImagePath: '/images/light.png',
          darkImagePath: '/images/dark.png',
          outputZipPath: p.join(tempDir.path, 'wallpaper.zip'),
          workDirPath: p.join(tempDir.path, 'work'),
          reportPath: p.join(tempDir.path, 'package-report.json'),
        ),
      ),
      throwsA(isA<PackagerException>()),
    );
  });

  test('streams CLI output to the caller while packaging runs', () async {
    final tempDir = await Directory.systemTemp.createTemp('packager_stream_');
    addTearDown(() => tempDir.delete(recursive: true));

    final script = File(p.join(tempDir.path, 'fake_packager.sh'));
    await script.writeAsString('''
#!/bin/sh
echo "[cadillac-packager] step 1/2 fake start"
sleep 0.05
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --report)
      report="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '{"zip_test_bad_file":null}' > "\$report"
echo "[cadillac-packager] step 2/2 fake done"
''');
    await Process.run('chmod', <String>['755', script.path]);

    final service = WallpaperPackagerService(
      packagerExecutable: script.path,
    );
    final streamed = <String>[];

    await service.buildPackage(
      PackageBuildRequest(
        lightImagePath: '/images/light.png',
        darkImagePath: '/images/dark.png',
        outputZipPath: p.join(tempDir.path, 'wallpaper.zip'),
        workDirPath: p.join(tempDir.path, 'work'),
        reportPath: p.join(tempDir.path, 'package-report.json'),
      ),
      onCliOutput: streamed.add,
    );

    expect(
      streamed,
      containsAllInOrder(<String>[
        '[cadillac-packager] step 1/2 fake start',
        '[cadillac-packager] step 2/2 fake done',
      ]),
    );
  });
}

class ProcessCall {
  const ProcessCall(this.command, this.arguments, this.workingDirectory);

  final String command;
  final List<String> arguments;
  final String? workingDirectory;
}
