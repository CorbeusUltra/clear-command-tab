#!/bin/zsh
# Headless native tap check: forwards all input, posts none, requests no permission.
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/check-support.sh"
compile_appkit_check "$task_root/.build/KeyboardRecoveryChecks/checks" \
    -D KEYBOARD_RECOVERY_CHECKS "$task_root/Sources/ClearCommandTab/KeyboardTap.swift" \
    "$task_root/Tests/KeyboardRecoveryChecks/main.swift"
task_host="$task_root/.build/KeyboardRecoveryChecks/Host.app"
mkdir -p "$task_host/Contents/MacOS"
cp "$task_root/Resources/Info.plist" "$task_host/Contents/Info.plist"
cp "$task_root/.build/KeyboardRecoveryChecks/checks" "$task_host/Contents/MacOS/ClearCmdTab"
# Same stable identity permits checking existing trust without granting a new app.
# A prohibited activation policy and no windows keep the host invisible.
zsh "$task_root/scripts/sign-app.sh" "$task_host"
python3 "$task_root/scripts/run-live-checks.py" "$task_host" "$task_root/.build/KeyboardRecoveryChecks/report.json"
