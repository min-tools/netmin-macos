# Architecture

Netmin is one app in one repository. The source build and App Store build compile the same Swift and bundled helper files with the same product identity.

| Concern | Source build | App Store build |
| --- | --- | --- |
| Bundle identifier | `tools.min.netmin` | `tools.min.netmin` |
| Access | 30-day Pro trial, then Free or verified Pro access | The same |
| StoreKit verification | Enabled | Enabled |
| Amber access banner | Hidden during the trial; visible afterward without Pro | The same |
| Build configuration | Debug or Release | AppStore |

## Build boundary

`NETMIN_APP_STORE` marks App Store archives and prevents the private local override from entering them. Debug, Release, Swift Package Manager, and App Store builds share StoreKit verification, Free limits, and the amber access banner.

`NetminProStore` owns verified StoreKit state, the on-device trial start, and the daily free allowance in every public build. The first 30 days have full Pro access. Afterward, a user without Pro can start five diagnostics per local calendar day and view raw output; opening or copying an existing result does not spend another request.

## Execution boundary

The engine invokes fixed command templates and loads only the Bash helpers bundled with Netmin. It does not assume a developer-language runtime exists on the customer's Mac.

The App Sandbox refuses to execute setuid tools such as `/usr/sbin/traceroute`. `netmin-traceroute.sh` therefore discovers hops with unprivileged TTL-limited `ping` probes.

Foundation launches each fixed command as a child of the app, so it inherits the containing app's sandbox. The runner limits each command's duration and caps combined standard output and error at 8 MiB. Helpers validate ranges and targets before expanding work, and Local Device Sweep scans at most 16 selected networks sequentially.

The submission checklist still requires exercising every command from a signed sandboxed build on a clean supported Mac. This catches OS-tool and permission changes that static checks cannot predict.

## Data boundary

Preferences and up to eight recent targets use the `tools.min.netmin` app container. The app menu clears the recent targets. Complete diagnostic output stays in memory unless the user copies or exports it.

Diagnostic requests go directly to the resolver, registry, website, remote host, or named public lookup provider required by the selected tool. Those services receive the target and public IP address and may retain them under their own policies. Netmin has no developer-operated diagnostic service.

## Localization and appearance boundary

The English source text is the localization key and fallback. SwiftUI literals and AppKit-created controls therefore read the same `Localizable.strings` catalog. The tool catalog, interpreted report labels, validation errors, purchase state, permission prompt, tooltips, and accessibility labels are also passed through the bundled localization helper. Every language has the same key set and compatible format arguments.

The app does not force an appearance. Custom SwiftUI surfaces use AppKit semantic colors for the window, controls, text, separators, status colors, and system accent. macOS resolves those colors for Light and Dark appearances, increased contrast, the chosen accent, and the current system design. Standard material remains owned by the system, so newer releases such as macOS 27 can apply their native window treatment without an app-specific palette fork.
