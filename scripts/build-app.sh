#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/build-config.sh"
cd "$task_root"
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
task_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
task_minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$task_root/Resources/Info.plist")"
# Keep the SDK distinct from the deployment target. Some Swift Build versions
# stamp both as the minimum OS, enabling legacy AppKit appearance at runtime.
swift build -c release --product ClearCommandTab --sdk "$task_sdk" \
    -Xlinker -platform_version -Xlinker macos \
    -Xlinker "$task_minimum_os" -Xlinker "$task_sdk_version"
task_binary_dir="$(swift build -c release --show-bin-path)"
# Check the actual linked artifact before packaging/signing, including every
# architecture if a universal executable is produced.
xcrun vtool -show-build "$task_binary_dir/ClearCommandTab" | awk \
    -v sdk="$task_sdk_version" -v minimum="$task_minimum_os" '
    function version(value, parts) {
        split(value, parts, ".")
        return sprintf("%d.%d.%d", parts[1], parts[2], parts[3])
    }
    $1 == "sdk" { sdks++; if (version($2) != version(sdk)) invalid = 1 }
    $1 == "minos" { minimums++; if (version($2) != version(minimum)) invalid = 1 }
    END {
        if (!sdks || sdks != minimums || invalid) {
            print "Incorrect executable SDK/deployment metadata; build stopped." > "/dev/stderr"
            exit 1
        }
    }'
task_bundle="${CCT_BUNDLE_PATH:-$task_root/.build/ClearCmdTab.app}"
mkdir -p "$task_bundle/Contents/MacOS" "$task_bundle/Contents/Resources"
cp "$task_binary_dir/ClearCommandTab" "$task_bundle/Contents/MacOS/ClearCmdTab"
cp "$task_root/Resources/Info.plist" "$task_bundle/Contents/Info.plist"
swift "$task_root/scripts/make-icon.swift" "$task_bundle/Contents/Resources/ClearCommandTab.icns"
swift "$task_root/scripts/make-icon.swift" --dark "$task_bundle/Contents/Resources/ClearCommandTab-dark.icns"
swift "$task_root/scripts/make-icon.swift" --menu "$task_bundle/Contents/Resources/ClearCommandTab-menu.png"
zsh "$task_root/scripts/compile-icon.sh"
cp "${CCT_ICON_OUTPUT_DIR:-$task_root/.build/icon-catalog}/Assets.car" "$task_bundle/Contents/Resources/Assets.car"
zsh "$task_root/scripts/sign-app.sh" "$task_bundle"
print "$task_bundle"
