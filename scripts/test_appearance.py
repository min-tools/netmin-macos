#!/usr/bin/env python3
"""Keep the app adaptive and backed by macOS semantic appearance colors."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sources = '\n'.join(path.read_text(encoding='utf-8') for path in (ROOT / 'Sources/NetminApp').glob('*.swift'))
theme = (ROOT / 'Sources/NetminApp/Theme.swift').read_text(encoding='utf-8')
banner = (ROOT / 'Sources/NetminApp/AccessBanner.swift').read_text(encoding='utf-8')

for forbidden in ('.preferredColorScheme(.dark)', 'NSAppearance(named: .darkAqua)', 'window.appearance ='):
    if forbidden in sources:
        print(f'FAIL: forced appearance remains: {forbidden}')
        sys.exit(1)

required = (
    '.windowBackgroundColor', '.controlBackgroundColor', '.textBackgroundColor',
    '.labelColor', '.secondaryLabelColor', '.tertiaryLabelColor',
    '.separatorColor', '.controlAccentColor', '.alternateSelectedControlTextColor',
)
missing = [token for token in required if token not in theme]
if missing:
    print('FAIL: missing semantic theme tokens: ' + ', '.join(missing))
    sys.exit(1)

if 'Color(hex:' in theme:
    print('FAIL: Theme.swift still contains a fixed RGB palette')
    sys.exit(1)

if '.background(.regularMaterial)' not in sources:
    print('FAIL: sidebar no longer uses native material')
    sys.exit(1)

if 'Color(nsColor: .systemOrange).opacity(0.16)' not in banner:
    print('FAIL: the restricted-access banner no longer uses the semantic amber tint')
    sys.exit(1)
if banner.count('.buttonStyle(.bordered)') < 2:
    print('FAIL: purchase and restore must use the same subdued native style')
    sys.exit(1)

print('Adaptive light/dark appearance and semantic macOS colors verified.')
