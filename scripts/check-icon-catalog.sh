#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
zsh "$task_root/scripts/compile-icon.sh"
python3 "$task_root/Tests/IconCatalogChecks/main.py" "$@"
