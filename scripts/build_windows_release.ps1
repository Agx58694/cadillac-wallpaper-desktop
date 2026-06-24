param(
  [string]$OutputDir = "dist",
  [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

flutter pub get
flutter analyze
if (!$SkipTests) {
  flutter test
}
flutter build windows --release

$releaseDir = Join-Path $projectRoot "build\windows\runner\Release"
$exePath = Join-Path $releaseDir "cadillac_wallpaper_desktop.exe"
$astcencPath = Join-Path $releaseDir "data\flutter_assets\packager\tools\windows\astcenc.exe"

if (!(Test-Path $exePath)) {
  throw "Missing Windows executable: $exePath"
}
if (!(Test-Path $astcencPath)) {
  throw "Missing bundled Windows astcenc.exe: $astcencPath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$zipPath = Join-Path $OutputDir "CadillacPackager-windows-x64.zip"
if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath

Write-Host "Windows release package:"
Write-Host (Resolve-Path $zipPath)
