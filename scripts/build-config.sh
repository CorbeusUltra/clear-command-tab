#!/bin/zsh
# Public defaults work in a fresh checkout; personal values stay in an ignored file.
task_root="${${(%):-%N}:A:h:h}"
if [[ -f "$task_root/.local/build.env" ]]; then
    source "$task_root/.local/build.env"
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$task_root/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
