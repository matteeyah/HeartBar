#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/preview-runner
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
preview_dir="$project_dir/build/preview-runner"
target="$(uname -m)-apple-macos14.0"
swiftc -swift-version 6 -target "$target" -parse-as-library -emit-library -emit-module \
    -module-name HeartBarCore Sources/HeartBarCore/*.swift \
    -emit-module-path "$preview_dir/HeartBarCore.swiftmodule" -o "$preview_dir/libHeartBarCore.dylib"
swiftc -swift-version 6 -target "$target" -parse-as-library -D HEARTBAR_VERIFY \
    -I "$preview_dir" -L "$preview_dir" -lHeartBarCore -Xlinker -rpath -Xlinker @executable_path \
    Sources/HeartBarApp/*.swift Scripts/VerifyUI.swift -o "$preview_dir/VerifyUI"
"$preview_dir/VerifyUI"
