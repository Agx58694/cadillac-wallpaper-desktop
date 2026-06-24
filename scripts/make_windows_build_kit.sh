#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ZIP_PATH="dist/CadillacPackager-windows-build-kit.zip"
mkdir -p dist
rm -f "$ZIP_PATH"

required_files=(
  "packager/tools/windows/astcenc.exe"
  "scripts/build_windows_release.ps1"
  "scripts/setup_and_build_windows.ps1"
  "build_windows_one_click.cmd"
  "WINDOWS_BUILD_README.txt"
  "pubspec.yaml"
  "windows/CMakeLists.txt"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required file: $file" >&2
    exit 1
  fi
done

zip_excludes=(
  '*/.DS_Store'
  '*/__pycache__/*'
  'windows/flutter/ephemeral/*'
)

if [[ "${CADILLAC_INCLUDE_PRIVATE_TEMPLATE:-0}" != "1" ]]; then
  zip_excludes+=('packager/templates/*.zip')
fi

zip -q -r "$ZIP_PATH" \
  analysis_options.yaml \
  build_windows_one_click.cmd \
  WINDOWS_BUILD_README.txt \
  pubspec.yaml \
  pubspec.lock \
  assets \
  lib \
  packager \
  scripts \
  test \
  windows \
  -x "${zip_excludes[@]}"

if unzip -p "$ZIP_PATH" \
  '*.dart' '*.yaml' '*.yml' '*.ps1' '*.py' '*.txt' '*.md' '*.cmake' '*.cpp' '*.h' '*.rc' '*.manifest' \
  2>/dev/null | rg -n '/Users/[A-Za-z0-9._-]+|C:\\Users\\(?!username)[A-Za-z0-9._-]+' --pcre2; then
  echo "Refusing to emit package: local user path found in archive text files." >&2
  exit 1
fi

ls -lh "$ZIP_PATH"
echo "Windows build kit ready: $ZIP_PATH"
