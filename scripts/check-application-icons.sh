#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/build-config.sh"
mkdir -p "$task_root/.build/ApplicationIconChecks"
swiftc -O "$task_root/Sources/ClearCommandTab/ApplicationIcon.swift" \
    "$task_root/Tests/ApplicationIconChecks/main.swift" \
    -o "$task_root/.build/ApplicationIconChecks/checks"
"$task_root/.build/ApplicationIconChecks/checks" "$@"
