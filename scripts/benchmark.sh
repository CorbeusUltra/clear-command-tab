#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/check-support.sh"
compile_appkit_check "$task_root/.build/PerformanceChecks/checks" \
    "$task_root/Sources/ClearCommandTab/GlassProfile.swift" \
    "$task_root/Sources/ClearCommandTab/ApplicationIcon.swift" \
    "$task_root/Sources/ClearCommandTab/SwitcherPanel.swift" \
    "$task_root/Tests/PerformanceChecks/main.swift"
"$task_root/.build/PerformanceChecks/checks" "$@"
