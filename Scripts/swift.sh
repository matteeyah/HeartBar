#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/ModuleCache"
subcommand="${1:?Usage: Scripts/swift.sh build|test [options]}"
shift
extra_args=()
developer_dir="$(xcode-select -p)"
# Some Command Line Tools releases ship Testing but omit its macro search path.
testing_plugins="$developer_dir/usr/lib/swift/host/plugins/testing"
if [[ "$subcommand" == "test" && "$developer_dir" == */CommandLineTools && -d "$testing_plugins" ]]; then
    testing_frameworks="$developer_dir/Library/Developer/Frameworks"
    extra_args=(--build-system native --disable-xctest
                -Xswiftc -plugin-path -Xswiftc "$testing_plugins"
                -Xswiftc -F -Xswiftc "$testing_frameworks"
                -Xlinker -F -Xlinker "$testing_frameworks"
                -Xlinker -rpath -Xlinker "$testing_frameworks")
fi
exec swift "$subcommand" --cache-path .build/cache --config-path .build/config --security-path .build/security ${extra_args[@]+"${extra_args[@]}"} "$@"
