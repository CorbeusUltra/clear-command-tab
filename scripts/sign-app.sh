#!/bin/zsh
set -euo pipefail
task_bundle="${1:?Pass the bundle or executable to sign.}"
# Existing local Apple Development identity. Pin it rather than silently switching
# to ad hoc signing: that would invalidate the application's Accessibility grant.
task_identity="${VISIBLETAB_SIGNING_IDENTITY:-A96AD6D636DAA554A4C8DCAA4B7E5686051E7334}"
if [[ "$task_identity" == "-" ]]; then
    print -u2 'VisibleTab updates require a stable certificate; ad hoc signing is disabled.'
    exit 1
fi
codesign --force --sign "$task_identity" --identifier local.lucas.VisibleTab --timestamp=none "$task_bundle"
codesign --verify --strict "$task_bundle"
