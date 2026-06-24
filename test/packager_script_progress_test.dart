import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packager script emits user-visible progress stages', () async {
    final script = await File(
      'packager/cadillac_wallpaper_packager.py',
    ).readAsString();

    expect(script, contains('progress("step 1/9 validate inputs")'));
    expect(script, contains('progress("step 3/9 derive external PNGs")'));
    expect(script, contains('progress("step 5/9 encode KZB ASTC records")'));
    expect(
      script,
      contains('progress("step 8/9 decode verify KZB/VCD stitch")'),
    );
    expect(script, contains('[cadillac-packager] {redact_text(message)}'));
    expect(script, contains('flush=True'));
  });

  test('packager script redacts local paths in stdout and report fields',
      () async {
    final script = await File(
      'packager/cadillac_wallpaper_packager.py',
    ).readAsString();
    final moduleHeader = script.split('def load_runtime_dependencies').first;

    expect(script, contains('def redact_text'));
    expect(script, contains('def redacted_path'));
    expect(script, contains('def load_runtime_dependencies'));
    expect(script, contains('load_runtime_dependencies()'));
    expect(moduleHeader, isNot(contains('from PIL import')));
    expect(moduleHeader, isNot(contains('import kzb_astc_patcher')));
    expect(script, contains('"input_zip": redacted_path(input_zip)'));
    expect(script, contains('"output_zip": redacted_path(output_zip)'));
    expect(script, contains('"light_image": redacted_path(light_image)'));
    expect(script, contains('"dark_image": redacted_path(dark_image)'));
    expect(script, contains('except Exception as error'));
    expect(script, isNot(contains(RegExp(r'/Users/[^/\s]+'))));
    expect(script, isNot(contains('str(input_zip.resolve())')));
    expect(script, isNot(contains('str(args.output_zip.resolve())')));
  });
}
