#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/build-config.sh"
task_bundle="${1:?Pass the bundle or executable to sign.}"
# Fresh checkouts explicitly use ad hoc development signing. A configured
# certificate is mandatory once selected: a failure never falls back to ad hoc.
task_identity="${CCT_SIGNING_IDENTITY:-${VISIBLETAB_SIGNING_IDENTITY:--}}"
if [[ "$task_identity" == "-" ]]; then
    print -u2 'Signing ad hoc for local development; use a stable certificate to retain Accessibility across updates.'
fi
task_info="$task_root/Resources/Info.plist"
if [[ -f "$task_bundle/Contents/Info.plist" ]]; then
    task_info="$task_bundle/Contents/Info.plist"
fi
task_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_info")"
codesign --force --sign "$task_identity" --identifier "$task_identifier" --timestamp=none "$task_bundle"
codesign --verify --strict "$task_bundle"
