import 'package:cadillac_wallpaper_desktop/src/models/package_report_summary.dart';

class ThemePackageRequest {
  const ThemePackageRequest({
    required this.displayName,
    required this.author,
    required this.notes,
    required this.createdAt,
    required this.lightMasterPath,
    required this.darkMasterPath,
    required this.lightPreviewPath,
    required this.darkPreviewPath,
    required this.otaZipPath,
    required this.reportPath,
    required this.reportSummary,
    required this.libraryRootPath,
  });

  final String displayName;
  final String author;
  final String notes;
  final DateTime createdAt;
  final String lightMasterPath;
  final String darkMasterPath;
  final String lightPreviewPath;
  final String darkPreviewPath;
  final String otaZipPath;
  final String reportPath;
  final PackageReportSummary reportSummary;
  final String libraryRootPath;
}
