"""Black-box installer scenarios; real script, isolated paths, mocked OS probes.

No source rewriting, real signing key, or user installation is accessed.
The replacement scenario moves only a newly created fixture app to macOS Trash.
"""
from pathlib import Path
import os
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".build" / "InstallerChecks" / uuid.uuid4().hex


def executable(path, content):
    path.write_text("#!/bin/zsh\nset -eu\n" + content)
    path.chmod(0o755)


def run_case(name, args=("--no-build",), *, prepared=True, invalid=False, process=1, old=False,
             copy_fails=False, stage_invalid=False, same_source=False):
    directory = SCRATCH / name
    commands = directory / "bin"
    commands.mkdir(parents=True)
    destination = directory / "Applications/ClearCommandTab.app"
    bundle = directory / "prepared/ClearCommandTab.app"
    if same_source:
        bundle = destination
    trace = directory / "trace.txt"
    if prepared:
        bundle.mkdir(parents=True)
        (bundle / "new.txt").write_text("prepared application")
    if old:
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "old.txt").write_text("original installation")
    executable(commands / "zsh", '''[[ "$1" == */scripts/build-app.sh ]] || exit 99
print build >> "$CHECK_TRACE"
mkdir -p "$CCT_BUNDLE_PATH"
print -n 'prepared application' > "$CCT_BUNDLE_PATH/new.txt"
''')
    executable(commands / "pgrep", 'exit "$CHECK_PROCESS_RESULT"\n')
    executable(commands / "codesign", '''[[ "$1" == "--verify" && "$2" == "--strict" ]] || exit 99
print verify >> "$CHECK_TRACE"
if [[ "$CHECK_STAGE_INVALID" == 1 && "$3" == */.ClearCommandTab-install-* ]]; then exit 1; fi
exit "$CHECK_VERIFY_RESULT"
''')
    executable(commands / "ditto", '''[[ "$CHECK_COPY_FAILS" == 0 ]] || exit 1
/bin/cp -R "$1" "$2"
''')
    environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                       CCT_INSTALL_DIR=str(destination.parent), CCT_BUNDLE_PATH=str(bundle),
                       CHECK_TRACE=str(trace), CHECK_PROCESS_RESULT=str(process),
                       CHECK_VERIFY_RESULT="1" if invalid else "0", CHECK_COPY_FAILS="1" if copy_fails else "0",
                       CHECK_STAGE_INVALID="1" if stage_invalid else "0")
    result = subprocess.run(["/bin/zsh", str(ROOT / "scripts/install-app.sh"), *args],
                            env=environment, text=True, capture_output=True)
    calls = trace.read_text().splitlines() if trace.exists() else []
    return result, calls, destination


result, calls, destination = run_case("prepared")
assert result.returncode == 0, result.stderr
assert "build" not in calls and (destination / "new.txt").read_text() == "prepared application"
print("PASS prepared signed app installs without rebuilding or requesting a signing key")

result, calls, destination = run_case("standalone", (), prepared=False)
assert result.returncode == 0 and calls.count("build") == 1, result.stderr
assert (destination / "new.txt").read_text() == "prepared application"
print("PASS standalone invocation builds once and installs the result")

for name, options in [
    ("missing", dict(prepared=False)), ("invalid", dict(invalid=True)),
    ("running", dict(process=0)), ("process-probe-failure", dict(process=2)),
    ("copy-failure", dict(copy_fails=True)),
    ("staging-signature-failure", dict(stage_invalid=True)),
]:
    result, calls, destination = run_case(name, old=True, **options)
    assert result.returncode != 0, name
    assert (destination / "old.txt").read_text() == "original installation", name
    assert not (destination / "new.txt").exists(), name
    print(f"PASS {name} preserves the previous installation")

for name, args in [("unknown", ("--unknown",)), ("extra", ("--no-build", "extra"))]:
    result, calls, destination = run_case(name, args)
    assert result.returncode == 2 and not calls and not destination.exists(), name
print("PASS invalid arguments cannot build or install")

result, calls, destination = run_case("same-source", old=True, same_source=True)
assert result.returncode != 0 and (destination / "old.txt").read_text() == "original installation"
print("PASS source matching destination is refused before replacement")

if Path('/usr/bin/trash').exists():
    result, calls, destination = run_case("replacement", old=True)
    assert result.returncode == 0, result.stderr
    assert (destination / "new.txt").exists() and not (destination / "old.txt").exists()
    print("PASS validated replacement moves the old fixture to macOS Trash")
else:
    print("SKIP replacement: /usr/bin/trash unavailable; fresh-install/failure scenarios still ran")
print("Installer checks completed; no user application or keychain was accessed")
