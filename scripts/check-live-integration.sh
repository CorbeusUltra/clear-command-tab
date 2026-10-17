#!/bin/zsh
# Opt in explicitly: shows short-lived fixture windows and switches their focus.
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/check-support.sh"
zsh "$task_root/scripts/build-fixtures.sh"
compile_appkit_check "$task_root/.build/LiveIntegrationChecks/checks" \
    "$task_root/Sources/ClearCommandTab/WindowTracker.swift" \
    "$task_root/Sources/ClearCommandTab/FocusCoordinator.swift" \
    "$task_root/Tests/LiveIntegrationChecks/main.swift"
# A distinct identity keeps test authorization separate from the user's app.
task_host="$task_root/.build/LiveIntegrationChecks/Host.app"
mkdir -p "$task_host/Contents/MacOS"
cp "$task_root/Resources/Info.plist" "$task_host/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.clearcommandtab.IntegrationChecks' "$task_host/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName ClearCommandTab Integration Checks' "$task_host/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName ClearCommandTab Integration Checks' "$task_host/Contents/Info.plist"
cp "$task_root/.build/LiveIntegrationChecks/checks" "$task_host/Contents/MacOS/ClearCommandTab"
zsh "$task_root/scripts/sign-app.sh" "$task_host"
if [[ "${CCT_LIVE_PREPARE_ONLY:-0}" == 1 ]]; then
    print "Prepared: $task_host"
    exit 0
fi
python3 "$task_root/scripts/run-live-checks.py" "$task_host" "${1:-$task_root/.build/LiveIntegrationChecks/report.json}"
