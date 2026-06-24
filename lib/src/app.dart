// coverage:ignore-file
import 'dart:async';
import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/models/package_build_request.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_build_result.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_report_summary.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_library_entry.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_package_request.dart';
import 'package:cadillac_wallpaper_desktop/src/services/folder_opener_service.dart';
import 'package:cadillac_wallpaper_desktop/src/services/image_probe_service.dart';
import 'package:cadillac_wallpaper_desktop/src/services/path_redactor.dart';
import 'package:cadillac_wallpaper_desktop/src/services/theme_library_store.dart';
import 'package:cadillac_wallpaper_desktop/src/services/theme_package_service.dart';
import 'package:cadillac_wallpaper_desktop/src/services/wallpaper_packager_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PackageMode {
  standardOta,
  androidTheme,
}

class CadillacWallpaperDesktopApp extends StatelessWidget {
  const CadillacWallpaperDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xff0a7c76);
    return MaterialApp(
      title: 'Cadillac Wallpaper Packager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: _AppColors.surface,
          background: _AppColors.chrome,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: _AppColors.chrome,
        fontFamily: '.AppleSystemUIFont',
        visualDensity: VisualDensity.standard,
        dividerTheme: const DividerThemeData(
          color: _AppColors.separator,
          thickness: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _AppColors.field,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.separator),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.separator),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.accent, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            side: const MaterialStatePropertyAll(
              BorderSide(color: _AppColors.separator),
            ),
          ),
        ),
      ),
      home: const PackagingHomePage(),
    );
  }
}

class PackagingHomePage extends StatefulWidget {
  const PackagingHomePage({super.key});

  @override
  State<PackagingHomePage> createState() => _PackagingHomePageState();
}

class _PackagingHomePageState extends State<PackagingHomePage> {
  final _themeNameController = TextEditingController(text: 'Cadillac Theme');
  final _authorController = TextEditingController();
  final _notesController = TextEditingController();
  final _outputZipController = TextEditingController();
  final _packagerService = WallpaperPackagerService();
  final _themePackageService = ThemePackageService();
  final _imageProbeService = ImageProbeService();
  final _folderOpenerService = FolderOpenerService();
  final _logs = <String>[];

  PackageMode _mode = PackageMode.standardOta;
  ThemeLibraryStore? _libraryStore;
  String? _libraryRootPath;
  String? _lightImagePath;
  String? _darkImagePath;
  ImageProbe? _lightProbe;
  ImageProbe? _darkProbe;
  PackageBuildResult? _lastResult;
  String? _lastPackagePath;
  String? _lastOutputFolderPath;
  List<ThemeLibraryEntry> _themes = const <ThemeLibraryEntry>[];
  bool _running = false;

