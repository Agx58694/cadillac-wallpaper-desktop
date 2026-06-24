import 'dart:io';

import 'package:cadillac_wallpaper_desktop/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  late Directory supportDir;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('cadillac_widget_');
    _FakePathProviderPlatform.supportPath = supportDir.path;
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  tearDown(() {
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  testWidgets('renders the modern desktop shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CadillacWallpaperDesktopApp());
    await tester.pump();

    expect(find.text('Cadillac Packager'), findsOneWidget);
    expect(find.text('标准 OTA'), findsWidgets);
    expect(find.text('主题包'), findsWidgets);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('校验报告'), findsOneWidget);
    expect(find.text('本地主题库'), findsOneWidget);
    expect(find.textContaining('拖入 PNG'), findsWidgets);
    expect(find.text('打开输出文件夹'), findsNothing);
    expect(find.text('主题名称'), findsNothing);
    expect(find.text('作者'), findsNothing);
    expect(find.text('备注'), findsNothing);
  });

  testWidgets('switches to Android theme mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const CadillacWallpaperDesktopApp());
    await tester.pump();
    await tester.tap(find.text('主题包'));
    await tester.pump();

    expect(find.text('主题信息'), findsOneWidget);
    expect(find.text('主题名称'), findsOneWidget);
    expect(find.text('作者'), findsOneWidget);
    expect(find.text('备注'), findsOneWidget);
    expect(find.text('本地主题库'), findsWidgets);
    expect(find.text('OTA zip'), findsNothing);
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  static String supportPath = '/tmp/cadillac_test';

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}
