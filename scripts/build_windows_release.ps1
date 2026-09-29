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
  if (Test-Command "python") {
    $script:PythonExe = "python"
    $script:PythonPrefix = @()
    return $true
  }
  if (Test-Command "py") {
    $script:PythonExe = "py"
    $script:PythonPrefix = @("-3")
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
  Invoke-Python @("-m", "pip", "install", "--requirement", "scripts/packager_runtime_requirements.txt")
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install PyInstaller/Pillow for the standalone packager CLI."
  }

  $runtimeDir = Join-Path $ReleaseDir "packager_runtime"
  $pyinstallerWorkDir = Join-Path $projectRoot "build\pyinstaller"
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  New-Item -ItemType Directory -Force -Path $pyinstallerWorkDir | Out-Null

  $pyinstallerArgs = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--name", "cadillac_wallpaper_packager",
    "--distpath", $runtimeDir,
    "--workpath", $pyinstallerWorkDir,
    "--specpath", $pyinstallerWorkDir,
    "--paths", (Join-Path $projectRoot "packager")
  )
  Get-ChildItem (Join-Path $projectRoot "packager") -File -Filter "*.py" | ForEach-Object {
    if ($_.BaseName -ne "cadillac_wallpaper_packager" -and $_.BaseName -ne "__init__") {
      $pyinstallerArgs += @("--hidden-import", $_.BaseName)
    }
  }
  $pyinstallerArgs += (Join-Path $projectRoot "packager\cadillac_wallpaper_packager.py")
  Invoke-Python -Arguments $pyinstallerArgs
  if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller failed building the standalone packager CLI."
  }
  Invoke-Python -Arguments @(
    (Join-Path $projectRoot "scripts\copy_packager_runtime_licenses.py"),
    (Join-Path $runtimeDir "third_party_licenses")
  )
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to include Python/Pillow/PyInstaller license texts."
  }

  $packagerExePath = Join-Path $runtimeDir "cadillac_wallpaper_packager.exe"
  if (!(Test-Path $packagerExePath)) {
    throw "Missing standalone packager CLI: $packagerExePath"
  }
  & $packagerExePath --help | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Standalone packager CLI failed to start: $packagerExePath"
  }
  $probePath = Join-Path $pyinstallerWorkDir "runtime-probe-missing-template.zip"
  $probeOutput = & $packagerExePath `
    --light-image (Join-Path $pyinstallerWorkDir "runtime-probe-light.png") `
    --dark-image (Join-Path $pyinstallerWorkDir "runtime-probe-dark.png") `
    --input-zip $probePath `
    --output-zip (Join-Path $pyinstallerWorkDir "runtime-probe-unused.zip") `
    --source-mode native 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0 -or !$probeOutput.Contains("runtime-probe-missing-template.zip")) {
    throw "Standalone packager runtime did not reach the expected missing-template boundary. Output: $probeOutput"
  }
  # The failed input probe is expected; do not let its native exit code mark
  # an otherwise successful PowerShell release script as failed.
  $global:LASTEXITCODE = 0
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
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }
if (!$SkipTests) {
  flutter test
  if ($LASTEXITCODE -ne 0) { throw "flutter test failed." }
}
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release failed." }

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
