#!/usr/bin/env python3
"""Export the source without repository metadata or generated app bundles."""
from pathlib import Path
import argparse
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def export_source(output):
    output = Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise ValueError('Choose a new output directory; existing directories are never replaced.')
    if output == ROOT or ROOT in output.parents:
        raise ValueError('Export outside the source checkout.')
    names = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT
    ).decode().split('\0')
    files = []
    for name in sorted(set(filter(None, names))):
        path = Path(name)
        if path.is_absolute() or '..' in path.parts:
            raise ValueError(f'Unsafe source path: {name}')
        if any(part in ('.git', '.build', 'build', '__pycache__', 'xcuserdata')
               or part.endswith('.app') for part in path.parts):
            continue
        source = ROOT / path
        if source.is_symlink() or any(parent.is_symlink() for parent in source.parents if parent != ROOT):
            raise ValueError(f'Symbolic links are not exported: {name}')
        if source.is_file():
            files.append((source, path))
    if not files:
        raise ValueError('No source files found.')
    output.mkdir(parents=True)
    for source, path in files:
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    print(f'Exported {len(files)} files to {output}.')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    export_source(parser.parse_args().output)
