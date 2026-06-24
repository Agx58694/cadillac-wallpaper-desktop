param(
  [string]$OutputDir = "dist",
  [switch]$SkipTests,
  [switch]$NoInstall
)

$ErrorActionPreference = "Stop"
$FlutterVersion = "3.13.9"
$RebootRecommended = $false

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-IsWindows {
  return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-AsAdministrator {
  if (Test-IsAdministrator) {
    return
  }

  if ($NoInstall) {
    throw "Missing dependencies and -NoInstall was specified. Re-run without -NoInstall or install them manually."
  }

  Write-Host "Installing missing system dependencies requires Administrator permission."
  Write-Host "A new elevated PowerShell window will open. Continue from there."

  $arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSCommandPath`"",
    "-OutputDir", "`"$OutputDir`""
  )
  if ($SkipTests) {
    $arguments += "-SkipTests"
  }

  Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
  exit 0
}

function Update-ProcessPath {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = "$machinePath;$userPath"
}

function Test-Command([string]$Command) {
  return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Ensure-Winget {
  if (Test-Command "winget") {
    return
  }
  throw "winget is not available. Install Microsoft App Installer from Microsoft Store, then run this script again."
}

function Install-WingetPackage(
  [string]$Id,
  [string]$Name,
  [string]$Override = ""
) {
  if ($NoInstall) {
    throw "$Name is missing and -NoInstall was specified."
  }

  Ensure-Winget
  Restart-AsAdministrator

  Write-Step "Installing $Name with winget"
  $args = @(
    "install",
    "-e",
    "--id", $Id,
    "--accept-package-agreements",
    "--accept-source-agreements",
    "--disable-interactivity"
  )
  if ($Override.Trim().Length -gt 0) {
    $args += "--override"
    $args += $Override
  }

  & winget @args
  $exitCode = $LASTEXITCODE
  if ($exitCode -eq 3010) {
    $script:RebootRecommended = $true
    Write-Warning "$Name installed and Windows requested a reboot. The script will continue, but reboot if the build still fails."
  } elseif ($exitCode -ne 0) {
    throw "winget failed installing $Name. Exit code: $exitCode"
  }

  Update-ProcessPath
}

function Ensure-Git {
  Write-Step "Checking Git"
  if (Test-Command "git") {
    git --version
    return
  }

  Install-WingetPackage -Id "Git.Git" -Name "Git for Windows"
  if (!(Test-Command "git")) {
    throw "Git was installed but is not visible in PATH. Restart PowerShell and run this script again."
  }
  git --version
}

function Get-VsWherePath {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }
  return $null
}

function Test-VsCppTools {
  $vswhere = Get-VsWherePath
  if ($null -eq $vswhere) {
    return $false
  }

  $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  return $LASTEXITCODE -eq 0 -and $installPath -and (Test-Path $installPath)
}