  static const _pngType = XTypeGroup(
    label: 'PNG',
    extensions: <String>['png'],
    uniformTypeIdentifiers: <String>['public.png'],
  );
  static const _zipType = XTypeGroup(
    label: 'ZIP',
    extensions: <String>['zip'],
    uniformTypeIdentifiers: <String>['public.zip-archive'],
  );

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _themeNameController.dispose();
    _authorController.dispose();
    _notesController.dispose();
    _outputZipController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final supportDir = await getApplicationSupportDirectory();
    final rootPath = p.join(supportDir.path, 'CadillacWallpaperThemes');
    final store = ThemeLibraryStore(rootDirectory: rootPath);
    final themes = await store.loadEntries();
    if (themes.isNotEmpty) {
      await store.saveEntries(themes);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _libraryRootPath = rootPath;
      _libraryStore = store;
      _themes = themes;
    });
  }

  Future<void> _selectImage({required bool isLight}) async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_pngType],
      confirmButtonText: '选择',
    );
    if (file == null) {
      return;
    }

    await _setImagePath(isLight: isLight, path: file.path);
  }

  Future<void> _dropImage({
    required bool isLight,
    required List<String> paths,
  }) async {
    final droppedPaths = paths.where((path) => path.trim().isNotEmpty).toList();
    final pngPath = droppedPaths.cast<String?>().firstWhere(
          (path) => p.extension(path!).toLowerCase() == '.png',
          orElse: () => null,
        );
    final label = isLight ? '白天' : '黑夜';
    if (pngPath == null) {
      _appendLog('拖入失败: $label 只支持 PNG 文件');
      return;
    }
    if (droppedPaths.length > 1) {
      _appendLog('拖入多个文件，$label 已使用第一张 PNG');
    }
    await _setImagePath(isLight: isLight, path: pngPath);
  }

  Future<void> _setImagePath({
    required bool isLight,
    required String path,
  }) async {
    if (p.extension(path).toLowerCase() != '.png') {
      _appendLog('图片添加失败: 只支持 PNG 文件 (${p.basename(path)})');
      return;
    }

    try {
      final probe = await _imageProbeService.inspect(path);
      setState(() {
        if (isLight) {
          _lightImagePath = path;
          _lightProbe = probe;
        } else {
          _darkImagePath = path;
          _darkProbe = probe;
        }
      });
      final label = isLight ? '白天' : '黑夜';
      final sizeLabel = '${probe.width}x${probe.height}';
      _appendLog(
        '已添加$label图片: ${p.basename(path)} '
        '($sizeLabel, alpha ${probe.alphaMin}-${probe.alphaMax})',
      );
      if (!probe.isRequiredPreviewSize) {
        _appendLog('$label图片尺寸不是 2198x367，开始打包前需要更换');
      }
    } on Object catch (error) {
      _appendLog('图片读取失败: $error');
    }
  }

  Future<void> _selectOutputZip() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_zipType],
      suggestedName: 'cadillac_ota_wallpaper.zip',
      confirmButtonText: '保存',
    );
    if (location == null) {
      return;
    }
    final path = location.path.toLowerCase().endsWith('.zip')
        ? location.path
        : '${location.path}.zip';
    setState(() {
      _outputZipController.text = path;
    });
  }

  Future<void> _runPackaging() async {
    final validationError = _validateInputs();
    if (validationError != null) {
      _appendLog(validationError);
      return;
    }

    setState(() {
      _running = true;
      _lastResult = null;
      _lastPackagePath = null;
      _lastOutputFolderPath = null;
      _logs.clear();
    });

    Timer? progressTimer;
    final stopwatch = Stopwatch()..start();
    try {
      final now = DateTime.now();
      _appendLog(
        '步骤 1/6 校验输入: 白天 ${p.basename(_lightImagePath!)}，'
        '黑夜 ${p.basename(_darkImagePath!)}',
      );
      final paths = _resolveBuildPaths(now);
      _appendLog('步骤 2/6 准备输出目录: ${p.dirname(paths.outputZipPath)}');
      final buildResources = await _resolveBuildResources();
      final envInputZipPath = _envPath('CADILLAC_INPUT_ZIP');
      final inputZipPath = envInputZipPath ?? buildResources.inputZipPath;
      final astcencPath =
          _envPath('CADILLAC_ASTCENC') ?? buildResources.astcencPath;
      final lightDimMaskPath = _envPath('CADILLAC_LIGHT_DIM_MASK') ??
          buildResources.lightDimMaskPath;
      final darkDimMaskPath =
          _envPath('CADILLAC_DARK_DIM_MASK') ?? buildResources.darkDimMaskPath;
      _appendLog('步骤 3/6 解析内置模板和 ASTC 工具');
      _appendLog(
        envInputZipPath == null
            ? '未设置 CADILLAC_INPUT_ZIP，使用内置足球模板'
            : '使用 CADILLAC_INPUT_ZIP 指定的模板',
      );
      _appendResourceLog('模板 zip', inputZipPath);
      _appendResourceLog('astcenc', astcencPath);
      _appendResourceLog('白天 alpha mask', lightDimMaskPath);
      _appendResourceLog('黑夜 alpha mask', darkDimMaskPath);
      final resourceError = _validateInputZipResource(inputZipPath);
      if (resourceError != null) {
        throw PackagerException(resourceError);
      }
      _appendLog('Python: ${_packagerService.pythonExecutable}');
      _appendLog(
        '步骤 4/6 调用打包 CLI: ${WallpaperPackagerService.defaultPackagerScript()}',
      );
      progressTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _appendLog(
          'CLI 仍在运行 ${stopwatch.elapsed.inSeconds}s，'
          '正在生成预览、编码 ASTC 或校验拼接',
        );
      });
      final result = await _packagerService.buildPackage(
        PackageBuildRequest(
          lightImagePath: _lightImagePath!,
          darkImagePath: _darkImagePath!,
          outputZipPath: paths.outputZipPath,
          workDirPath: paths.workDirPath,
          reportPath: paths.reportPath,
          inputZipPath: inputZipPath,
          astcencPath: astcencPath,
          lightDimMaskPath: lightDimMaskPath,
          darkDimMaskPath: darkDimMaskPath,
        ),
        onCliOutput: _appendCliOutput,
      );
      progressTimer.cancel();
      progressTimer = null;
      _appendLog('步骤 5/6 读取 report.json 并生成校验报告');
      _appendLog('OTA zip: ${result.outputZipPath}');
      _appendLog('report.json: ${result.reportPath}');

      ThemeLibraryEntry? savedTheme;
      if (_mode == PackageMode.androidTheme) {
        _appendLog('步骤 6/6 写入 .cwtheme 并保存到本地主题库');
        savedTheme = await _saveThemePackage(result, now);
      } else {
        _appendLog('步骤 6/6 完成标准 OTA 打包');
      }

      if (!mounted) {
        return;
      }
      final packagePath = savedTheme?.cwthemePath ?? result.outputZipPath;
      final outputFolderPath = p.dirname(packagePath);
      setState(() {
        _lastResult = result;
        _lastPackagePath = packagePath;
        _lastOutputFolderPath = outputFolderPath;
      });
      _appendLog('输出文件夹: $outputFolderPath');
      _appendLog('总耗时: ${stopwatch.elapsed.inSeconds}s');
    } on Object catch (error) {
      _appendLog('打包失败: $error');
    } finally {
      progressTimer?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<ThemeLibraryEntry> _saveThemePackage(
    PackageBuildResult result,
    DateTime createdAt,
  ) async {
    final libraryRootPath = _libraryRootPath;
    final libraryStore = _libraryStore;
    if (libraryRootPath == null || libraryStore == null) {
      throw StateError('主题库尚未初始化');
    }

    final entry = await _themePackageService.createThemePackage(
      ThemePackageRequest(
        displayName: _themeNameController.text.trim(),
        author: _authorController.text.trim(),
        notes: _notesController.text.trim(),
        createdAt: createdAt,
        lightMasterPath: _lightImagePath!,
        darkMasterPath: _darkImagePath!,
        lightPreviewPath: p.join(
          result.workDirPath,
          'derived_png',
          'light_preview_image.png',
        ),
        darkPreviewPath: p.join(
          result.workDirPath,
          'derived_png',
          'dark_preview_image.png',
        ),
        otaZipPath: result.outputZipPath,
        reportPath: result.reportPath,
        reportSummary: result.reportSummary,
        libraryRootPath: libraryRootPath,
      ),
    );
    await libraryStore.upsertEntry(entry);
    final themes = await libraryStore.loadEntries();
    if (!mounted) {
      return entry;
    }
    setState(() {
      _themes = themes;
    });
    _appendLog('.cwtheme: ${entry.cwthemePath}');
    return entry;
  }

  _BuildPaths _resolveBuildPaths(DateTime now) {
    final stamp = _timestamp(now);
    if (_mode == PackageMode.standardOta) {
      final outputZipPath = _outputZipController.text.trim();
      final base = p.withoutExtension(outputZipPath);
      return _BuildPaths(
        outputZipPath: outputZipPath,
        workDirPath: '${base}_work',
        reportPath: '$base-report.json',
      );
    }

    final root = p.join(_libraryRootPath!, 'builds', stamp);
    return _BuildPaths(
      outputZipPath: p.join(root, 'ota_wallpaper.zip'),
      workDirPath: p.join(root, 'work'),
      reportPath: p.join(root, 'package-report.json'),
    );
  }

  Future<_BuildResources> _resolveBuildResources() async {
    String? astcencSource;
    if (Platform.isMacOS) {
      astcencSource = WallpaperPackagerService.bundledAssetPath(
        'packager/tools/macos/astcenc',
      );
    } else if (Platform.isWindows) {
      astcencSource = WallpaperPackagerService.bundledAssetPath(
        'packager/tools/windows/astcenc.exe',
      );
    }
    return _BuildResources(
      inputZipPath: WallpaperPackagerService.bundledAssetPath(
        'packager/templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip',
      ),
      astcencPath: astcencSource == null
          ? null
          : await _stageExecutableAsset(
              sourcePath: astcencSource,
              name: Platform.isWindows ? 'astcenc.exe' : 'astcenc',
            ),
      lightDimMaskPath: WallpaperPackagerService.bundledAssetPath(
        'packager/masks/light_dim_alpha_fixed_smoothed_used.png',
      ),
      darkDimMaskPath: WallpaperPackagerService.bundledAssetPath(
        'packager/masks/dark_dim_alpha_fixed_smoothed_used.png',
      ),
    );
  }

  Future<String> _stageExecutableAsset({
    required String sourcePath,
    required String name,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final runtimeDir = Directory(p.join(supportDir.path, 'PackagerRuntime'));
    await runtimeDir.create(recursive: true);
    final destination = File(p.join(runtimeDir.path, name));
    final source = File(sourcePath);
    if (!destination.existsSync() ||
        destination.lengthSync() != source.lengthSync()) {
      await source.copy(destination.path);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['755', destination.path]);
    }
    return destination.path;
  }

  String? _validateInputs() {
    if (_lightImagePath == null || _darkImagePath == null) {
      return '需要选择白天和黑夜两张 PNG';
    }
    if (_lightProbe?.isRequiredPreviewSize != true ||
        _darkProbe?.isRequiredPreviewSize != true) {
      return '两张输入图必须都是 2198x367';
    }
    if (_mode == PackageMode.standardOta &&
        _outputZipController.text.trim().isEmpty) {
      return '标准 OTA 模式需要输出 zip 路径';
    }
    if (_mode == PackageMode.androidTheme &&
        _themeNameController.text.trim().isEmpty) {
      return 'Android 联动主题包需要主题名称';
    }
    if (_mode == PackageMode.androidTheme && _libraryRootPath == null) {
      return '主题库路径尚未初始化';
    }
    return null;
  }

  Future<void> _deleteTheme(ThemeLibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除主题'),
        content: Text(entry.displayName),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(CupertinoIcons.delete),
            label: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _libraryStore?.deleteTheme(entry.themeId);
    await _loadLibrary();
  }

  Future<void> _openOutputFolder() async {
    final outputFolderPath = _lastOutputFolderPath;
    if (outputFolderPath == null) {
      return;
    }
    await _openFolder(outputFolderPath);
  }

  Future<void> _openThemeFolder(ThemeLibraryEntry entry) async {
    await _openFolder(p.dirname(entry.cwthemePath));
  }

  Future<void> _openFolder(String folderPath) async {
    try {
      final openedPath = await _folderOpenerService.openFolder(folderPath);
      _appendLog('已打开文件夹: $openedPath');
    } on Object catch (error) {
      _appendLog('打开文件夹失败: $error');
    }
  }

  void _appendLog(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.add(redactSensitivePaths(message));
    });
  }

  void _appendResourceLog(String label, String? path) {
    _appendLog('$label: ${path ?? '使用 CLI 默认'}');
  }

  String? _validateInputZipResource(String? path) {
    if (path == null || path.trim().isEmpty) {
      return '模板 zip 未配置。请重新下载包含内置足球模板的版本，或设置 CADILLAC_INPUT_ZIP 指向兼容模板 zip。';
    }
    if (!File(path).existsSync()) {
      return '模板 zip 不存在，请检查内置足球模板或 CADILLAC_INPUT_ZIP: $path';
    }
    return null;
  }

  void _appendCliOutput(String line) {
    if (line.startsWith('[cadillac-packager]')) {
      _appendLog(line);
      return;
    }
    _appendLog('CLI: $line');
  }

  @override
  Widget build(BuildContext context) {
    final summary = _lastResult?.reportSummary;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _AppHeader(mode: _mode, running: _running, summary: summary),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 980;
                  final sidebar = _Sidebar(
                    mode: _mode,
                    lightImagePath: _lightImagePath,
                    darkImagePath: _darkImagePath,
                    lightProbe: _lightProbe,
                    darkProbe: _darkProbe,
                    outputZipController: _outputZipController,
                    themeNameController: _themeNameController,
                    authorController: _authorController,
                    notesController: _notesController,
                    libraryRootPath: _libraryRootPath,
                    running: _running,
                    onModeChanged: (mode) => setState(() => _mode = mode),
                    onPickLight: () => _selectImage(isLight: true),
                    onPickDark: () => _selectImage(isLight: false),
                    onDropLight: (paths) =>
                        _dropImage(isLight: true, paths: paths),
                    onDropDark: (paths) =>
                        _dropImage(isLight: false, paths: paths),
                    onPickOutput: _selectOutputZip,
                    onRun: _running ? null : _runPackaging,
                  );
                  final workbench = _Workbench(
                    mode: _mode,
                    lightImagePath: _lightImagePath,
                    darkImagePath: _darkImagePath,
                    result: _lastResult,
                    packagePath: _lastPackagePath,
                    outputFolderPath: _lastOutputFolderPath,
                    summary: summary,
                    logs: _logs,
                    themes: _themes,
                    onDeleteTheme: _deleteTheme,
                    onOpenOutputFolder: _openOutputFolder,
                    onOpenThemeFolder: _openThemeFolder,
                    onRefreshLibrary: _loadLibrary,
                  );

                  if (compact) {
                    return CustomScrollView(
                      slivers: <Widget>[
                        SliverToBoxAdapter(child: sidebar),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                          sliver: SliverToBoxAdapter(child: workbench),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(width: 338, child: sidebar),
                      const VerticalDivider(width: 1),
                      Expanded(child: workbench),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.mode,
    required this.running,
    required this.summary,
  });

  final PackageMode mode;
  final bool running;
  final PackageReportSummary? summary;

  @override
  Widget build(BuildContext context) {
    final status = summary?.allPassed;
    final statusText = running
        ? '打包中'
        : status == null
            ? '待打包'
            : status
                ? '校验通过'
                : '校验异常';
    final statusColor = running
        ? _AppColors.accent
        : status == null
            ? _AppColors.tertiaryText
            : status
                ? _AppColors.success
                : _AppColors.danger;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(color: _AppColors.surface),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/app_icon_source.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 26, color: _AppColors.chromeLine),
          const SizedBox(width: 12),
          Text(
            'Cadillac Packager',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(width: 10),
          Text(
            mode == PackageMode.standardOta ? '标准 OTA' : '主题包',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AppColors.secondaryText,
                ),
          ),
          const Spacer(),
          _StatusPill(text: statusText, color: statusColor),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.mode,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.lightProbe,
    required this.darkProbe,
    required this.outputZipController,
    required this.themeNameController,
    required this.authorController,
    required this.notesController,
    required this.libraryRootPath,
    required this.running,
    required this.onModeChanged,
    required this.onPickLight,
    required this.onPickDark,
    required this.onDropLight,
    required this.onDropDark,
    required this.onPickOutput,
    required this.onRun,
  });

  final PackageMode mode;
  final String? lightImagePath;
  final String? darkImagePath;
  final ImageProbe? lightProbe;
  final ImageProbe? darkProbe;
  final TextEditingController outputZipController;
  final TextEditingController themeNameController;
  final TextEditingController authorController;
  final TextEditingController notesController;
  final String? libraryRootPath;
  final bool running;
  final ValueChanged<PackageMode> onModeChanged;
  final VoidCallback onPickLight;
  final VoidCallback onPickDark;
  final Future<void> Function(List<String> paths) onDropLight;
  final Future<void> Function(List<String> paths) onDropDark;
  final VoidCallback onPickOutput;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _AppColors.sidebar,
        border: Border(right: BorderSide(color: _AppColors.separator)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SidebarTitle(),
            const SizedBox(height: 14),
            _ModePicker(mode: mode, onChanged: onModeChanged),
            const SizedBox(height: 20),
            const _SectionLabel(
              icon: CupertinoIcons.photo,
              title: '输入图片',
              trailing: '2198x367',
            ),
            const SizedBox(height: 10),
            _ImageInputTile(
              title: '白天',
              path: lightImagePath,
              probe: lightProbe,
              onPick: onPickLight,
              onDrop: onDropLight,
            ),
            const SizedBox(height: 10),
            _ImageInputTile(
              title: '黑夜',
              path: darkImagePath,
              probe: darkProbe,
              onPick: onPickDark,
              onDrop: onDropDark,
            ),
            const SizedBox(height: 22),
            if (mode == PackageMode.standardOta)
              _StandardOutputFields(
                outputZipPath: outputZipController.text,
                onPickOutput: onPickOutput,
              )
            else
              _ThemeFields(
                themeNameController: themeNameController,
                authorController: authorController,
                notesController: notesController,
                libraryRootPath: libraryRootPath,
              ),
            const SizedBox(height: 22),
            _RunButton(running: running, onRun: onRun),
          ],
        ),
      ),
    );
  }
}

