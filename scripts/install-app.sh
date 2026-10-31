#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
source "$task_root/scripts/build-config.sh"
task_bundle="${CCT_BUNDLE_PATH:-$task_root/.build/ClearCmdTab.app}"
task_install_dir="${CCT_INSTALL_DIR:-$HOME/Applications}"
task_destination="$task_install_dir/ClearCmdTab.app"
task_previous_name="$task_install_dir/ClearCommandTab.app"
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
for task_process in ClearCmdTab ClearCommandTab VisibleTab; do
    if pgrep -x "$task_process" >/dev/null; then
        print -u2 'Quit ClearCmdTab before installing a new build.'
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
if [[ "${task_bundle:A}" == "${task_destination:A}" || "${task_bundle:A}" == "${task_previous_name:A}" ]]; then
    print -u2 'Prepared and installed bundle paths must differ.'
    exit 1
fi
mkdir -p "$task_install_dir"
# Validate a complete copy before touching an existing installation. A failed
# copy/signature leaves the old app in place and the staging path for inspection.
if [[ -e "$task_previous_name" && -e "$task_destination" ]]; then
    print -u2 'Both ClearCommandTab.app and ClearCmdTab.app exist; review them before migrating.'
    exit 1
fi
if [[ -e "$task_previous_name" ]]; then
    # Keep the app's root inode through the one-time rename so existing login
    # bookmarks can follow it, as in ScreenTextOCR's update workflow.
    codesign --verify --strict "$task_previous_name"
    task_old_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_previous_name/Contents/Info.plist")"
    task_new_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_bundle/Contents/Info.plist")"
    [[ "$task_old_id" == "$task_new_id" ]] || { print -u2 'Legacy bundle identity differs; migration stopped.'; exit 1; }
fi
task_stage="$task_install_dir/.ClearCmdTab-install-$$-$RANDOM.app"
ditto "$task_bundle" "$task_stage"
codesign --verify --strict "$task_stage"
task_legacy_destination="$task_install_dir/VisibleTab.app"
if [[ ( -e "$task_legacy_destination" || -e "$task_destination" || -e "$task_previous_name" ) && ! -x /usr/bin/trash ]]; then
    print -u2 'This installer requires /usr/bin/trash for safe replacement. Move the old app to Trash in Finder first.'
    exit 1
fi
if [[ -e "$task_legacy_destination" ]]; then
    /usr/bin/trash -s "$task_legacy_destination"
fi
if [[ -e "$task_previous_name" ]]; then
    task_backup="$task_install_dir/.ClearCmdTab-previous-$$-$RANDOM.app"
    mkdir -p "$task_backup"
    mv "$task_previous_name/Contents" "$task_backup/Contents"
    if ! mv "$task_stage/Contents" "$task_previous_name/Contents" || ! codesign --verify --strict "$task_previous_name"; then
        if [[ -e "$task_previous_name/Contents" ]]; then /usr/bin/trash -s "$task_previous_name/Contents"; fi
        mv "$task_backup/Contents" "$task_previous_name/Contents"
        print -u2 'Migration failed; the original app was restored.'
        exit 1
    fi
    if ! mv "$task_previous_name" "$task_destination"; then
        /usr/bin/trash -s "$task_previous_name/Contents"
        mv "$task_backup/Contents" "$task_previous_name/Contents"
        print -u2 'Rename failed; the original app was restored.'
        exit 1
    fi
    /usr/bin/trash -s "$task_backup"
    /usr/bin/trash -s "$task_stage"
    codesign --verify --strict "$task_destination"
    print "Installed: $task_destination"
    exit 0
fi
if [[ -e "$task_destination" ]]; then
    /usr/bin/trash -s "$task_destination"
fi
mv "$task_stage" "$task_destination"
codesign --verify --strict "$task_destination"
print "Installed: $task_destination"
