#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
swift build -c release --product ClearCommandTab
task_binary_dir="$(swift build -c release --show-bin-path)"
task_bundle="$task_root/.build/ClearCommandTab.app"
mkdir -p "$task_bundle/Contents/MacOS" "$task_bundle/Contents/Resources"
cp "$task_binary_dir/ClearCommandTab" "$task_bundle/Contents/MacOS/ClearCommandTab"
cp "$task_root/Resources/Info.plist" "$task_bundle/Contents/Info.plist"
swift "$task_root/scripts/make-icon.swift" "$task_bundle/Contents/Resources/ClearCommandTab.icns"
zsh "$task_root/scripts/sign-app.sh" "$task_bundle"
print "$task_bundle"
