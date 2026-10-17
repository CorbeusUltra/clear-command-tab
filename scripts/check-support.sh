#!/bin/zsh
# Shared compiler setup for AppKit integration checks and benchmarks.
set -euo pipefail
task_root="${${(%):-%N}:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$task_root/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
compile_appkit_check() {
    local task_output="$1"
    shift
    cd "$task_root"
    swift build -c release --target ClearCommandTabCore
    local task_bin_dir="$(swift build -c release --show-bin-path)"
    local -a task_core_objects
    if [[ -f "$task_bin_dir/ClearCommandTabCore.o" ]]; then
        task_core_objects=("$task_bin_dir/ClearCommandTabCore.o")
    else
        task_core_objects=("$task_bin_dir/ClearCommandTabCore.build/"*.o)
    fi
    mkdir -p "${task_output:h}"
    swiftc -O -swift-version 5 -I "$task_bin_dir" -I "$task_bin_dir/Modules" \
        "${task_core_objects[@]}" "$@" -o "$task_output"
}
