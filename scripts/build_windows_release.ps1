param(
  [string]$OutputDir = "dist",
  [switch]$SkipTests,
  [switch]$SkipPackagerExe
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Test-Command([string]$Command) {
  return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Set-PythonCommand {
  if (Test-Command "py") {
    $script:PythonExe = "py"
    $script:PythonPrefix = @("-3")
    return $true
  }
  if (Test-Command "python") {
    $script:PythonExe = "python"
    $script:PythonPrefix = @()
    return $true
  }

  $knownPython = @(
    "$env:LocalAppData\Programs\Python\Python314\python.exe",
    "$env:LocalAppData\Programs\Python\Python313\python.exe",
    "$env:LocalAppData\Programs\Python\Python312\python.exe",
    "$env:LocalAppData\Programs\Python\Python311\python.exe",
    "$env:ProgramFiles\Python314\python.exe",
    "$env:ProgramFiles\Python313\python.exe",
    "$env:ProgramFiles\Python312\python.exe",
    "$env:ProgramFiles\Python311\python.exe"
  )
  foreach ($candidate in $knownPython) {
    if (Test-Path $candidate) {
      $script:PythonExe = $candidate
      $script:PythonPrefix = @()
      return $true
    }
  }

  return $false
}

function Invoke-Python([string[]]$Arguments) {
  $allArgs = @()
  $allArgs += $script:PythonPrefix
  $allArgs += $Arguments
  & $script:PythonExe @allArgs
}

function Build-PackagerExecutable([string]$ReleaseDir) {
  if ($SkipPackagerExe) {
    Write-Warning "Skipping standalone packager CLI. The app will require Python with Pillow at runtime."
    return
  }

  if (!(Set-PythonCommand)) {
    throw "Python 3 is required to build the standalone packager CLI. Run setup_and_build_windows.ps1 or pass -SkipPackagerExe."
  }

  Write-Host "Building standalone packager CLI with $script:PythonExe"
  Invoke-Python @("-m", "pip", "install", "--upgrade", "pip", "Pillow", "pyinstaller")
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install PyInstaller/Pillow for the standalone packager CLI."
  }

  $runtimeDir = Join-Path $ReleaseDir "packager_runtime"
  $pyinstallerWorkDir = Join-Path $projectRoot "build\pyinstaller"
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  New-Item -ItemType Directory -Force -Path $pyinstallerWorkDir | Out-Null

  Invoke-Python @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--name", "cadillac_wallpaper_packager",
    "--distpath", $runtimeDir,
    "--workpath", $pyinstallerWorkDir,
    "--specpath", $pyinstallerWorkDir,
    "--paths", (Join-Path $projectRoot "packager"),
    "--hidden-import", "kzb_astc_patcher",
    (Join-Path $projectRoot "packager\cadillac_wallpaper_packager.py")
  )
  if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller failed building the standalone packager CLI."
  }

  $packagerExePath = Join-Path $runtimeDir "cadillac_wallpaper_packager.exe"
  if (!(Test-Path $packagerExePath)) {
    throw "Missing standalone packager CLI: $packagerExePath"
  }
}

function Resolve-WindowsReleaseDir {
  $candidates = @(
    (Join-Path $projectRoot "build\windows\x64\runner\Release"),
    (Join-Path $projectRoot "build\windows\runner\Release")
  )
  foreach ($candidate in $candidates) {
    $candidateExe = Join-Path $candidate "cadillac_wallpaper_desktop.exe"
    if (Test-Path $candidateExe) {
      return $candidate
    }
  }
  return $candidates[0]
}

flutter pub get
flutter analyze
if (!$SkipTests) {
  flutter test
}
flutter build windows --release

$releaseDir = Resolve-WindowsReleaseDir
$exePath = Join-Path $releaseDir "cadillac_wallpaper_desktop.exe"
$astcencPath = Join-Path $releaseDir "data\flutter_assets\packager\tools\windows\astcenc.exe"

if (!(Test-Path $exePath)) {
  throw "Missing Windows executable: $exePath"
}
if (!(Test-Path $astcencPath)) {
  throw "Missing bundled Windows astcenc.exe: $astcencPath"
}

Build-PackagerExecutable -ReleaseDir $releaseDir

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$zipPath = Join-Path $OutputDir "CadillacPackager-windows-x64.zip"
if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath

Write-Host "Windows release package:"
Write-Host (Resolve-Path $zipPath)
