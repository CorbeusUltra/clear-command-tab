#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/check-support.sh"
compile_appkit_check "$task_root/.build/ApplicationLifecycleChecks/checks" \
    -D YELLOW_BUTTON_CHECKS -D FOCUS_DISPATCH_CHECKS \
    "$task_root/Sources/ClearCommandTab/ApplicationIcon.swift" \
    "$task_root/Sources/ClearCommandTab/ApplicationTracker.swift" \
    "$task_root/Sources/ClearCommandTab/WindowTracker.swift" \
    "$task_root/Sources/ClearCommandTab/FocusCoordinator.swift" \
    "$task_root/Sources/ClearCommandTab/YellowButtonInterceptor.swift" \
    "$task_root/Tests/ApplicationLifecycleChecks/main.swift"
"$task_root/.build/ApplicationLifecycleChecks/checks"
