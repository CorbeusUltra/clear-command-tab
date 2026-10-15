#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
swift build --product ClearCommandTabFixture
task_binary_dir="$(swift build --show-bin-path)"
for task_suffix in A B; do
    task_name="ClearCommandTab Test $task_suffix"
    task_bundle="$task_root/.build/Fixtures/$task_name.app"
    mkdir -p "$task_bundle/Contents/MacOS"
    cp "$task_binary_dir/ClearCommandTabFixture" "$task_bundle/Contents/MacOS/ClearCommandTabFixture"
    cat > "$task_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.lucas.VisibleTab.Test$task_suffix</string>
<key>CFBundleName</key><string>$task_name</string>
<key>CFBundleExecutable</key><string>ClearCommandTabFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
    codesign --force --sign - "$task_bundle"
    print "$task_bundle"
done
