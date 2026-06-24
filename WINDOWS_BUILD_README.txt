Windows build steps:

1. Right-click CadillacPackager-windows-build-kit.zip and choose Extract All.
2. Open the extracted folder.
3. Right-click build_windows_one_click.cmd and choose Run as administrator.
4. Wait until the script finishes.
5. The final package will be:
   dist\CadillacPackager-windows-x64.zip

If Windows asks for a reboot after installing Visual Studio Build Tools,
reboot and run build_windows_one_click.cmd again.

The build kit includes the currently supported football template. The packaged
app can build packages without setting CADILLAC_INPUT_ZIP.

Current limitation: only the football template is supported. Other official
theme templates will be added in later updates.
