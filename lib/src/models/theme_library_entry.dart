import 'package:path/path.dart' as p;

class ThemeLibraryEntry {
  const ThemeLibraryEntry({
    required this.themeId,
    required this.displayName,
    required this.author,
    required this.notes,
    required this.createdAt,
    required this.cwthemePath,
    required this.otaZipPath,
    required this.reportPath,
    required this.lightThumbnailPath,
    required this.darkThumbnailPath,
    required this.allChecksPassed,
    required this.checkStatuses,
  });

  final String themeId;
  final String displayName;
  final String author;
  final String notes;
  final DateTime createdAt;
  final String cwthemePath;
  final String otaZipPath;
  final String reportPath;
  final String lightThumbnailPath;
  final String darkThumbnailPath;
  final bool allChecksPassed;
  final Map<String, bool> checkStatuses;

  Map<String, dynamic> toJson({String? basePath}) {
    return <String, dynamic>{
      'themeId': themeId,
      'displayName': displayName,
      'author': author,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'cwthemePath': _encodePath(cwthemePath, basePath),
      'otaZipPath': _encodePath(otaZipPath, basePath),
      'reportPath': _encodePath(reportPath, basePath),
      'lightThumbnailPath': _encodePath(lightThumbnailPath, basePath),
      'darkThumbnailPath': _encodePath(darkThumbnailPath, basePath),
      'allChecksPassed': allChecksPassed,
      'checkStatuses': checkStatuses,
    };
  }

  static ThemeLibraryEntry fromJson(
    Map<String, dynamic> json, {
    String? basePath,
  }) {
    return ThemeLibraryEntry(
      themeId: json['themeId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      cwthemePath: _decodePath(json['cwthemePath']?.toString() ?? '', basePath),
      otaZipPath: _decodePath(json['otaZipPath']?.toString() ?? '', basePath),
      reportPath: _decodePath(json['reportPath']?.toString() ?? '', basePath),
      lightThumbnailPath: _decodePath(
        json['lightThumbnailPath']?.toString() ?? '',
        basePath,
      ),
      darkThumbnailPath: _decodePath(
        json['darkThumbnailPath']?.toString() ?? '',
        basePath,
      ),
      allChecksPassed: json['allChecksPassed'] == true,
      checkStatuses: _boolMap(json['checkStatuses']),
    );
  }
}

String _encodePath(String path, String? basePath) {
  if (path.isEmpty || basePath == null || basePath.isEmpty) {
    return path;
  }

  final normalizedBase = p.normalize(p.absolute(basePath));
  final normalizedPath = p.normalize(p.absolute(path));
  if (p.equals(normalizedBase, normalizedPath) ||
      p.isWithin(normalizedBase, normalizedPath)) {
    return p.relative(normalizedPath, from: normalizedBase);
  }
  return path;
}

String _decodePath(String path, String? basePath) {
  if (path.isEmpty ||
      basePath == null ||
      basePath.isEmpty ||
      p.isAbsolute(path)) {
    return path;
  }
  return p.normalize(p.join(basePath, path));
}

Map<String, bool> _boolMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value.map(
      (key, dynamic value) => MapEntry(key, value == true),
    );
  }
  if (value is Map) {
    return value.map(
      (key, dynamic value) => MapEntry(key.toString(), value == true),
    );
  }
  return const <String, bool>{};
}
