#!/bin/zsh
# Noninteractive checks. --all includes lifecycle/queue checks and native icon
# compilation; --render additionally writes hidden AppKit preview images.
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
export CLANG_MODULE_CACHE_PATH="$task_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
task_render=false
task_all=false
for task_argument in "$@"; do
    case "$task_argument" in
        --render) task_render=true ;;
        --all) task_all=true ;;
        *) print -u2 'Usage: check.sh [--all] [--render]'; exit 2 ;;
    esac
done
python3 "$task_root/Tests/InstallerChecks/main.py"
swift build -c release --product ClearCommandTab
swift run -c release ClearCommandTabChecks
zsh "$task_root/scripts/check-application-icons.sh"
if [[ "$task_render" == true ]]; then
    zsh "$task_root/scripts/check-settings-layout.sh" --render-dir="$task_root/.build/SettingsPreviews"
else
    zsh "$task_root/scripts/check-settings-layout.sh"
fi
if [[ "$task_all" == true ]]; then
    zsh "$task_root/scripts/check-application-lifecycle.sh"
    zsh "$task_root/scripts/check-icon-catalog.sh"
    python3 "$task_root/scripts/export-source.py" --check
fi
