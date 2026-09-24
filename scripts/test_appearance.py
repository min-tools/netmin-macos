#!/usr/bin/env python3
"""Keep the app adaptive with semantic text and explicit Light/Dark brand surfaces."""

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

adaptive_tokens = (
    'NSColor(name: nil)', '.accessibilityHighContrastDarkAqua',
    'static let sidebarBackground = adaptive(', 'static let badgeActiveBackground = adaptive(',
    'static let segmentSelected = adaptive(', 'static let labelText = adaptive(',
    'static let inputBackground = adaptive(', 'static let inputBorder = adaptive(',
    'static let inputPlaceholderNSColor = adaptiveNSColor(',
)
missing = [token for token in adaptive_tokens if token not in theme]
if missing:
    print('FAIL: missing adaptive palette tokens: ' + ', '.join(missing))
    sys.exit(1)

if '.background(Theme.sidebarBackground)' not in sources:
    print('FAIL: sidebar does not use its adaptive background')
    sys.exit(1)

standard_titlebar = (
    '.windowStyle(.titleBar)',
    'window.styleMask.remove(.fullSizeContentView)',
    'window.titleVisibility = .visible',
    'window.titlebarAppearsTransparent = false',
    'window.titlebarSeparatorStyle = .line',
)
missing = [token for token in standard_titlebar if token not in sources]
if missing:
    print('FAIL: main window no longer uses the standard title bar: ' + ', '.join(missing))
    sys.exit(1)

if 'Color(nsColor: .systemOrange).opacity(0.16)' not in banner:
    print('FAIL: the restricted-access banner no longer uses the semantic amber tint')
    sys.exit(1)
if banner.count('.buttonStyle(.bordered)') < 2 or '.tint(nil)' not in banner:
    print('FAIL: purchase and restore must use the same neutral native style')
    sys.exit(1)

print('Adaptive light/dark appearance and semantic macOS colors verified.')
