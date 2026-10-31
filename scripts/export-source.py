#!/usr/bin/env python3
"""Create a curated, history-free source folder; never alter the local checkout."""
from pathlib import Path
import hashlib
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
FILES = ('LICENSE', 'Package.swift', 'README.md', 'CHANGELOG.md', 'VALIDATION.md',
         'THIRD_PARTY_NOTICES.md', '.gitignore', 'config/build.env.example')
TREES = ('Sources', 'Resources', 'Tests', 'scripts', 'docs', 'Design/SelectedLogo')
EXCLUDED = {'scripts/make-logo-proposals.swift'}


def source_plan():
    candidates = [ROOT / name for name in FILES]
    for name in TREES:
        candidates.extend(path for path in (ROOT / name).rglob('*') if path.is_file())
    selected = []
    for source in sorted(candidates):
        relative = source.relative_to(ROOT)
        if (relative.as_posix() in EXCLUDED or '__pycache__' in relative.parts
                or source.name == '.DS_Store' or source.suffix == '.pyc'):
            continue
        if source.is_symlink() or not source.resolve().is_relative_to(ROOT):
            raise SystemExit(f'Refusing a symlink or external source: {relative}')
        selected.append((source, relative))
    # Validate inputs before creating the destination. Absolute personal paths,
    # private keys, and the local signing identity must never enter this export.
    forbidden = (b'/' + b'Users/', b'/' + b'opt/homebrew/', b'PRIVATE' + b' KEY-----')
    for source, relative in selected:
        if source.suffix.lower() in {'.png', '.icns'}:
            continue
        if any(marker in source.read_bytes() for marker in forbidden):
            raise SystemExit(f'Personal path or key marker requires review: {relative}')
    return selected


def export(destination: Path) -> None:
    destination = destination.expanduser().absolute()
    if destination.exists() or destination.is_symlink():
        raise SystemExit('Destination already exists; choose a new folder.')
    selected = source_plan()
    destination.mkdir(parents=True)
    manifest = []
    for source, relative in selected:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        manifest.append(f'{hashlib.sha256(target.read_bytes()).hexdigest()}  {relative.as_posix()}')
    (destination / 'SOURCE-MANIFEST.sha256').write_text('\n'.join(manifest) + '\n')
    print(f'Prepared {len(selected)} files: {destination}')
    print('Project licence and third-party notices included; no Git history or personal build settings.')


if __name__ == '__main__':
    if sys.argv[1:] == ['--check']:
        print(f'Validated {len(source_plan())} exportable files; no export created.')
    elif len(sys.argv) == 2 and not sys.argv[1].startswith('--'):
        export(Path(sys.argv[1]))
    else:
        raise SystemExit('Usage: python3 scripts/export-source.py NEW_DESTINATION | --check')
