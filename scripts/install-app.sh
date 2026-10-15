#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
task_destination="/Users/lucas/Applications/VisibleTab.app"
if pgrep -x VisibleTab >/dev/null; then
    print -u2 'Quit VisibleTab before installing a new build.'
    exit 1
fi
zsh "$task_root/scripts/build-app.sh"
if [[ -e "$task_destination" ]]; then
    /usr/bin/trash -s "$task_destination"
fi
mkdir -p "${task_destination:h}"
ditto "$task_root/.build/VisibleTab.app" "$task_destination"
codesign --verify --strict "$task_destination"
print "Installed: $task_destination"
