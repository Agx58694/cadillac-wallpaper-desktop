#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 APP_PATH RUNTIME_ARTIFACT_DIRECTORY OUTPUT_ZIP" >&2
  exit 2
fi

app_path="$1"
artifact_dir="$2"
output_zip="$3"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="$app_path/Contents/MacOS/packager_runtime"
asset_dir="$app_path/Contents/Frameworks/App.framework/Resources/flutter_assets/packager"
mkdir -p "$runtime_dir"

for arch in x86_64 arm64; do
  archive="$artifact_dir/cadillac_wallpaper_packager_$arch.tar.gz"
  test -f "$archive"
  tar -C "$runtime_dir" -xzf "$archive"
  chmod +x "$runtime_dir/cadillac_wallpaper_packager_$arch"
done

xcrun clang -arch x86_64 -arch arm64 -mmacosx-version-min=12.0 \
  -o "$runtime_dir/cadillac_wallpaper_packager" \
  "$root_dir/scripts/macos_packager_launcher.c"

check_archs() {
  local path="$1"
  shift
  test -f "$path"
  local archs
  archs="$(lipo -archs "$path")"
  for expected_arch in "$@"; do
    if [[ " $archs " != *" $expected_arch "* ]]; then
      echo "Missing $expected_arch architecture in $path: $archs" >&2
      exit 1
    fi
  done
  echo "$path: $archs"
}

main_binary="$app_path/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")"
check_archs "$main_binary" x86_64 arm64
check_archs "$runtime_dir/cadillac_wallpaper_packager" x86_64 arm64
check_archs "$runtime_dir/cadillac_wallpaper_packager_x86_64" x86_64
check_archs "$runtime_dir/cadillac_wallpaper_packager_arm64" arm64
check_archs "$asset_dir/tools/macos/astcenc" x86_64 arm64
for arch in x86_64 arm64; do
  for license_file in Python-LICENSE.txt Pillow-LICENSE.txt PyInstaller-COPYING.txt RUNTIME-NOTICE.txt; do
    test -s "$runtime_dir/third_party_licenses_$arch/$license_file"
  done
done
test -f "$asset_dir/templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip"
test -f "$asset_dir/cadillac_wallpaper_packager.py"

# The current host runs its own slice. Each runtime job also invokes --help on
# its native host, so both embedded Python/Pillow builds are exercised.
"$runtime_dir/cadillac_wallpaper_packager" --help >/dev/null
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"

mkdir -p "$(dirname "$output_zip")"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"
shasum -a 256 "$output_zip"
