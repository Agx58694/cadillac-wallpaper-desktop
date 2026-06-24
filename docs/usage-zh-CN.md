# 使用说明

Cadillac Wallpaper Desktop 是一个桌面打包工具，用两张 `2198x367` PNG 主图生成 Cadillac 兼容的 OTA 壁纸包，或生成可供 Android 联动安装器使用的 `.cwtheme` 主题包。

## 下载哪个版本

从 [GitHub 最新 Release](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest) 下载对应系统的 zip：

| 系统 | 下载文件 |
| --- | --- |
| macOS Apple Silicon / M 系列 | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest/download/CadillacPackager-macos-universal.zip) |
| macOS Intel | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest/download/CadillacPackager-macos-universal.zip) |
| Windows x64 | [CadillacPackager-windows-x64.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/latest/download/CadillacPackager-windows-x64.zip) |

Release 页面里会同时出现 `Source code (zip)` 和 `Source code (tar.gz)`。这两个是源码包，不是可直接运行的桌面程序；普通用户请下载上表中的 `CadillacPackager-*.zip`。

解压后直接运行应用。macOS 如果提示来自未认证开发者，可以右键应用选择“打开”；如果仍被阻止，可在终端执行：

```bash
xattr -dr com.apple.quarantine "/path/to/Cadillac Packager.app"
```

## 运行前准备

应用需要以下输入：

- 白天主图：PNG，尺寸必须是 `2198x367`。
- 黑夜主图：PNG，尺寸必须是 `2198x367`。
- macOS 版本需要 Python 3 和 Pillow。
- Windows x64 release 已内置独立打包 Runtime，通常不需要额外安装 Python/Pillow。

应用已经内置当前支持的足球模板，正常下载 release 后不需要额外配置模板 zip。

> 当前版本只适配足球模板这一款。其他官方主题模板结构不同，后续版本再逐步适配。

macOS 安装 Pillow：

```bash
python3 -m pip install Pillow
```

如果使用 Windows 源码构建包，或者手动指定外部 Python 脚本，Windows 也可以使用：

```powershell
py -m pip install Pillow
```

## 可选：覆盖模板 zip

默认会使用内置足球模板。只有在需要测试兼容模板时，才通过环境变量覆盖：

```bash
CADILLAC_INPUT_ZIP=/path/to/template.zip
```

macOS 双击打开的应用不一定继承 shell 环境变量。如果要覆盖模板，推荐用终端启动：

```bash
export CADILLAC_INPUT_ZIP="/path/to/template.zip"
export CADILLAC_PYTHON="$(command -v python3)"
"/Applications/Cadillac Packager.app/Contents/MacOS/cadillac_wallpaper_desktop"
```

如果应用还在下载目录，可以把最后一行换成对应 `.app` 内的可执行文件路径。

Windows 临时启动：

```powershell
$env:CADILLAC_INPUT_ZIP="C:\path\to\template.zip"
.\cadillac_wallpaper_desktop.exe
```

Windows 持久配置：

```powershell
setx CADILLAC_INPUT_ZIP "C:\path\to\template.zip"
```

执行 `setx` 后需要重新打开终端或重新启动应用。

可选环境变量：

| 变量 | 用途 |
| --- | --- |
| `CADILLAC_PYTHON` | 指定带 Pillow 的 Python 可执行文件 |
| `CADILLAC_PACKAGER_SCRIPT` | 指定外部 `cadillac_wallpaper_packager.py` |
| `CADILLAC_ASTCENC` | 指定外部 `astcenc` / `astcenc.exe` |
| `CADILLAC_LIGHT_DIM_MASK` | 指定白天 dim mask |
| `CADILLAC_DARK_DIM_MASK` | 指定黑夜 dim mask |

## 标准 OTA 打包

1. 选择“标准 OTA”。
2. 拖入或选择白天 `2198x367` PNG。
3. 拖入或选择黑夜 `2198x367` PNG。
4. 选择 OTA zip 输出位置。
5. 点击“开始打包”。
6. 打包完成后查看校验结果，并使用“打开文件夹”进入输出目录。

标准 OTA 模式会输出：

- `ota_wallpaper.zip`
- `report.json` 或 `package-report.json`

这个模式适合即用即丢，不会强制保存历史记录。

## Android 联动主题包

1. 选择“主题包”。
2. 拖入或选择白天 `2198x367` PNG。
3. 拖入或选择黑夜 `2198x367` PNG。
4. 填写主题名称、作者和备注。
5. 点击“开始打包”。
6. 打包完成后使用“打开文件夹”进入主题包目录。

主题包模式会输出 `.cwtheme`，并保存到桌面端本地主题库。下次打开软件仍能看到历史主题、预览和校验状态，除非在软件里主动删除。

`.cwtheme` 内部结构：

```text
cwtheme/
  manifest.json
  previews/light_preview_2198x367.png
  previews/dark_preview_2198x367.png
  previews/thumbnail_light.png
  previews/thumbnail_dark.png
  masters/light_master_2198x367.png
  masters/dark_master_2198x367.png
  payload/ota_wallpaper.zip
  report/package-report.json
```

## 校验结果说明

应用不会只显示“成功”。打包完成后会读取 report 并展示关键校验：

- zip 完整性。
- PNG 尺寸和 alpha。
- preview alpha 是否复用模板。
- KZB size 是否不变。
- KZB record offset 是否不变。
- `rec0` 是否保持。
- `rec1`、`rec2`、`rec4`、`rec5` 中 alpha 为 0 的 RGB 是否为 `[0,0,0]`。
- KZB/VCD 拼接 MAE。

如果任一关键校验失败，不建议继续使用该产物。

## 常见问题

### 提示模板 zip 缺失

重新下载包含内置足球模板的 release。也可以设置 `CADILLAC_INPUT_ZIP` 指向兼容模板 zip 后重新启动应用。

### 提示 Pillow 不可用

安装 Pillow，或通过 `CADILLAC_PYTHON` 指定已经安装 Pillow 的 Python。

### 图片尺寸不正确

白天和黑夜主图都必须是 `2198x367` PNG。请先在图片编辑工具中裁切或导出为这个尺寸。

### macOS 打不开应用

先尝试右键应用选择“打开”。如果仍然被拦截，移除 quarantine 标记：

```bash
xattr -dr com.apple.quarantine "/path/to/Cadillac Packager.app"
```

### 打包时间较长像卡住

查看界面右侧日志。日志会显示 Python CLI 调用、输入检查、OTA 打包、主题封装、report 读取、输出路径等步骤。
