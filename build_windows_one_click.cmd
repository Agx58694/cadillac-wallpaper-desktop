@echo off
setlocal

cd /d "%~dp0"

echo Cadillac Packager Windows build
echo.
echo This script will check/install build dependencies and create:
echo   dist\CadillacPackager-windows-x64.zip
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup_and_build_windows.ps1"

echo.
if errorlevel 1 (
  echo Build failed. Check the messages above.
  pause
  exit /b 1
)

echo Build completed.
pause
