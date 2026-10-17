#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/build-config.sh"
task_bundle="${CCT_BUNDLE_PATH:-$task_root/.build/ClearCommandTab.app}"
task_install_dir="${CCT_INSTALL_DIR:-$HOME/Applications}"
task_destination="$task_install_dir/ClearCommandTab.app"
task_build=true
if (( $# > 1 )); then
    print -u2 'Usage: install-app.sh [--no-build]'
    exit 2
fi
if (( $# == 1 )); then
    if [[ "$1" != "--no-build" ]]; then
        print -u2 'Usage: install-app.sh [--no-build]'
        exit 2
    fi
    task_build=false
fi
for task_process in ClearCommandTab VisibleTab; do
    if pgrep -x "$task_process" >/dev/null; then
        print -u2 'Quit ClearCommandTab before installing a new build.'
        exit 1
    else
        task_process_status=$?
        if (( task_process_status != 1 )); then
            print -u2 'Cannot check running applications; installation stopped.'
            exit 1
        fi
    fi
done
if [[ "$task_build" == true ]]; then
    zsh "$task_root/scripts/build-app.sh"
fi
if [[ ! -d "$task_bundle" ]]; then
    print -u2 'No prepared app bundle. Run zsh scripts/build-app.sh first.'
    exit 1
fi
# Verification uses public signature data; it does not request the private key.
# Reject a missing/invalid build before moving either installed app to Trash.
codesign --verify --strict "$task_bundle"
if [[ "${task_bundle:A}" == "${task_destination:A}" ]]; then
    print -u2 'Prepared and installed bundle paths must differ.'
    exit 1
fi
mkdir -p "$task_install_dir"
# Validate a complete copy before touching an existing installation. A failed
# copy/signature leaves the old app in place and the staging path for inspection.
task_stage="$task_install_dir/.ClearCommandTab-install-$$-$RANDOM.app"
ditto "$task_bundle" "$task_stage"
codesign --verify --strict "$task_stage"
task_legacy_destination="$task_install_dir/VisibleTab.app"
if [[ ( -e "$task_legacy_destination" || -e "$task_destination" ) && ! -x /usr/bin/trash ]]; then
    print -u2 'This installer requires /usr/bin/trash for safe replacement. Move the old app to Trash in Finder first.'
    exit 1
fi
if [[ -e "$task_legacy_destination" ]]; then
    /usr/bin/trash -s "$task_legacy_destination"
fi
if [[ -e "$task_destination" ]]; then
    /usr/bin/trash -s "$task_destination"
fi
mv "$task_stage" "$task_destination"
codesign --verify --strict "$task_destination"
print "Installed: $task_destination"
