class ReportCheck {
  const ReportCheck({
    required this.id,
    required this.label,
    required this.passed,
    required this.detail,
  });

  final String id;
  final String label;
  final bool passed;
  final String detail;
}

class PackageReportSummary {
  const PackageReportSummary({required this.checks});

  static const double defaultMaxStitchMae = 4.0;

  final List<ReportCheck> checks;

  bool get allPassed => checks.every((check) => check.passed);

  ReportCheck checkById(String id) {
    return checks.firstWhere((check) => check.id == id);
  }

  Map<String, bool> toStatusMap() {
    return <String, bool>{
      for (final check in checks) check.id: check.passed,
    };
  }

  static PackageReportSummary fromJson(
    Map<String, dynamic> report, {
    double maxStitchMae = defaultMaxStitchMae,
  }) {
    return PackageReportSummary(
      checks: <ReportCheck>[
        _zipIntegrity(report),
        _pngDimensionsAndAlpha(report),
        _previewAlphaTemplate(report),
        _kzbStructure(report),
        _kzbRec0Preserved(report),
        _auxTransparentRgb(report),
        _kzbVcdStitchMae(report, maxStitchMae),
      ],
    );
  }

  Map<String, bool> toManifestChecks() {
    return <String, bool>{
      'zip': checkById('zip_integrity').passed,
      'pngAlpha': checkById('png_dimensions_alpha').passed &&
          checkById('preview_alpha_template').passed,
      // Retain the v1 manifest key for existing .cwtheme consumers. A rebuilt
      // KZB may legitimately have different offsets when its identity grows.
      'kzbOffsets': checkById('kzb_structure').passed &&
          checkById('kzb_rec0_preserved').passed,
      'kzbStructure': checkById('kzb_structure').passed,
      'auxTransparentRgbZero': checkById('aux_transparent_rgb').passed,
      'kzbVcdStitch': checkById('kzb_vcd_stitch_mae').passed,
    };
  }
}

ReportCheck _zipIntegrity(Map<String, dynamic> report) {
  final badFile = report['zip_test_bad_file'];
  final structureValid = report.containsKey('zip_structure_valid')
      ? report['zip_structure_valid'] == true
      : report['zip_names_identical_order'] == true;
  final passed = badFile == null && structureValid;
  return ReportCheck(
    id: 'zip_integrity',
    label: 'ZIP 完整性',
    passed: passed,
    detail: passed
        ? report.containsKey('zip_structure_valid')
            ? 'zip test 与壁纸结构校验通过'
            : 'zip test 通过，旧版条目顺序未改变'
        : 'bad_file=${badFile ?? 'none'}, structure_valid=$structureValid',
  );
}

ReportCheck _pngDimensionsAndAlpha(Map<String, dynamic> report) {
  final pngs = _map(report['pngs']);
  if (pngs.isEmpty) {
    return const ReportCheck(
      id: 'png_dimensions_alpha',
      label: 'PNG 尺寸和 alpha',
      passed: false,
      detail: 'report 缺少 pngs 校验',
    );
  }

  final failures = <String>[];
  for (final entry in pngs.entries) {
    final value = _map(entry.value);
    final sizeMatches = value['size_matches'] == true;
    final isPreview = entry.key.endsWith('preview_image.png');
    final alphaOk = isPreview
        ? value.containsKey('alpha_extrema')
        : value['fully_opaque'] == true;
    if (!sizeMatches || !alphaOk) {
      failures.add(entry.key);
    }
  }

  return ReportCheck(
    id: 'png_dimensions_alpha',
    label: 'PNG 尺寸和 alpha',
    passed: failures.isEmpty,
    detail: failures.isEmpty
        ? '${pngs.length} 个 PNG 尺寸/alpha 校验通过'
        : '失败: ${failures.join(', ')}',
  );
}

ReportCheck _previewAlphaTemplate(Map<String, dynamic> report) {
  final pngs = _map(report['pngs']);
  final previews = pngs.entries
      .where((entry) => entry.key.endsWith('preview_image.png'))
      .toList(growable: false);
  if (previews.isEmpty) {
    return const ReportCheck(
      id: 'preview_alpha_template',
      label: 'preview alpha 复用模板',
      passed: false,
      detail: 'report 缺少 preview PNG 校验',
    );
  }

  final failures = previews
      .where(
        (entry) => _map(entry.value)['preview_alpha_matches_template'] != true,
      )
      .map((entry) => entry.key)
      .toList(growable: false);

  return ReportCheck(
    id: 'preview_alpha_template',
    label: 'preview alpha 复用模板',
    passed: failures.isEmpty,
    detail: failures.isEmpty
        ? 'light/dark preview alpha 均匹配模板'
        : failures.join(', '),
  );
}

