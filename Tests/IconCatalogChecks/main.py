"""Check only ClearCommandTab's own native icon catalog; never inspect third-party UI."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
catalog = root / '.build/icon-catalog/Assets.car'
manifest = json.loads((root / 'Resources/AppIcon.icon/icon.json').read_text())
checks = 0


def check(value, description):
    global checks
    checks += 1
    print(f'{"PASS" if value else "FAIL"} {description}')
    if not value:
        raise SystemExit(1)


def specializations(items):
    return {item.get('appearance', 'light'): item['value']['solid'] for item in items}


check(manifest['supported-platforms'] == {'squares': ['macOS']}, 'icon source targets macOS only')
check(specializations(manifest['fill-specializations']) == {
    'light': 'srgb:0.97000,0.97000,0.97000,1.00000',
    'dark': 'srgb:0.12000,0.12000,0.12000,1.00000',
}, 'native backgrounds match ScreenshotOCR light gray and charcoal palettes')
group = manifest['groups'][0]
check(len(manifest['groups']) == 1 and len(group['layers']) == 1, 'one original two-arrow layer, no added artwork')
check(specializations(group['layers'][0]['fill-specializations']) == {
    'light': 'srgb:0.00000,0.00000,0.00000,1.00000',
    'dark': 'srgb:1.00000,1.00000,1.00000,1.00000',
}, 'native arrows preserve current black and white palettes')
check(not group['layers'][0]['glass'] and not group['specular'] and not group['translucency']['enabled'],
      'native logo adds no glass, specular or translucency treatment')
scratch = root / '.build/IconCatalogChecks'
scratch.mkdir(parents=True, exist_ok=True)
generated = scratch / 'original-arrows.png'
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(root / '.build/ModuleCache'))
subprocess.run(['swift', str(root / 'scripts/make-icon.swift'), '--native-glyph', str(generated)], env=env, check=True)
glyph = root / 'Resources/AppIcon.icon/Assets/Arrows.png'
check(hashlib.sha256(glyph.read_bytes()).digest() == hashlib.sha256(generated.read_bytes()).digest(),
      'native glyph is byte-identical to the existing production arrow paths')
records = json.loads(subprocess.check_output(['/usr/bin/assetutil', '--info', str(catalog)]))
appearances = {r.get('Appearance') for r in records if r.get('AssetType') == 'IconImageStack' and r.get('Name') == 'AppIcon'}
check({'NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'} <= appearances,
      'compiled Assets.car contains real native light and dark icon stacks')
check(any(r.get('Name') == 'AppIcon_Assets/Arrows' for r in records), 'catalog includes the actual original glyph image')
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
check(info['CFBundleIconName'] == 'AppIcon' and info['CFBundleIconFile'] == 'ClearCommandTab.icns',
      'bundle metadata selects native variants while retaining legacy ICNS fallback')
if len(sys.argv) == 2:
    bundle = Path(sys.argv[1])
    packaged = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    resources = bundle / 'Contents/Resources'
    check(packaged['CFBundleIconName'] == 'AppIcon' and (resources / 'Assets.car').is_file(),
          'prepared app actually packages and declares the native icon catalog')
    for name in ['ClearCommandTab.icns', 'ClearCommandTab-dark.icns', 'ClearCommandTab-menu.png']:
        check((resources / name).is_file(), f'explicit About/menu artwork remains packaged: {name}')
print(f'{checks} native logo checks, zero failures; no Finder/Spotlight window was opened')
