# Build and test

## Public source build

```bash
python3 scripts/build.py
```

The output is `build/Netmin.app`, ad-hoc signed for local development. The normal 30-day full-access trial, free limit, and verified-purchase rules remain active. The amber purchase banner appears only after the trial expires.

Use `--configuration Debug` for debugging, `--unsigned` to skip ad-hoc signing, `--arch arm64` to state the supported architecture explicitly, or `--output /private/tmp/Netmin.app` to choose another output. The builder does not install or launch the app.

The Xcode Debug and Release configurations use the same access policy:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Netmin.xcodeproj \
  -scheme Netmin -configuration Release \
  -derivedDataPath /private/tmp/NetminDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Both builders compile in a staging directory and replace an older generated bundle only after every build step succeeds.

## App Store build

Use the Xcode AppStore configuration for archives sent to App Review. It defines `NETMIN_APP_STORE`, uses the same on-device trial, Free limit, verified StoreKit access, and amber access banner.

For isolated compilation and packaging tests only:

```bash
python3 scripts/build.py --app-store
```

This creates `build/app-store/Netmin.app` without replacing the local bundle. Both editions therefore keep the real `Netmin.app` filename. To build both variants together, run:

```bash
python3 scripts/build.py --both
```

The two bundles share one bundle identifier and app container, so do not run them at the same time. Submit only a properly signed Xcode archive, never the ad-hoc App Store test bundle produced by the script.

## Source layout

| Path | Contents |
| --- | --- |
| `Netmin.xcodeproj` | Source, release, and App Store configurations |
| `Sources/NetminApp` | SwiftUI interface, command engine, StoreKit logic, and resources |
| `Sources/NetminApp/Resources/Scripts` | Bash helpers bundled into every app |
| `Sources/NetminApp/Resources/*.lproj` | Matching app and permission translations for 27 languages |
| `scripts` | Staged builder, source export, release audit, and regression suites |
| `docs` | Architecture and submission guidance |

## Test

```bash
python3 scripts/test_all.py
```

The suite type-checks the source and App Store variants, tests the trial, daily request limit, and entitlement decisions without an Apple Account, validates localization coverage and format safety, prevents a forced appearance or fixed RGB palette, validates command quoting and bundled helpers, and checks the app identity, privacy manifest, entitlements, staged packaging, and Xcode archive configuration. Fixture tests do not contact diagnostic services or make purchases.

## Export source

```bash
python3 scripts/export_source.py --output /private/tmp/netmin-source
```

The destination must not exist. Repository metadata, build directories, app bundles, caches, and symbolic links are excluded.