class _SidebarTitle extends StatelessWidget {
  const _SidebarTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            CupertinoIcons.slider_horizontal_3,
            color: _AppColors.accent,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Inputs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
              ),
              Text(
                'OTA / Theme Pack',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AppColors.secondaryText,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});

  final PackageMode mode;
  final ValueChanged<PackageMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PackageMode>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<PackageMode>>[
        ButtonSegment<PackageMode>(
          value: PackageMode.standardOta,
          icon: Icon(CupertinoIcons.archivebox, size: 18),
          label: Text('标准 OTA'),
        ),
        ButtonSegment<PackageMode>(
          value: PackageMode.androidTheme,
          icon: Icon(CupertinoIcons.device_phone_portrait, size: 18),
          label: Text('主题包'),
        ),
      ],
      selected: <PackageMode>{mode},
      onSelectionChanged: (values) => onChanged(values.single),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: _AppColors.secondaryText),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _AppColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _AppColors.tertiaryText,
                ),
          ),
      ],
    );
  }
}

class _ImageInputTile extends StatefulWidget {
  const _ImageInputTile({
    required this.title,
    required this.path,
    required this.probe,
    required this.onPick,
    required this.onDrop,
  });

  final String title;
  final String? path;
  final ImageProbe? probe;
  final VoidCallback onPick;
  final Future<void> Function(List<String> paths) onDrop;

