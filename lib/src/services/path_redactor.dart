import 'dart:io';

String redactSensitivePaths(Object? value) {
  var text = value?.toString() ?? '';

  final tempPath = Directory.systemTemp.path;
  if (tempPath.isNotEmpty) {
    text = text.replaceAll(tempPath, '<TEMP>');
  }
  text = text.replaceAll(RegExp(r'/var/folders/[^\s"<>]+'), '<TEMP>');

  final homePath =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homePath != null && homePath.isNotEmpty) {
    text = text.replaceAll(homePath, '<HOME>');
  }

  text = text.replaceAllMapped(
    RegExp(r'/(Users|home)/[^/\s"<>]+'),
    (_) => '<HOME>',
  );
  text = text.replaceAllMapped(
    RegExp(r'[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s"<>]+'),
    (_) => '<HOME>',
  );

  return text;
}
