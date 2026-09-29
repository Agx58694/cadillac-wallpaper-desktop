#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != "arm64" && "$1" != "x86_64" ) ]]; then
  echo "usage: $0 arm64|x86_64 OUTPUT_DIRECTORY" >&2
  exit 2
fi

arch="$1"
output_dir="$2"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

python_command="${CADILLAC_BUILD_PYTHON:-python3}"
actual_arch="$("$python_command" -c 'import platform; print(platform.machine())')"
if [[ "$actual_arch" != "$arch" ]]; then
  echo "Python is $actual_arch, expected $arch" >&2
  exit 1
fi

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
work_dir="$root_dir/build/pyinstaller-macos-$arch"
runtime_name="cadillac_wallpaper_packager_$arch"
hidden_imports=()
for module_file in "$root_dir"/packager/*.py; do
  module_name="$(basename "$module_file" .py)"
  if [[ "$module_name" != "cadillac_wallpaper_packager" && "$module_name" != "__init__" ]]; then
    hidden_imports+=(--hidden-import "$module_name")
  fi
done

"$python_command" -m PyInstaller \
  --noconfirm --clean --onefile --target-arch "$arch" \
  --name "$runtime_name" \
  --distpath "$output_dir" \
  --workpath "$work_dir" \
  --specpath "$work_dir" \
  --paths "$root_dir/packager" \
  "${hidden_imports[@]}" \
  "$root_dir/packager/cadillac_wallpaper_packager.py"

runtime_path="$output_dir/$runtime_name"
test -x "$runtime_path"
runtime_archs="$(lipo -archs "$runtime_path")"
if [[ "$runtime_archs" != "$arch" ]]; then
  echo "Runtime architecture mismatch: $runtime_archs (expected $arch)" >&2
  exit 1
fi
"$runtime_path" --help >/dev/null
# --help exits before loading Pillow and the KZB modules. A deliberately
# missing template reaches the first input boundary only after all imports.
probe_path="$output_dir/runtime-probe-missing-template.zip"
if probe_output="$("$runtime_path" \
  --light-image "$output_dir/runtime-probe-light.png" \
  --dark-image "$output_dir/runtime-probe-dark.png" \
  --input-zip "$probe_path" \
  --output-zip "$output_dir/runtime-probe-unused.zip" \
  --source-mode native 2>&1)"; then
  echo "Runtime probe unexpectedly succeeded" >&2
  exit 1
fi
if [[ "$probe_output" != *"runtime-probe-missing-template.zip"* ]]; then
  echo "Runtime probe failed before reaching the missing-template boundary" >&2
  echo "$probe_output" >&2
  exit 1
fi
licenses_name="third_party_licenses_$arch"
"$python_command" "$root_dir/scripts/copy_packager_runtime_licenses.py" \
  "$output_dir/$licenses_name"
tar -C "$output_dir" -czf "$output_dir/$runtime_name.tar.gz" \
  "$runtime_name" "$licenses_name"
shasum -a 256 "$output_dir/$runtime_name.tar.gz"