  @override
  State<_ImageInputTile> createState() => _ImageInputTileState();
}

class _ImageInputTileState extends State<_ImageInputTile> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final valid = widget.probe?.isRequiredPreviewSize == true;
    final imageProbe = widget.probe;
    final statusColor = valid ? _AppColors.success : _AppColors.warning;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        await widget.onDrop(
          details.files.map((file) => file.path).toList(growable: false),
        );
      },
      child: _Panel(
        padding: const EdgeInsets.all(10),
        highlighted: _dragging,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                _IconTextButton(
                  icon: CupertinoIcons.folder,
                  label: '选择',
                  onPressed: widget.onPick,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '拖入 PNG 或点击选择',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        _dragging ? _AppColors.accent : _AppColors.tertiaryText,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 9),
            _PreviewStrip(path: widget.path, compact: true),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  valid
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.info_circle_fill,
                  color: statusColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    imageProbe == null
                        ? '未选择'
                        : '${imageProbe.width}x${imageProbe.height}  alpha ${imageProbe.alphaMin}-${imageProbe.alphaMax}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AppColors.secondaryText,
                        ),
                  ),
                ),
              ],
            ),
            if (widget.path != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                p.basename(widget.path!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AppColors.tertiaryText,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StandardOutputFields extends StatelessWidget {
  const _StandardOutputFields({
    required this.outputZipPath,
    required this.onPickOutput,
  });

  final String outputZipPath;
  final VoidCallback onPickOutput;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionLabel(
          icon: CupertinoIcons.square_arrow_down,
          title: '输出',
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: onPickOutput,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            isEmpty: outputZipPath.isEmpty,
            decoration: InputDecoration(
              labelText: 'OTA zip',
              suffixIcon: IconButton(
                tooltip: '选择输出路径',
                onPressed: onPickOutput,
                icon: const Icon(CupertinoIcons.ellipsis_circle),
              ),
            ),
            child: Text(
              outputZipPath.isEmpty
                  ? '未选择'
                  : redactSensitivePaths(outputZipPath),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeFields extends StatelessWidget {
  const _ThemeFields({
    required this.themeNameController,
    required this.authorController,
    required this.notesController,
    required this.libraryRootPath,
  });

  final TextEditingController themeNameController;
  final TextEditingController authorController;
  final TextEditingController notesController;
  final String? libraryRootPath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionLabel(
          icon: CupertinoIcons.slider_horizontal_3,
          title: '主题信息',
        ),
        const SizedBox(height: 10),
        TextField(
          controller: themeNameController,
          decoration: const InputDecoration(labelText: '主题名称'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: authorController,
          decoration: const InputDecoration(labelText: '作者'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: notesController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 8),
        Text(
          libraryRootPath == null
              ? '主题库初始化中'
              : redactSensitivePaths(libraryRootPath),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AppColors.tertiaryText,
              ),
        ),
      ],
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.running, required this.onRun});

  final bool running;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onRun,
        icon: running
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(CupertinoIcons.play_fill, size: 18),
        label: Text(running ? '打包中' : '开始打包'),
        style: FilledButton.styleFrom(
          backgroundColor: _AppColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _Workbench extends StatelessWidget {
  const _Workbench({
    required this.mode,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.result,
    required this.packagePath,
    required this.outputFolderPath,
    required this.summary,
    required this.logs,
    required this.themes,
    required this.onDeleteTheme,
    required this.onOpenOutputFolder,
    required this.onOpenThemeFolder,
    required this.onRefreshLibrary,
  });

  final PackageMode mode;
  final String? lightImagePath;
  final String? darkImagePath;
  final PackageBuildResult? result;
  final String? packagePath;
  final String? outputFolderPath;
  final PackageReportSummary? summary;
  final List<String> logs;
  final List<ThemeLibraryEntry> themes;
  final ValueChanged<ThemeLibraryEntry> onDeleteTheme;
  final VoidCallback onOpenOutputFolder;
  final ValueChanged<ThemeLibraryEntry> onOpenThemeFolder;
  final VoidCallback onRefreshLibrary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1060 && constraints.hasBoundedHeight;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _HeroStatus(
                                mode: mode,
                                lightImagePath: lightImagePath,
                                darkImagePath: darkImagePath,
                                summary: summary,
                                packagePath: packagePath,
                              ),
                              const SizedBox(height: 14),
                              _PreviewPanel(
                                lightImagePath: lightImagePath,
                                darkImagePath: darkImagePath,
                              ),
                              const SizedBox(height: 14),
                              _ReportPanel(
                                summary: summary,
                                result: result,
                                packagePath: packagePath,
                                outputFolderPath: outputFolderPath,
                                onOpenOutputFolder: onOpenOutputFolder,
                              ),
                              const SizedBox(height: 14),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: constraints.maxWidth >= 1240 ? 420 : 360,
                        child: SingleChildScrollView(
                          child: _ThemeLibraryPanel(
                            themes: themes,
                            onDeleteTheme: onDeleteTheme,
                            onOpenThemeFolder: onOpenThemeFolder,
                            onRefresh: onRefreshLibrary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _LogPanel(logs: logs),
                const SizedBox(height: 14),
              ],
            ),
          );
        }

        final content = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _HeroStatus(
                mode: mode,
                lightImagePath: lightImagePath,
                darkImagePath: darkImagePath,
                summary: summary,
                packagePath: packagePath,
              ),
              const SizedBox(height: 14),
              _PreviewPanel(
                lightImagePath: lightImagePath,
                darkImagePath: darkImagePath,
              ),
              const SizedBox(height: 14),
              _ReportPanel(
                summary: summary,
                result: result,
                packagePath: packagePath,
                outputFolderPath: outputFolderPath,
                onOpenOutputFolder: onOpenOutputFolder,
              ),
              const SizedBox(height: 14),
              _LogPanel(logs: logs),
              const SizedBox(height: 14),
              _ThemeLibraryPanel(
                themes: themes,
                onDeleteTheme: onDeleteTheme,
                onOpenThemeFolder: onOpenThemeFolder,
                onRefresh: onRefreshLibrary,
              ),
            ],
          ),
        );

        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: content);
        }
        return content;
      },
    );
  }
}

