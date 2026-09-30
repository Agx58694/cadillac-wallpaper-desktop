# 从电脑打包到车机应用

本说明适用于两张静态白天、黑夜图片。电脑端打包，车机“壁纸空间”导入并请求应用。

## 1. 下载并安装

| 设备 | 下载 |
| --- | --- |
| macOS 12+（Apple Silicon / Intel） | [CadillacPackager-macos-universal.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-macos-universal.zip) |
| Windows x64 | [CadillacPackager-windows-x64.zip](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/CadillacPackager-windows-x64.zip) |
| Android 12+ 车机 | [wallpaper-studio-0.2.1-test.apk](https://github.com/Agx58694/cadillac-wallpaper-desktop/releases/download/v1.1.0/wallpaper-studio-0.2.1-test.apk) |

解压桌面 ZIP 后运行程序，在车机上安装 APK。请选择上表中的附件；GitHub 自动提供的 `Source code` 是源码。APK 是调试签名的验证版，内置一张示例壁纸；首次打开不会自动应用示例。

## 2. 准备两张图片

- 推荐两张同构图、完全不透明的 **8960×1320 PNG**。左侧 IPD 为 5010×1320，右侧 VCD 为 3950×1320，接缝在 x=5010。白天和黑夜的主体位置应一致，并避开车机仪表、卡片和工具栏的遮挡。
- 也可使用两张 **2198×367 PNG** 进入旧版兼容模式，但放大后会损失细节。

两张图必须同尺寸；程序会拒绝混用或其他尺寸。不要把不同比例的图片强行拉伸到 8960×1320。

## 3. 在电脑端打包

1. 打开桌面程序，选择“标准 OTA”或“主题包”。标准 OTA 输出 ZIP；主题包输出 `.cwtheme` 并保存到程序的主题库。两种成品都能在“壁纸空间”导入。
2. 拖入或选择白天、黑夜 PNG。标准 OTA 模式还需选择输出位置。
3. 点击“开始打包”，等待界面显示校验通过，再打开输出文件夹。标准 OTA 的校验报告保存在 ZIP 旁边。

图片编码和成品校验可能需要一段时间，期间可查看界面日志。若校验失败，请勿将未通过的文件用于车机。

## 4. 在车机导入并应用

1. 将生成的 ZIP 或 `.cwtheme` 放到车机文件选择器可访问的位置。
2. 打开“壁纸空间”，点“导入壁纸”，选择文件。
3. 选中导入的壁纸，分别查看白天和黑夜预览。
4. 点“应用壁纸”。收到对应本次壁纸的系统成功回调才算已确认应用；若显示超时或“结果待确认”，请查看左右屏画面与“车机与记录”，再决定是否重试。

0.2.1 的导入与界面流程经过本地和模拟器检查，**本版新生成的壁纸尚无本次实车应用结果**。实际效果仍需按车型和 OTA 版本验证。

## 常见问题

- **图片尺寸不符**：两张都用 8960×1320，或都用 2198×367；不要混用。
- **模板不受支持**：本版只支持程序内置的静态日夜模板，不支持动态模板。
- **macOS 提示无法打开**：在 Finder 中右键应用，选择“打开”。分发包已内置打包运行时，不需单独安装 Python。
- **打包较慢**：等待图片编码和成品校验完成，可查看进度日志。
- **应用结果待确认**：查看车机左右屏与“车机与记录”；仅发送应用请求不能证明已生效。
