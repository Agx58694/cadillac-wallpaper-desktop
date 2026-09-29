# 从电脑打包到车机应用

本文描述两张**静态白天/黑夜图片**的完整流程：电脑端出包，车机“壁纸空间”导入并请求应用。适用性取决于车机车型、OTA 版本和原厂服务；应用显示“成功”以本次系统回调为准。

## 1. 选对程序

下载 v1.1.0 对应附件；桌面 ZIP 解压后运行：

| 设备 | 下载文件 |
| --- | --- |
| macOS 12+ Apple Silicon / Intel | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-macos-universal.zip) |
| Windows x64 | [CadillacPackager-windows-x64.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-windows-x64.zip) |
| Android 12+ 车机 | [wallpaper-studio-0.2.1-test.apk](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/wallpaper-studio-0.2.1-test.apk) |

这些链接在 v1.1.0 Release 发布后生效；GitHub 自动提供的 `Source code` 是源码，不能直接运行。

v1.1.0 macOS 分发包内含 x86_64 和 arm64 两套 Python/Pillow 打包运行时以及双架构 `astcenc`；Windows x64 分发包内含独立打包运行时和 `astcenc.exe`，正常打包不需另装 Python/Pillow。仅从源码执行 `flutter build macos --release` 不会自动加入打包运行时。

“壁纸空间”的包名是 `com.cadillac.wallpaperstudio`。0.2.1 是**调试签名的验证 APK**，和该应用 0.1.0 / 0.2.0 使用相同签名、可覆盖升级。旧 `com.cadillac.themeinstaller` 是另一个应用，固定写入足球模板目录，不适合本次生成的独立身份包。0.2.1 APK 自带“雨夜球场 V12”示例，首次启动仅导入示例，不自动应用。

## 2. 准备日夜母图

推荐使用两张同构图、不透明的 **8960×1320 PNG**。左侧 5010×1320 对应 IPD，右侧 3950×1320 对应 VCD，两侧接缝在 x=5010。日夜画面应保持主体位置和地平线一致，并按目标车机 OTA 的仪表、卡片、工具栏遮挡检查构图。

也可继续使用两张 **2198×367 PNG** 进入旧预览兼容模式。程序会从较小预览图裁切、放大并生成所需原生资源，因此无法恢复原图没有的细节，也不保证大屏主体位置等同于原生母图。日夜尺寸必须一致；其他尺寸会被拒绝。不要把其他比例的图片硬拉成 8960×1320。

本次只处理静态白天/黑夜两态。静态入口只接受经审计的 `football-static` 模板结构，保留其原有状态和遮罩；动态模板会被拒绝。程序不会替新图自动设计或适配雪花、落叶等专属动画，也不生成四态、右屏视频、天气/时间联动。

## 3. 在电脑端打包

### 标准 OTA ZIP

1. 打开程序，选择“标准 OTA”。
2. 拖入或选择白天 PNG 与黑夜 PNG。程序按尺寸识别原生或旧预览模式。
3. 选择输出位置，点击“开始打包”。
4. 等待最终 ZIP、报告和界面校验全部完成，点击“打开文件夹”。

标准模式输出 `ota_wallpaper.zip` 及旁边的 `package-report.json`；报告不在 OTA ZIP 内。ZIP 内仅有一套壁纸的 9 个文件：两张 2198×367 preview、四张 3950×1320 VCD/dim、两张 1920×1080 RID，以及一个 KZB。路径形如：

```text
<32位十六进制ID>/cadi_wallpaper.../
  light_preview_image.png
  dark_preview_image.png
  light_dim_background.png
  dark_dim_background.png
  vcd/wallpaper/light_wallpaper_vcd.png
  vcd/wallpaper/dark_wallpaper_vcd.png
  rid/screenSaver/light_screenSaver_rid.png
  rid/screenSaver/dark_screenSaver_rid.png
  ipd/wallpaper/<项目身份>.kzb
```

每个内容版本有独立的 KZB 内部项目与资源地址，以及对应的外层目录。再次打包相同内容和主题标识时身份稳定，内容改变会换身份。最终 ZIP 会校验目录和路径安全、9 文件、PNG 尺寸与 alpha、`rec0`、辅助贴图透明区 RGB、内部引用、日夜资源与左右拼接。身份重建后 KZB 大小和记录偏移可以变化；以结构化重建和引用一致性为准。

### `.cwtheme` 主题包

