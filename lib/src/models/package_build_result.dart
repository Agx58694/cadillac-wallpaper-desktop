import 'package:cadillac_wallpaper_desktop/src/models/package_report_summary.dart';

class PackageBuildResult {
  const PackageBuildResult({
    required this.outputZipPath,
    required this.reportPath,
    required this.workDirPath,
    required this.reportJson,
    required this.reportSummary,
    required this.stdout,
    required this.stderr,
  });

  final String outputZipPath;
  final String reportPath;
  final String workDirPath;
  final Map<String, dynamic> reportJson;
  final PackageReportSummary reportSummary;
  final String stdout;
  final String stderr;
}