function Ensure-VsCppTools {
  Write-Step "Checking Visual Studio C++ Build Tools"
  if (Test-VsCppTools) {
    Write-Host "Visual Studio C++ build tools detected."
    return
  }

  Install-WingetPackage `
    -Id "Microsoft.VisualStudio.2022.BuildTools" `
    -Name "Visual Studio 2022 Build Tools with C++ workload" `
    -Override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

  if (!(Test-VsCppTools)) {
    throw "Visual Studio C++ build tools are still not detected. Reboot Windows or open Visual Studio Installer and ensure Desktop development with C++ is installed."
  }
  Write-Host "Visual Studio C++ build tools detected."
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
    "$env:ProgramFiles\Python314\python.exe",
    "$env:ProgramFiles\Python313\python.exe",
    "$env:ProgramFiles\Python312\python.exe"
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

function Ensure-PythonAndPillow {
  Write-Step "Checking Python and Pillow"
  if (!(Set-PythonCommand)) {
    Install-WingetPackage -Id "Python.Python.3.12" -Name "Python 3.12"
    Update-ProcessPath
    if (!(Set-PythonCommand)) {
      throw "Python was installed but is not visible. Restart PowerShell and run this script again."
    }
  }

  Invoke-Python @("--version")

  Invoke-Python @("-m", "pip", "--version") | Out-Host
  if ($LASTEXITCODE -ne 0) {
    Invoke-Python @("-m", "ensurepip", "--upgrade")
  }

  Invoke-Python @("-c", "import PIL") 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Step "Installing Pillow"
    Invoke-Python @("-m", "pip", "install", "--upgrade", "pip", "Pillow")
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to install Pillow."
    }
  }

  Invoke-Python @("-c", "import PIL; print('Pillow OK')")
  if ($LASTEXITCODE -ne 0) {
    throw "Pillow import check failed."
  }
}

function Ensure-NuGet {
  Write-Step "Checking NuGet"
  if (Test-Command "nuget") {
    nuget help | Select-Object -First 1
    return
  }

  Install-WingetPackage -Id "Microsoft.NuGet" -Name "NuGet CLI"
  if (!(Test-Command "nuget")) {
    Write-Warning "NuGet was installed but is not visible in PATH. Flutter may still work if Visual Studio provides the required tooling."
  }
}

function Ensure-Flutter {
  param([string]$ProjectRoot)

  Write-Step "Checking Flutter"
  $localFlutter = Join-Path $ProjectRoot ".tooling\flutter\bin\flutter.bat"
  if (Test-Path $localFlutter) {
    $env:Path = "$(Split-Path -Parent $localFlutter);$env:Path"
    & $localFlutter --version
    return
  }

  if (Test-Command "flutter") {
    flutter --version
    return
  }

  if ($NoInstall) {
    throw "Flutter is missing and -NoInstall was specified."
  }

  Ensure-Git

  Write-Step "Installing local Flutter SDK $FlutterVersion"
  $toolRoot = Join-Path $ProjectRoot ".tooling"
  $cacheRoot = Join-Path $toolRoot "cache"
  New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null

  $zipPath = Join-Path $cacheRoot "flutter_windows_$FlutterVersion-stable.zip"
  $url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
  if (!(Test-Path $zipPath)) {
    Invoke-WebRequest -Uri $url -OutFile $zipPath
  }

  Expand-Archive -Path $zipPath -DestinationPath $toolRoot -Force
  if (!(Test-Path $localFlutter)) {
    throw "Flutter SDK extraction failed: $localFlutter not found."
  }

  $env:Path = "$(Split-Path -Parent $localFlutter);$env:Path"
  & $localFlutter --version
}

function Invoke-Flutter([string[]]$Arguments) {
  & flutter @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "flutter $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

if (!(Test-IsWindows)) {
  throw "This script must be run on Windows."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Step "Cadillac Packager Windows setup and build"
Write-Host "Project: $projectRoot"

Ensure-Git
Ensure-VsCppTools
Ensure-PythonAndPillow
Ensure-NuGet
Ensure-Flutter -ProjectRoot $projectRoot

Write-Step "Preparing Flutter Windows desktop"
Invoke-Flutter @("config", "--enable-windows-desktop")
Invoke-Flutter @("doctor", "-v")
Invoke-Flutter @("pub", "get")
Invoke-Flutter @("analyze")
if (!$SkipTests) {
  Invoke-Flutter @("test")
}

Write-Step "Building Windows release package"
$releaseArgs = @("-ExecutionPolicy", "Bypass", "-File", ".\scripts\build_windows_release.ps1", "-OutputDir", $OutputDir)
if ($SkipTests) {
  $releaseArgs += "-SkipTests"
}
& powershell @releaseArgs
if ($LASTEXITCODE -ne 0) {
  throw "Windows release build failed."
}

if ($RebootRecommended) {
  Write-Warning "One or more installers requested a reboot. Reboot Windows if the app fails to start or if Flutter reports missing Visual Studio components."
}

Write-Step "Done"
