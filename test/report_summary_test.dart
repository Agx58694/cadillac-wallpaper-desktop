import 'package:cadillac_wallpaper_desktop/src/models/package_report_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackageReportSummary', () {
    test('extracts all required success checks from packager report', () {
      final summary = PackageReportSummary.fromJson(_safeReport());

      expect(summary.allPassed, isTrue);
      expect(summary.checkById('zip_integrity').passed, isTrue);
      expect(summary.checkById('png_dimensions_alpha').passed, isTrue);
      expect(summary.checkById('preview_alpha_template').passed, isTrue);
      expect(summary.checkById('kzb_size').passed, isTrue);
      expect(summary.checkById('kzb_record_offsets').passed, isTrue);
      expect(summary.checkById('kzb_rec0_preserved').passed, isTrue);
      expect(summary.checkById('aux_transparent_rgb').passed, isTrue);
      expect(summary.checkById('kzb_vcd_stitch_mae').passed, isTrue);
    });

    test('fails aux transparent RGB when any decoded record leaks RGB', () {
      final report = _safeReport();
      report['decoded_kzb']['aux_records']['2']
          ['rgb_where_alpha0_max'] = <int>[1, 0, 0];

      final summary = PackageReportSummary.fromJson(report);

      expect(summary.allPassed, isFalse);
      expect(summary.checkById('aux_transparent_rgb').passed, isFalse);
      expect(
        summary.checkById('aux_transparent_rgb').detail,
        contains('rec2'),
      );
    });

    test('fails stitch MAE when decoded KZB crop drifts too far from VCD', () {
      final report = _safeReport();
      report['decoded_kzb']['stitch']['6']['right_crop_vs_vcd_mae'] = 4.25;

      final summary = PackageReportSummary.fromJson(report);

      expect(summary.allPassed, isFalse);
      expect(summary.checkById('kzb_vcd_stitch_mae').passed, isFalse);
      expect(
        summary.checkById('kzb_vcd_stitch_mae').detail,
        contains('rec6'),
      );
    });
  });
}

Map<String, dynamic> _safeReport() {
  return <String, dynamic>{
    'output_zip': '/tmp/wallpaper.zip',
    'work_dir': '/tmp/work',
    'zip_test_bad_file': null,
    'zip_names_identical_order': true,
    'pngs': <String, dynamic>{
      'light_preview_image.png': <String, dynamic>{
        'size_matches': true,
        'alpha_extrema': <int>[0, 255],
        'preview_alpha_matches_template': true,
      },
      'dark_preview_image.png': <String, dynamic>{
        'size_matches': true,
        'alpha_extrema': <int>[0, 255],
        'preview_alpha_matches_template': true,
      },
      'vcd/wallpaper/light_wallpaper_vcd.png': <String, dynamic>{
        'size_matches': true,
        'fully_opaque': true,
      },
      'vcd/wallpaper/dark_wallpaper_vcd.png': <String, dynamic>{
        'size_matches': true,
        'fully_opaque': true,
      },
    },
    'kzb': <String, dynamic>{
      'source_kzb_size': 128,
      'patched_kzb_size': 128,
      'record0_preserved': true,
      'record_offsets_same': <bool>[true, true, true, true, true, true, true],
    },
    'decoded_kzb': <String, dynamic>{
      'aux_records': <String, dynamic>{
        '1': <String, dynamic>{
          'rgb_where_alpha0_max': <int>[0, 0, 0]
        },
        '2': <String, dynamic>{'rgb_where_alpha0_max': null},
        '4': <String, dynamic>{
          'rgb_where_alpha0_max': <int>[0, 0, 0]
        },
        '5': <String, dynamic>{
          'rgb_where_alpha0_max': <int>[0, 0, 0]
        },
      },
      'stitch': <String, dynamic>{
        '3': <String, dynamic>{'right_crop_vs_vcd_mae': 2.5},
        '6': <String, dynamic>{'right_crop_vs_vcd_mae': 3.75},
      },
    },
  };
}
