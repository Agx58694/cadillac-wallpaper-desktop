import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cadillac_wallpaper_desktop/src/app.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _writeErrorLog(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _writeErrorLog(error, stack);
    return true;
  };
  runZonedGuarded(
    () => runApp(const CadillacWallpaperDesktopApp()),
    _writeErrorLog,
  );
}

void _writeErrorLog(Object error, StackTrace? stack) {
  try {
    final logFile = File(
      '${Directory.systemTemp.path}/cadillac-packager-error.log',
    );
    logFile.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $error\n$stack\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } on Object {
    // Last-resort error handling must not throw another exception.
  }
}