选择“主题包”，用相同的两张 PNG 填写主题名称等信息后打包。这个模式调用同一 OTA 核心，随后把成品放进 `cwtheme/payload/ota_wallpaper.zip`，附上清单、2198×367 预览、缩略图、原始母图和报告，并保存到桌面主题库。原生母图在包内为 `masters/light_master_8960x1320.png` / `masters/dark_master_8960x1320.png`；旧预览模式则对应 `2198x367`。清单安装路径来自实际 OTA 成品，仍使用 schema v1。

## 4. 在车机导入并应用

1. 把电脑生成的 OTA ZIP 或 `.cwtheme` 放到车机文件选择器可访问的位置。
2. 打开“壁纸空间”，点“导入壁纸”，通过系统文件选择器选择文件。程序会检查路径、大小、必需资源、PNG 尺寸和 KZB 标识；不通过就不要应用。
3. 选择刚导入的壁纸，分别查看白天、黑夜预览。重复导入相同内容会选中现有条目。
4. 点“应用壁纸”。程序准备独立目录，向原厂通道传输仪表资源，发布 Android 侧资源，再请求系统切换。
5. 看到对应本次 ID 的成功回调才算已应用。失败时打开“车机与记录”看步骤；超时代表**结果待确认**，请先观察左右屏，勿仅凭请求已发出就判断成功。

安装器通过系统文件选择器和 MediaStore 工作，不需用户授予“所有文件访问”权限。它不会自动应用首次导入的包。进入壁纸桌面模式的后续请求本身没有确认回调；实车是否已进入该模式还需查看车机。0.2.1 的导入、传输和界面经过本地/模拟器测试，**该版本尚无本线程的实车结果**；先前版本与独立身份对照包有实车 A/B/A 左右屏即时更新反馈，不能推广为所有车型、OTA 或任意新包都免重启。

## 5. 常见问题与可选配置

- **提示图片尺寸不符**：两张都导出为 8960×1320 原生 PNG，或都使用 2198×367 旧预览 PNG。不要混用。
- **提示模板不受支持**：程序只内置已适配的静态足球模板；其他包必须符合已审计的 `football-static` 结构，未知或动态结构会被拒绝。
- **校验失败**：查看 `package-report.json` 和界面中的具体项目；不要拿未通过的 ZIP 上车。
- **应用结果待确认**：查看“车机与记录”以及左右屏实际画面，再决定是否重试。
- **macOS 打不开**：先尝试在 Finder 中右键应用并选择“打开”；v1.1.0 分发包已内置 Python/Pillow 运行时。
- **运行较慢**：完整 ASTC 编码和解码校验会耗时，界面日志会持续显示进度。

默认使用随桌面程序附带的足球模板和编码器。需要本地测试兼容模板或工具时可设置：

| 环境变量 | 用途 |
| --- | --- |
| `CADILLAC_INPUT_ZIP` | 覆盖内置模板 ZIP；结构未知会拒绝 |
| `CADILLAC_ASTCENC` | 覆盖内置 ASTC 编码器 |
| `CADILLAC_PACKAGER_CLI` | 覆盖内置独立打包 runtime |
| `CADILLAC_PYTHON`、`CADILLAC_PACKAGER_SCRIPT` | 使用外部 Python 与打包源码 |
| `CADILLAC_LIGHT_DIM_MASK`、`CADILLAC_DARK_DIM_MASK` | 本地测试 dim mask |

macOS 从 Finder 双击启动的应用未必继承终端环境变量；需要覆盖时从终端启动应用。Windows 可用 PowerShell 的 `$env:变量名="值"` 临时设置环境变量。

## 6. 开发者验证

```bash
flutter pub get
flutter analyze
flutter test
PYTHONPATH=packager python3 -m unittest discover -s packager/tests -p 'test_*.py'
```

macOS/Windows release 构建工作流位于 `.github/workflows/desktop-release.yml`，手动触发后上传 Actions artifacts。macOS 合包会验证 Flutter 主程序、Python 启动器、两套架构专属 runtime 与 `astcenc`，并在各自架构机器上运行打包 CLI。Windows 使用 `scripts/build_windows_release.ps1` 制作带独立 Python runtime 的 x64 ZIP。正式 GitHub Release 及附件发布是另一步，不能把 Actions artifact 当作正式发布。

## 一起完善

欢迎车友测试不同车型和 OTA 版本、提出体验建议，或帮忙制作教程和视频。本项目坚持开源免费。

<img src="assets/wechat-contact.png" alt="微信联系方式" width="240">

禁止偷电
