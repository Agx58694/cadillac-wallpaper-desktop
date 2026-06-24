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

typedef PythonDependencyChecker = bool Function(String executable);

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
    bool? validatePythonDependencies,
    PythonDependencyChecker? pythonDependencyChecker,
  })  : pythonExecutable = pythonExecutable ??
            ((packagerExecutable ?? _defaultPackagerExecutable())?.isNotEmpty ==
                    true
                ? _fallbackPythonExecutable()
                : _defaultPythonExecutable()),
        packagerScript = packagerScript ?? defaultPackagerScript(),
        packagerExecutable = packagerExecutable ?? _defaultPackagerExecutable(),
        _processRunner = processRunner ?? _runProcess,
        _validatePythonDependencies =
            validatePythonDependencies ?? processRunner == null,
        _pythonDependencyChecker =
            pythonDependencyChecker ?? _pythonCanImportPillow;

  final String pythonExecutable;
  final String packagerScript;
  final String? packagerExecutable;
  final ProcessRunner _processRunner;
  final bool _validatePythonDependencies;
  final PythonDependencyChecker _pythonDependencyChecker;

  String get runtimeDescription {
    if (packagerExecutable?.isNotEmpty == true) {
      return packagerExecutable!;
    }
    return '$pythonExecutable $packagerScript';
  }

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
    final usesPackagerExecutable = packagerExecutable?.isNotEmpty == true;
    if (!usesPackagerExecutable &&
        _validatePythonDependencies &&
        !_pythonDependencyChecker(pythonExecutable)) {
      throw PackagerException(_missingPillowMessage(pythonExecutable));
    }

    final command =
        usesPackagerExecutable ? packagerExecutable! : pythonExecutable;
    final arguments = usesPackagerExecutable
        ? request.toCliArguments()
        : <String>[packagerScript, ...request.toCliArguments()];
    final workingDirectory = usesPackagerExecutable
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
      final combinedOutput = '${result.stdout}\n${result.stderr}';
      if (!usesPackagerExecutable &&
          combinedOutput.contains("No module named 'PIL'")) {
        throw PackagerException(redactSensitivePaths(
          '${_missingPillowMessage(pythonExecutable)}\n\n'
          'stdout:\n${result.stdout}\n'
          'stderr:\n${result.stderr}',
        ));
      }
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

String? _defaultPackagerExecutable() {
  final envPath = Platform.environment['CADILLAC_PACKAGER_CLI'];
  if (envPath != null && envPath.isNotEmpty) {
    return envPath;
  }

  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final executableName = Platform.isWindows
      ? 'cadillac_wallpaper_packager.exe'
      : 'cadillac_wallpaper_packager';
  final candidates = <String>[
    p.join(executableDir, 'packager_runtime', executableName),
    p.join(executableDir, executableName),
    if (Platform.isWindows)
      p.join(
        executableDir,
        'data',
        'flutter_assets',
        'packager',
        executableName,
      ),
  ];

  for (final candidate in candidates) {
    final normalized = p.normalize(candidate);
    if (File(normalized).existsSync()) {
      return normalized;
    }
  }
  return null;
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

String _fallbackPythonExecutable() {
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

String _missingPillowMessage(String executable) {
  final installCommand = '$executable -m pip install Pillow';
  return '当前 Python 不能加载 Pillow。\n'
      'Python: $executable\n'
      '请先安装 Pillow: $installCommand\n'
      '或者设置 CADILLAC_PYTHON 指向已经安装 Pillow 的 Python。';
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
