import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/services/folder_opener_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens folders with the macOS open command', () async {
    final tempDir = await Directory.systemTemp.createTemp('folder_open_');
    addTearDown(() => tempDir.delete(recursive: true));
    final calls = <_OpenCall>[];

    final service = FolderOpenerService(
      platform: DesktopPlatform.macos,
      runner: (command, arguments, {bool runInShell = false}) async {
        calls.add(_OpenCall(command, arguments, runInShell));
        return ProcessResult(1, 0, '', '');
      },
    );

    final openedPath = await service.openFolder(tempDir.path);

    expect(openedPath, tempDir.path);
    expect(calls.single.command, 'open');
    expect(calls.single.arguments, <String>[tempDir.path]);
    expect(calls.single.runInShell, isFalse);
  });

  test('opens folders with Windows explorer through the shell', () async {
    final tempDir = await Directory.systemTemp.createTemp('folder_open_');
    addTearDown(() => tempDir.delete(recursive: true));
    final calls = <_OpenCall>[];

    final service = FolderOpenerService(
      platform: DesktopPlatform.windows,
      runner: (command, arguments, {bool runInShell = false}) async {
        calls.add(_OpenCall(command, arguments, runInShell));
        return ProcessResult(2, 0, '', '');
      },
    );

    await service.openFolder(tempDir.path);

    expect(calls.single.command, 'explorer');
    expect(calls.single.arguments, <String>[tempDir.path]);
    expect(calls.single.runInShell, isTrue);
  });

  test('throws when the output folder is missing', () async {
    final service = FolderOpenerService(
      runner: (command, arguments, {bool runInShell = false}) async {
        return ProcessResult(3, 0, '', '');
      },
    );

    expect(
      () => service.openFolder('/definitely/missing/cadillac-folder'),
      throwsA(isA<FolderOpenException>()),
    );
  });
}

class _OpenCall {
  const _OpenCall(this.command, this.arguments, this.runInShell);

  final String command;
  final List<String> arguments;
  final bool runInShell;
}
