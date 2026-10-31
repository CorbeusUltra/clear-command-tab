#!/bin/zsh
# Compile only ClearCommandTab's own Finder/Spotlight icon, for macOS only.
set -euo pipefail
task_root="${0:A:h:h}"
task_output="${CCT_ICON_OUTPUT_DIR:-$task_root/.build/icon-catalog}"
if [[ -n "${CCT_ASSET_DEVELOPER_DIR:-}" ]]; then
    task_developer="$CCT_ASSET_DEVELOPER_DIR"
elif [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/actool ]]; then
    task_developer=/Applications/Xcode.app/Contents/Developer
else
    task_developer="$(/usr/bin/xcode-select -p)"
fi
task_actool="$task_developer/usr/bin/actool"
if [[ ! -x "$task_actool" ]]; then
    print -u2 'Native icon compilation requires existing Xcode asset tools. Set CCT_ASSET_DEVELOPER_DIR to Contents/Developer.'
    exit 1
fi
mkdir -p "$task_output"
DEVELOPER_DIR="$task_developer" "$task_actool" "$task_root/Resources/AppIcon.icon" \
    --compile "$task_output" --platform macosx --target-device mac \
    --minimum-deployment-target 14.0 --app-icon AppIcon --include-all-app-icons \
    --output-partial-info-plist "$task_output/partial-Info.plist"
if [[ ! -s "$task_output/Assets.car" ]]; then
    print -u2 'actool produced no native icon catalog; stop before signing/installing.'
    exit 1
fi
print "Compiled native macOS icon: $task_output/Assets.car"
