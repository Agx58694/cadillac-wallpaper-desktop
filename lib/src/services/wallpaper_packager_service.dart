import 'dart:convert';
import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/models/package_build_request.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_build_result.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_report_summary.dart';
import 'package:cadillac_wallpaper_desktop/src/services/path_redactor.dart';
import 'package:path/path.dart' as p;

typedef CliOutputSink = void Function(String line);

typedef ProcessRunner = Future<ProcessResult> Function(
  String command,
  List<String> arguments,
  String? workingDirectory, {
  CliOutputSink? onOutput,
});

class PackagerException implements Exception {
  const PackagerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WallpaperPackagerService {
  WallpaperPackagerService({
    String? pythonExecutable,
    String? packagerScript,
    String? packagerExecutable,
    ProcessRunner? processRunner,
  })  : pythonExecutable = pythonExecutable ?? _defaultPythonExecutable(),
        packagerScript = packagerScript ?? defaultPackagerScript(),
        packagerExecutable =
            packagerExecutable ?? Platform.environment['CADILLAC_PACKAGER_CLI'],
        _processRunner = processRunner ?? _runProcess;

  final String pythonExecutable;
  final String packagerScript;
  final String? packagerExecutable;
  final ProcessRunner _processRunner;

  static String defaultPackagerScript() {
    final envPath = Platform.environment['CADILLAC_PACKAGER_SCRIPT'];
    if (envPath != null && envPath.isNotEmpty) {
      return envPath;
    }

    final fromProjectParent = p.normalize(
      p.join(Directory.current.path, '..', 'cadillac_wallpaper_packager.py'),
    );
    if (File(fromProjectParent).existsSync()) {
      return fromProjectParent;
    }

    final fromProjectPackager = p.normalize(
      p.join(
          Directory.current.path, 'packager', 'cadillac_wallpaper_packager.py'),
    );
    if (File(fromProjectPackager).existsSync()) {
      return fromProjectPackager;
    }

    final bundledScript =
        bundledAssetPath('packager/cadillac_wallpaper_packager.py');
    if (bundledScript != null) {
      return bundledScript;
    }

    return fromProjectPackager;
  }

  static String? bundledAssetPath(String relativePath) {
    for (final root in _flutterAssetRootCandidates()) {
      final candidate = p.normalize(p.join(root, relativePath));
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<PackageBuildResult> buildPackage(
    PackageBuildRequest request, {
    CliOutputSink? onCliOutput,
  }) async {
    final command = packagerExecutable?.isNotEmpty == true
        ? packagerExecutable!
        : pythonExecutable;
    final arguments = packagerExecutable?.isNotEmpty == true
        ? request.toCliArguments()
        : <String>[packagerScript, ...request.toCliArguments()];
    final workingDirectory = packagerExecutable?.isNotEmpty == true
        ? Directory.current.path
        : p.dirname(packagerScript);

    final ProcessResult result;
    try {
      result = await _processRunner(
        command,
        arguments,
        workingDirectory,
        onOutput: onCliOutput,
      );
    } on Object catch (error) {
      throw PackagerException(redactSensitivePaths(
        '无法启动打包 CLI\n'
        'command: $command\n'
        'workingDirectory: $workingDirectory\n'
        'error: $error',
      ));
    }
    if (result.exitCode != 0) {
      throw PackagerException(redactSensitivePaths(
        '打包 CLI 失败 exit=${result.exitCode}\n'
        'stdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}',
      ));
    }

    final reportFile = File(request.reportPath);
    if (!reportFile.existsSync()) {
      throw PackagerException(
        redactSensitivePaths('打包成功但未生成 report.json: ${request.reportPath}'),
      );
    }

    final reportJson = jsonDecode(await reportFile.readAsString());
    if (reportJson is! Map<String, dynamic>) {
      throw const PackagerException('report.json 格式不是 JSON object');
    }

    return PackageBuildResult(
      outputZipPath: request.outputZipPath,
      reportPath: request.reportPath,
      workDirPath: request.workDirPath,
      reportJson: reportJson,
      reportSummary: PackageReportSummary.fromJson(
        reportJson,
        maxStitchMae: request.maxStitchMae,
      ),
      stdout: redactSensitivePaths(result.stdout),
      stderr: redactSensitivePaths(result.stderr),
    );
  }
}

List<String> _flutterAssetRootCandidates() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  return <String>[
    if (Platform.isMacOS)
      p.normalize(
        p.join(
          executableDir,
          '..',
          'Frameworks',
          'App.framework',
          'Resources',
          'flutter_assets',
        ),
      ),
    if (Platform.isWindows)
      p.normalize(p.join(executableDir, 'data', 'flutter_assets')),
    p.normalize(p.join(Directory.current.path, 'build', 'flutter_assets')),
    Directory.current.path,
  ];
}

String _defaultPythonExecutable() {
  final envPath = Platform.environment['CADILLAC_PYTHON'];
  if (envPath != null && envPath.isNotEmpty) {
    return envPath;
  }

  final candidates = <String>[
    if (Platform.isMacOS) ...<String>[
      '/opt/homebrew/anaconda3/bin/python3',
      '/opt/anaconda3/bin/python3',
      '/opt/homebrew/bin/python3',
      '/usr/local/bin/python3',
      '/usr/bin/python3',
    ],
    if (Platform.isWindows) ...<String>[
      'python',
      'py',
    ],
    if (!Platform.isWindows) 'python3',
  ];
  for (final candidate in candidates) {
    if (_pythonCanImportPillow(candidate)) {
      return candidate;
    }
  }
  return Platform.isWindows ? 'python' : 'python3';
}

bool _pythonCanImportPillow(String executable) {
  try {
    final result = Process.runSync(
      executable,
      <String>['-c', 'import PIL'],
      runInShell: Platform.isWindows,
    );
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}

Future<ProcessResult> _runProcess(
  String command,
  List<String> arguments,
  String? workingDirectory, {
  CliOutputSink? onOutput,
}) async {
  final process = await Process.start(
    command,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();

  Future<void> collectOutput(
    Stream<List<int>> stream,
    StringBuffer buffer, {
    required bool isStderr,
  }) async {
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final redactedLine = redactSensitivePaths(line);
      buffer.writeln(redactedLine);
      if (line.trim().isEmpty) {
        continue;
      }
      onOutput?.call(isStderr ? 'stderr: $redactedLine' : redactedLine);
    }
  }

  final stdoutFuture = collectOutput(
    process.stdout,
    stdoutBuffer,
    isStderr: false,
  );
  final stderrFuture = collectOutput(
    process.stderr,
    stderrBuffer,
    isStderr: true,
  );
  final exitCode = await process.exitCode;
  await Future.wait(<Future<void>>[stdoutFuture, stderrFuture]);

  return ProcessResult(
    process.pid,
    exitCode,
    stdoutBuffer.toString(),
    stderrBuffer.toString(),
  );
}
