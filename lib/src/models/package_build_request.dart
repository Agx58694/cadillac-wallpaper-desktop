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

  List<String> toCliArguments() {
    return <String>[
      '--light-image',
      lightImagePath,
      '--dark-image',
      darkImagePath,
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