class _HeroStatus extends StatelessWidget {
  const _HeroStatus({
    required this.mode,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.summary,
    required this.packagePath,
  });

  final PackageMode mode;
  final String? lightImagePath;
  final String? darkImagePath;
  final PackageReportSummary? summary;
  final String? packagePath;

  @override
  Widget build(BuildContext context) {
    final passed = summary?.allPassed;
    final statusText = passed == null ? '待打包' : (passed ? '校验通过' : '校验异常');
    final statusColor = passed == null
        ? _AppColors.tertiaryText
        : (passed ? _AppColors.success : _AppColors.danger);
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: mode == PackageMode.standardOta
                      ? CupertinoIcons.archivebox
                      : CupertinoIcons.cube_box,
                  label: '模式',
                  value: mode == PackageMode.standardOta ? '标准 OTA' : '主题包',
                  color: _AppColors.accent,
                ),
              ),
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: CupertinoIcons.photo_on_rectangle,
                  label: '输入图片',
                  value:
                      '${(lightImagePath == null ? 0 : 1) + (darkImagePath == null ? 0 : 1)} / 2',
                  color: lightImagePath != null && darkImagePath != null
                      ? _AppColors.success
                      : _AppColors.tertiaryText,
                ),
              ),
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: CupertinoIcons.doc_text,
                  label: '输出',
                  value: packagePath == null
                      ? (mode == PackageMode.standardOta
                          ? 'OTA zip'
                          : '.cwtheme')
                      : p.basename(packagePath!),
                  color: packagePath == null
                      ? _AppColors.tertiaryText
                      : _AppColors.success,
                ),
              ),
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: CupertinoIcons.checkmark_shield,
                  label: '校验',
                  value: statusText,
                  color: statusColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _AppColors.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _AppColors.separator),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _AppColors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.lightImagePath,
    required this.darkImagePath,
  });

  final String? lightImagePath;
  final String? darkImagePath;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _PanelHeader(
            icon: CupertinoIcons.rectangle_stack,
            title: '预览',
            trailing: 'Day / Night',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 560;
              final children = <Widget>[
                _PreviewFrame(label: '白天', path: lightImagePath),
                _PreviewFrame(label: '黑夜', path: darkImagePath),
              ];
              if (!sideBySide) {
                return Column(
                  children: <Widget>[
                    children[0],
                    const SizedBox(height: 12),
                    children[1],
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: children[0]),
                  const SizedBox(width: 12),
                  Expanded(child: children[1]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.label, required this.path});

  final String label;
  final String? path;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _AppColors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            if (path != null)
              Flexible(
                child: Text(
                  p.basename(path!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _AppColors.tertiaryText,
                      ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _PreviewStrip(path: path, compact: false),
      ],
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.path, required this.compact});

  final String? path;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 8 : 10),
      child: AspectRatio(
        aspectRatio: 2198 / 367,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xff161a1d)),
          child: path == null
              ? const Center(
                  child: Icon(
                    CupertinoIcons.photo,
                    color: Color(0xff6f777d),
                    size: 22,
                  ),
                )
              : Image.file(File(path!), fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.summary,
    required this.result,
    required this.packagePath,
    required this.outputFolderPath,
    required this.onOpenOutputFolder,
  });

  final PackageReportSummary? summary;
  final PackageBuildResult? result;
  final String? packagePath;
  final String? outputFolderPath;
  final VoidCallback onOpenOutputFolder;

  @override
  Widget build(BuildContext context) {
    final checks = summary?.checks ?? const <ReportCheck>[];
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PanelHeader(
            icon: CupertinoIcons.checkmark_shield,
            title: '校验报告',
            trailing: result == null ? 'report.json' : null,
            trailingWidget: result == null
                ? null
                : _IconTextButton(
                    icon: CupertinoIcons.folder,
                    label: '打开输出文件夹',
                    onPressed: onOpenOutputFolder,
                  ),
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 12),
            if (packagePath != null)
              _PathLine(label: '最终产物', value: packagePath!),
            _PathLine(label: 'OTA zip', value: result!.outputZipPath),
            _PathLine(label: 'report', value: result!.reportPath),
            if (outputFolderPath != null)
              _PathLine(label: '文件夹', value: outputFolderPath!),
          ],
          const SizedBox(height: 14),
          if (checks.isEmpty)
            const _EmptyState(icon: CupertinoIcons.doc_text, text: '暂无报告')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 820 ? 2 : 1;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: checks
                      .map(
                        (check) => SizedBox(
                          width: (constraints.maxWidth - (columns - 1) * 10) /
                              columns,
                          child: _CheckTile(check: check),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final ReportCheck check;

  @override
  Widget build(BuildContext context) {
    final color = check.passed ? _AppColors.success : _AppColors.danger;
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            check.passed
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.exclamationmark_circle_fill,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  check.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  check.detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _AppColors.secondaryText,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogPanel extends StatefulWidget {
  const _LogPanel({required this.logs});

  final List<String> logs;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final _scrollController = ScrollController();
  int _previousLogCount = 0;

  @override
  void didUpdateWidget(covariant _LogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length != _previousLogCount) {
      _previousLogCount = widget.logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _PanelHeader(
            icon: CupertinoIcons.doc_text,
            title: '日志',
            trailing: 'CLI',
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 108, maxHeight: 168),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _AppColors.terminal,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Text(
                widget.logs.isEmpty ? '等待开始打包' : widget.logs.join('\n'),
                style: const TextStyle(
                  color: Color(0xffe8eeee),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeLibraryPanel extends StatelessWidget {
  const _ThemeLibraryPanel({
    required this.themes,
    required this.onDeleteTheme,
    required this.onOpenThemeFolder,
    required this.onRefresh,
  });

  final List<ThemeLibraryEntry> themes;
  final ValueChanged<ThemeLibraryEntry> onDeleteTheme;
  final ValueChanged<ThemeLibraryEntry> onOpenThemeFolder;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PanelHeader(
            icon: CupertinoIcons.square_stack_3d_up,
            title: '本地主题库',
            trailingWidget: IconButton(
              tooltip: '刷新主题库',
              onPressed: onRefresh,
              icon: const Icon(CupertinoIcons.refresh, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          if (themes.isEmpty)
            const _EmptyState(icon: CupertinoIcons.archivebox, text: '无历史主题')
          else
            ...themes.map(
              (entry) => _ThemeTile(
                entry: entry,
                onDelete: () => onDeleteTheme(entry),
                onOpenFolder: () => onOpenThemeFolder(entry),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.entry,
    required this.onDelete,
    required this.onOpenFolder,
  });

  final ThemeLibraryEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        entry.allChecksPassed ? _AppColors.success : _AppColors.danger;
    return LayoutBuilder(
      builder: (context, constraints) {
        final thumbWidth = constraints.maxWidth < 390 ? 118.0 : 166.0;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _AppColors.field,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _AppColors.separator),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: thumbWidth,
                child: Column(
                  children: <Widget>[
                    _Thumb(path: entry.lightThumbnailPath),
                    const SizedBox(height: 6),
                    _Thumb(path: entry.darkThumbnailPath),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDate(entry.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _AppColors.secondaryText,
                          ),
                    ),
                    if (entry.author.isNotEmpty)
                      Text(
                        entry.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (entry.notes.isNotEmpty)
                      Text(
                        entry.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _AppColors.secondaryText,
                            ),
                      ),
                    const SizedBox(height: 6),
                    _StatusPill(
                      text: entry.allChecksPassed ? '校验通过' : '校验异常',
                      color: statusColor,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '打开主题文件夹',
                onPressed: onOpenFolder,
                icon: const Icon(CupertinoIcons.folder, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
              IconButton(
                tooltip: '删除主题',
                onPressed: onDelete,
                icon: const Icon(CupertinoIcons.delete, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: AspectRatio(
        aspectRatio: 2198 / 367,
        child: File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.cover)
            : const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xffd9dddc)),
              ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    this.trailing,
    this.trailingWidget,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: _AppColors.secondaryText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
          ),
        ),
        if (trailingWidget != null)
          trailingWidget!
        else if (trailing != null)
          Text(
            trailing!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _AppColors.tertiaryText,
                ),
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    required this.padding,
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? _AppColors.accentWash : _AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? _AppColors.accent : _AppColors.separator,
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0d000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _IconTextButton extends StatelessWidget {
  const _IconTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  const _PathLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AppColors.secondaryText,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              redactSensitivePaths(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _AppColors.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _AppColors.separator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: _AppColors.tertiaryText, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _AppColors.secondaryText,
                ),
          ),
        ],
      ),
    );
  }
}

class _BuildPaths {
  const _BuildPaths({
    required this.outputZipPath,
    required this.workDirPath,
    required this.reportPath,
  });

  final String outputZipPath;
  final String workDirPath;
  final String reportPath;
}

class _BuildResources {
  const _BuildResources({
    required this.inputZipPath,
    required this.astcencPath,
    required this.lightDimMaskPath,
    required this.darkDimMaskPath,
  });

  final String? inputZipPath;
  final String? astcencPath;
  final String? lightDimMaskPath;
  final String? darkDimMaskPath;
}

class _AppColors {
  static const chrome = Color(0xfff3f2ef);
  static const sidebar = Color(0xfffaf9f6);
  static const surface = Color(0xffffffff);
  static const field = Color(0xfff6f6f3);
  static const separator = Color(0xffdedbd4);
  static const chromeLine = Color(0xffd0ccc2);
  static const terminal = Color(0xff14191d);
  static const accent = Color(0xff00616b);
  static const accentWash = Color(0xffe5f3f2);
  static const success = Color(0xff18864b);
  static const warning = Color(0xffa86700);
  static const danger = Color(0xffb3261e);
  static const secondaryText = Color(0xff5c666c);
  static const tertiaryText = Color(0xff879098);
}

String _timestamp(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}${two(value.month)}${two(value.day)}'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}';
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String? _envPath(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
