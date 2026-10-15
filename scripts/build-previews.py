#!/usr/bin/env python3
"""Create isolated, keyboard-free visual QA apps from the release bundle."""
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parent.parent
source = root / ".build/VisibleTab.app"
destination = root / ".build/GlassPreviews"
if not source.exists():
    raise SystemExit("Run zsh scripts/build-app.sh first.")
if destination.exists():
    subprocess.run(["/usr/bin/trash", "-s", str(destination)], check=True)

for count, appearance in [(1, "light"), (3, "light"), (18, "light"), (50, "light"), (3, "dark")]:
    name = f"VisibleTab Preview {count} {appearance}"
    bundle = destination / f"{name}.app"
    subprocess.run(["ditto", str(source), str(bundle)], check=True)
    plist_path = bundle / "Contents/Info.plist"
    info = plistlib.loads(plist_path.read_bytes())
    info.update(CFBundleIdentifier=f"local.lucas.VisibleTab.Preview{count}.{appearance}",
                CFBundleName=name, CFBundleDisplayName=name, CFBundleExecutable="PreviewLauncher")
    plist_path.write_bytes(plistlib.dumps(info))
    launcher = bundle / "Contents/MacOS/PreviewLauncher"
    launcher.write_text(f'#!/bin/zsh\nexec "${{0:A:h}}/VisibleTab" --preview --preview-count={count} --preview-{appearance}\n')
    launcher.chmod(0o755)
    subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)
    print(bundle)
