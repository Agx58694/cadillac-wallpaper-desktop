import 'dart:io';

enum DesktopPlatform {
  macos,
  windows,
  linux,
}

typedef FolderOpenRunner = Future<ProcessResult> Function(
  String command,
  List<String> arguments, {
  bool runInShell,
});

class FolderOpenException implements Exception {
  const FolderOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FolderOpenerService {
  FolderOpenerService({
    DesktopPlatform? platform,
    FolderOpenRunner? runner,
  })  : platform = platform ?? currentPlatform(),
        _runner = runner ?? Process.run;

  final DesktopPlatform platform;
  final FolderOpenRunner _runner;

  static DesktopPlatform currentPlatform() {
    if (Platform.isMacOS) {
      return DesktopPlatform.macos;
    }
    if (Platform.isWindows) {
      return DesktopPlatform.windows;
    }
    return DesktopPlatform.linux;
  }

  Future<String> openFolder(String folderPath) async {
    final folder = Directory(folderPath);
    if (!folder.existsSync()) {
      throw FolderOpenException('文件夹不存在: $folderPath');
    }

    final command = _commandFor(platform, folderPath);
    final result = await _runner(
      command.executable,
      command.arguments,
      runInShell: platform == DesktopPlatform.windows,
    );
    if (result.exitCode != 0) {
      throw FolderOpenException(
        '打开文件夹失败 exit=${result.exitCode}\n'
        'stdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}',
      );
    }
    return folderPath;
  }
}

_OpenCommand _commandFor(DesktopPlatform platform, String folderPath) {
  switch (platform) {
    case DesktopPlatform.macos:
      return _OpenCommand('open', <String>[folderPath]);
    case DesktopPlatform.windows:
      return _OpenCommand('explorer', <String>[folderPath]);
    case DesktopPlatform.linux:
      return _OpenCommand('xdg-open', <String>[folderPath]);
  }
}

class _OpenCommand {
  const _OpenCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
