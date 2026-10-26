#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
architecture_args=()
if [[ "${1:-}" == "--universal" ]]; then
    architecture_args=(--arch arm64 --arch x86_64)
    shift
fi
"$project_dir/Scripts/swift.sh" build -c release ${architecture_args[@]+"${architecture_args[@]}"} "$@"
bin_dir="$("$project_dir/Scripts/swift.sh" build -c release ${architecture_args[@]+"${architecture_args[@]}"} --show-bin-path "$@")"
app_dir="$project_dir/build/HeartBar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/HeartBar" "$app_dir/Contents/MacOS/HeartBar"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
