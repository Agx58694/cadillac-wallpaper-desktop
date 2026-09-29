import 'dart:convert';

import 'package:crypto/crypto.dart';

enum WallpaperSourceMode {
  native,
  legacy;

  static WallpaperSourceMode? fromSize(int width, int height) {
    if (width == 8960 && height == 1320) return native;
    if (width == 2198 && height == 367) return legacy;
    return null;
  }
}

String safeThemeKey(String value) {
  final normalized = value.trim().toLowerCase();
  final cleaned = normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final prefixed = cleaned.isEmpty
      ? 'wallpaper'
      : RegExp(r'^[a-z]').hasMatch(cleaned)
          ? cleaned
          : 'wallpaper_$cleaned';
  final shortened = prefixed.length > 15 ? prefixed.substring(0, 15) : prefixed;
  final readable = shortened.replaceFirst(RegExp(r'_+$'), '');
  final digest =
      sha256.convert(utf8.encode(normalized)).toString().substring(0, 16);
  return '${readable}_$digest';
}

class PackageBuildRequest {
  const PackageBuildRequest({
    required this.lightImagePath,
    required this.darkImagePath,
    required this.outputZipPath,
    required this.workDirPath,
    required this.reportPath,
    this.inputZipPath,
    this.astcencPath,
    this.lightDimMaskPath,
    this.darkDimMaskPath,
    this.quality = '-medium',
    this.previewBlur = 0.45,
    this.sharpen = true,
    this.decodeVerify = true,
    this.maxStitchMae = 4.0,
    this.sourceMode = WallpaperSourceMode.legacy,
    this.themeKey = 'wallpaper',
  });

  final String lightImagePath;
  final String darkImagePath;
  final String outputZipPath;
  final String workDirPath;
  final String reportPath;
  final String? inputZipPath;
  final String? astcencPath;
  final String? lightDimMaskPath;
  final String? darkDimMaskPath;
  final String quality;
  final double previewBlur;
  final bool sharpen;
  final bool decodeVerify;
  final double maxStitchMae;
  final WallpaperSourceMode sourceMode;
  final String themeKey;

  List<String> toCliArguments() {
    return <String>[
      '--light-image',
      lightImagePath,
      '--dark-image',
      darkImagePath,
      '--source-mode',
      sourceMode.name,
      '--theme-key',
      themeKey,
      '--output-zip',
      outputZipPath,
      '--work-dir',
      workDirPath,
      '--report',
      reportPath,
      if (inputZipPath != null) ...<String>['--input-zip', inputZipPath!],
      if (astcencPath != null) ...<String>['--astcenc', astcencPath!],
      if (lightDimMaskPath != null) ...<String>[
        '--light-dim-mask',
        lightDimMaskPath!,
      ],
      if (darkDimMaskPath != null) ...<String>[
        '--dark-dim-mask',
        darkDimMaskPath!,
      ],
      '--quality=$quality',
      '--preview-blur',
      previewBlur.toString(),
      '--max-stitch-mae',
      maxStitchMae.toString(),
      if (!sharpen) '--no-sharpen',
      if (!decodeVerify) '--skip-decode-verify',
    ];
  }
}