ReportCheck _kzbStructure(Map<String, dynamic> report) {
  final kzb = _map(report['kzb']);
  if (kzb.containsKey('identity_rebuild_consistent')) {
    final passed = kzb['identity_rebuild_consistent'] == true;
    return ReportCheck(
      id: 'kzb_structure',
      label: 'KZB 身份与引用一致性',
      passed: passed,
      detail: passed ? '变长身份重建与内部引用校验通过' : '身份重建校验失败或缺少结果',
    );
  }

  // Older reports described an in-place payload patch. Its size and record
  // offsets had to stay fixed; preserve that interpretation for saved themes.
  final sourceSize = kzb['source_kzb_size'];
  final patchedSize = kzb['patched_kzb_size'];
  final offsets = _boolList(kzb['record_offsets_same']);
  final passed = sourceSize != null &&
      sourceSize == patchedSize &&
      offsets.isNotEmpty &&
      offsets.every((value) => value);
  return ReportCheck(
    id: 'kzb_structure',
    label: '旧版 KZB 定长结构',
    passed: passed,
    detail: 'source=$sourceSize, patched=$patchedSize, offsets=$offsets',
  );
}

ReportCheck _kzbRec0Preserved(Map<String, dynamic> report) {
  final preserved = _map(report['kzb'])['record0_preserved'] == true;
  return ReportCheck(
    id: 'kzb_rec0_preserved',
    label: 'rec0 保持',
    passed: preserved,
    detail: preserved ? 'rec0 md5 未改变' : 'rec0 已变化或 report 缺失',
  );
}

ReportCheck _auxTransparentRgb(Map<String, dynamic> report) {
  final aux = _map(_map(report['decoded_kzb'])['aux_records']);
  if (aux.isEmpty) {
    return const ReportCheck(
      id: 'aux_transparent_rgb',
      label: 'rec1/2/4/5 alpha=0 RGB',
      passed: false,
      detail: 'report 缺少 decoded_kzb.aux_records',
    );
  }

  final failures = <String>[];
  for (final index in const <String>['1', '2', '4', '5']) {
    final value = _map(aux[index])['rgb_where_alpha0_max'];
    if (!_isTransparentRgbZero(value)) {
      failures.add('rec$index=$value');
    }
  }

  return ReportCheck(
    id: 'aux_transparent_rgb',
    label: 'rec1/2/4/5 alpha=0 RGB',
    passed: failures.isEmpty,
    detail: failures.isEmpty
        ? '透明像素 RGB 均为 [0,0,0] 或无 alpha=0 像素'
        : failures.join(', '),
  );
}

ReportCheck _kzbVcdStitchMae(
  Map<String, dynamic> report,
  double maxStitchMae,
) {
  final stitch = _map(_map(report['decoded_kzb'])['stitch']);
  if (stitch.isEmpty) {
    return const ReportCheck(
      id: 'kzb_vcd_stitch_mae',
      label: 'KZB/VCD 拼接 MAE',
      passed: false,
      detail: 'report 缺少 decoded_kzb.stitch',
    );
  }

  final failures = <String>[];
  final details = <String>[];
  for (final entry in stitch.entries) {
    final mae = _number(_map(entry.value)['right_crop_vs_vcd_mae']);
    details.add('rec${entry.key}=${mae?.toStringAsFixed(3) ?? 'missing'}');
    if (mae == null || mae > maxStitchMae) {
      failures.add('rec${entry.key}');
    }
  }

  return ReportCheck(
    id: 'kzb_vcd_stitch_mae',
    label: 'KZB/VCD 拼接 MAE',
    passed: failures.isEmpty,
    detail: '${details.join(', ')}; 阈值 <= $maxStitchMae',
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<bool> _boolList(Object? value) {
  if (value is List) {
    return value.whereType<bool>().toList(growable: false);
  }
  return const <bool>[];
}

double? _number(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool _isTransparentRgbZero(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is List && value.length == 3) {
    return value.every((channel) => channel == 0);
  }
  return false;
}
