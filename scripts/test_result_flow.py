#!/usr/bin/env python3
"""Guard the live-result and on-the-fly summary UX against silent regressions."""
from build import ROOT

app = ROOT / 'Sources/NetminApp'
form = (app / 'ToolFormView.swift').read_text()
result = (app / 'ResultView.swift').read_text()
runner = (app / 'CommandRunner.swift').read_text()
template = (app / 'CommandTemplate.swift').read_text()
theme = (app / 'Theme.swift').read_text()
root_view = (app / 'NetminRootView.swift').read_text()
build_edition = (app / 'BuildEdition.swift').read_text()
access_banner = (app / 'AccessBanner.swift').read_text()
sidebar = (app / 'SidebarView.swift').read_text()
pro_store = (app / 'ProStore.swift').read_text()
network_helper = (app / 'Resources/Scripts/netmin-network-lookup.sh').read_text()
zone_helper = (app / 'Resources/Scripts/netmin-dns-zone-discovery.sh').read_text()
sweep_helper = (app / 'Resources/Scripts/netmin-local-device-sweep.sh').read_text()
document_helper = (app / 'Resources/Scripts/netmin-document-fetch.sh').read_text()

# Live output streams while a command runs and the summary opens when it completes.
assert 'RawTextView(text: consoleText, followsTail: true)' in form
assert 'class ConsoleClipView: NSClipView' in form
assert 'class ConsoleScrollView: NSScrollView' in form
assert 'if keepsLeadingEdge { bounds.origin.x = 0 }' in form
assert 'clipView.keepsLeadingEdge = followsTail' in form
assert 'frame.origin.x = 0' in form
assert 'frame.size.width = max(frame.width, contentView.bounds.width)' in form
assert 'textView.textContainer?.lineFragmentPadding = 0' in form
assert 'origin.x = 0' in form
assert 'scroll.reflectScrolledClipView(scroll.contentView)' in form
assert 'if !runner.output.isEmpty' not in form
assert 'Waiting for the first response…' in form
assert 'availableData' in runner
assert 'onFinish' in runner
assert 'maximumOutputBytes' in runner
assert 'tool.maximumDuration' in runner
assert 'process.interrupt()' in runner
assert "section 'Basic'" in network_helper
assert "printf '\\n%s\\n' \"$1\"" in network_helper
assert '===' not in network_helper
assert '===' not in zone_helper
assert '===' not in (app / 'Resources/Scripts/netmin-site-report.sh').read_text()
assert '=== $resolver ===' not in (app / 'Resources/tools.tsv').read_text()
assert "Completeness: Complete" in zone_helper
assert "Completeness: Partial discovery" in zone_helper
assert 'AXFR' in zone_helper and 'NSEC3' in zone_helper and 'crt.sh' in zone_helper
# The App Sandbox cannot execute the setuid traceroute, so the route comes from ICMP echo probes.
assert '/usr/sbin/traceroute' not in network_helper
assert 'netmin-traceroute.sh' in network_helper
assert '/usr/sbin/traceroute' not in (app / 'Resources/tools.tsv').read_text()
assert '/opt/homebrew' not in template
assert 'var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "NO_COLOR": "1"]' in template
assert 'var environment = ProcessInfo.processInfo.environment' not in template
assert 'netmin-document-fetch.sh" security "$1"' in (app / 'Resources/tools.tsv').read_text()
assert 'netmin-document-fetch.sh" robots "$1"' in (app / 'Resources/tools.tsv').read_text()
assert '--max-redirs 20' in document_helper
assert 'returned an HTML page instead of' in document_helper
assert "${requested_host#www.}" in document_helper
assert "grep -Eiq '^[[:space:]]*contact" in document_helper

# Results open on the summary built from the output; a header toggle shows the raw console instead.
assert 'Picker(' not in result
assert 'enum Tab' not in result
assert 'model.summary(for: run)' in result
assert 'StatTile(metric:' in result
assert 'DeviceTableView(devices:' in result
assert 'SummarySectionView(section:' in result
assert 'SegmentedControl(options: ["Overview", "Raw output"]' in result
assert 'RawTextView(text: run.output)' in result
assert 'if insight?.severity != .error' in result
# The choice is remembered across results and mirrored in the native View menu with ⌘1 / ⌘2.
assert 'model.showsRawOutput' in result
model_source = (app / 'AppModel.swift').read_text()
assert 'UserDefaults.standard.bool(forKey: AppModel.rawOutputKey)' in model_source
app_source = (app / 'NetminApp.swift').read_text()
assert 'item(localized("Overview"), .overview, key: "1", modifiers: .command)' in app_source
assert 'item(localized("Raw Output"), .rawOutput, key: "2", modifiers: .command)' in app_source
assert 'installNativeCommands()' in app_source
assert 'string: "GitHub.com/iliaross"' in app_source
assert 'URL(string: "https://github.com/iliaross")' in app_source
assert 'iconView,\n            nameLabel,\n            versionLabel,\n            copyrightLabel,\n            profileButton' in app_source
assert 'MinToolsAboutPanelController.shared.show(applicationName: "Netmin")' in app_source
assert 'let size = NSSize(width: 280, height: 174)' in app_source
assert 'stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10)' in app_source
assert app_source.count('.commands {') == 1
assert 'CommandGroup(replacing: .appInfo)' in app_source
assert 'Button(localized("About Netmin"))' in app_source
assert 'appDelegate.showAbout()' in app_source
assert 'CommandMenu(' not in app_source
assert 'installAboutCommand' not in app_source
assert 'NSMenu.didBeginTrackingNotification' not in app_source
assert 'NSMenu(title: localized("Tools"))' in app_source
assert 'item(localized("Run"), .run, key: "\\r", modifiers: .command)' in app_source
assert 'item(localized("Stop"), .stop, key: "\\u{1b}")' in app_source
assert 'chevron.left' not in result  # the footer's New Lookup button (esc) is the only way back
assert '.buttonStyle(.netmin(.ghost, shortcut: "esc"))' in result

# Raw output and the command stay one click away in the footer and the menu.
assert 'SplitButton(title: "Copy Result"' in result
assert 'SplitMenuItem("Copy Raw Output")' in result
assert 'SplitMenuItem("Copy Command")' in result
assert 'SplitMenuItem("Copy Summary")' in result
assert 'copy(run.output, note: "raw output")' in result
# The split control keeps its custom shell while using keyboard-operable native controls.
assert 'struct SplitButton: View' in theme
assert 'Button(action: action)' in theme
assert 'Menu {' in theme
assert '.menuStyle(.borderlessButton)' in theme
assert '.frame(width: Theme.controlHeight, height: Theme.controlHeight)' in theme
assert theme.count('.keyboardFocusable()') >= 2
# Running and finished states share the header height and console padding, so nothing jumps.
assert '.frame(height: 84)' in form and '.frame(height: 88)' not in form
assert ".overlay(ProgressStripe().frame(height: 2))" in form
running_view = form.split('private struct RunningView: View', 1)[1].split('struct RawTextView:', 1)[0]
assert 'HStack(spacing: 14)' in running_view
assert 'VStack(alignment: .leading, spacing: 3)' in running_view
assert 'Text(tool.localizedTitle)' in running_view
assert 'Text(tool.localizedProgressMessage)' in running_view
assert 'Live output · the summary opens when the command completes' not in running_view
assert 'HStack(spacing: 14)' in result
assert 'VStack(alignment: .leading, spacing: 3)' in result
assert 'Raw output\n' in result  # the saved report keeps the complete output

# The design system: one button style with 34 pt controls, chips for shortcuts, one accent gradient.
assert 'static let controlHeight: CGFloat = 34' in theme
assert 'static let radius: CGFloat = 10' in theme
assert 'struct NetminButtonStyle: ButtonStyle' in theme
assert 'KeyCap(shortcut' in theme
assert 'topHighlight' in theme
assert theme.count('@Environment(\\.accessibilityReduceMotion)') >= 2
# Segments share one edge-to-edge container instead of nesting a pill inside a padded shell.
segmented = theme.split('struct SegmentedControl: View', 1)[1].split('struct CheckMark: View', 1)[0]
assert 'HStack(spacing: 0)' in segmented
assert '.padding(2)' not in segmented
assert 'if index < options.count - 1' in segmented
assert '.padding(.vertical, 6)' not in segmented
assert segmented.count('.frame(height: Theme.controlHeight)') == 2
assert '.fixedSize(horizontal: true, vertical: true)' in segmented
assert 'minWidth:' not in segmented
assert 'minHeight: Theme.controlHeight' not in segmented
assert '.buttonStyle(.netmin(.primary, shortcut: "⌘↩"))' in form
assert '.buttonStyle(.netmin(.ghost, shortcut: "esc"))' in form
assert '.buttonStyle(.netmin(.danger, shortcut: "esc"))' in form
assert 'previewCommand' not in form
assert sidebar.count('.help(') == 1 and '.help(favoriteLabel)' in sidebar
assert 'tool.title == "DNS Zone Discovery"' in form
assert 'SegmentedControl(options: ["Quick", "Deep"]' in form
assert 'Text("Use custom resolver")' in form
assert 'if model.useCustomResolver { resolverSection }' in form
assert 'CommandTemplate.command(for: tool, resolver: resolver)' not in form
catalog = (app / 'Resources/tools.tsv').read_text()
assert '[Custom DNS Resolver]' not in catalog
assert 'DNS A using Resolver' not in catalog
assert 'DNS Zone Transfer\t' in catalog

# The form validates what was typed before Run and previews the sweep networks.
assert 'TargetField(' in form
assert 'model.targetKind' in form
target_field = theme.split('struct TargetField: View', 1)[1].split('struct ProgressStripe: View', 1)[0]
assert '.offset(y: -1.5)' in target_field
assert 'Target (optional)' in form
assert 'if tool.requiresTarget' in (app / 'AppModel.swift').read_text()
assert 'SweepFormView(model: model)' in form
assert 'LocalNetworks.detect()' in (app / 'AppModel.swift').read_text()
assert "IFS=',' read -ra requested" in sweep_helper
assert 'Default gateway:' in sweep_helper

# The sidebar filter is the only tool finder. ⌘K focuses its flicker-safe text client in the key
# window instead of opening a second command-palette surface.
assert not (app / 'CommandPaletteView.swift').exists()
assert '.sheet(' not in root_view
assert 'showingPalette' not in root_view
assert 'showingPalette' not in (app / 'AppModel.swift').read_text()
assert 'NotificationCenter.default.post(name: .focusSidebarSearch, object: keyWindow)' in app_source
assert 'focusOnWindowOpen: true' in sidebar
assert 'StableTextInput(' in theme
assert 'final class StableInputTextView: NSTextView' in theme
assert 'TextField(' not in theme
assert 'TextField(' not in (app / 'SweepFormView.swift').read_text()
assert 'preferredTextAccessoryPlacement() -> NSTextCursorAccessoryPlacement { .invisible }' in theme
assert 'NSWindow.didBecomeKeyNotification' in theme
assert 'forName: .focusSidebarSearch' in theme
assert 'selectAll(nil)' in theme
assert 'height: floor((contentHeight - lineHeight) / 2) + textVerticalOffset' in theme
assert 'textVerticalOffset: 0' in sidebar
assert '@State private var targetFocused = false' in form
assert '@FocusState private var targetFocused' not in form
assert 'onFocusChange: { isFocused = $0 }' in theme
assert 'window.isVisible' in theme and 'window.isKeyWindow' in theme
assert 'window.makeFirstResponder(self)' in theme
assert 'List(selection: listAppearanceReady ? sidebarSelection : .constant(nil))' in sidebar
assert 'Section(isExpanded: expansionBinding(for: group.id))' in sidebar
assert '@State private var collapsedGroups: Set<String>' in sidebar
assert 'transaction.disablesAnimations = true' in sidebar
assert 'withAnimation(' not in sidebar
assert 'NetminCollapsedToolGroups' in sidebar
assert 'UserDefaults.standard.set(updated.sorted()' in sidebar
assert 'model.isFavorite(tool)' in sidebar
assert 'model.toggleFavorite(tool)' in sidebar
assert 'Image(systemName: isFavorite ? "star.fill" : "star")' in sidebar
assert 'NetminFavoriteToolIDs' in model_source
assert 'ToolGroup(name: "Favorites", tools: favorites)' in model_source
assert 'func toggleFavorite(_ tool: ToolDefinition)' in model_source
assert 'listAppearanceReady = true' in sidebar
assert '.listStyle(.sidebar)' in sidebar
assert '.focusEffectDisabled()' in sidebar
assert 'table.selectionHighlightStyle = .none' in sidebar
assert 'selected ? Theme.accent.opacity(0.13)' in sidebar
assert '.onChange(of: model.sidebarQuery)' in sidebar
assert 'model.select(firstMatch)' in sidebar
assert 'restoreToolListFocus' not in sidebar
assert '.onKeyPress(' not in sidebar
assert '.onAppear { targetFocused =' not in form
assert 'case 48 where modifiers.isEmpty || modifiers == .shift:' in theme
assert 'moveSelection?(offset)' not in theme
assert 'func keyboardFocusable() -> some View' in theme
assert theme.count('.keyboardFocusable()') >= 8
assert form.count('.keyboardFocusable()') >= 5
assert result.count('.keyboardFocusable()') >= 6

# Public source builds retain access limits and show an amber purchase banner.
assert 'static let bundleIdentifier = "tools.min.netmin"' in build_edition
assert 'NETMIN_LOCAL_BUILD && NETMIN_APP_STORE' in build_edition
assert 'static let localProAccess: Bool? = nil' in build_edition
assert '#if !NETMIN_APP_STORE' not in access_banner
assert 'NetminAccessBanner()' in root_view
assert root_view.index('NetminAccessBanner()') > root_view.index('HStack(spacing: 0)')
assert 'if store.hasResolvedEntitlement && store.hasPreparedFreeAccess && !store.hasFullAccess' in access_banner
assert 'if store.hasResolvedEntitlement && store.hasPreparedFreeAccess && !store.hasFullAccess' in form
assert '@Published private(set) var hasResolvedEntitlement = false' in pro_store
assert 'var hasPreparedFreeAccess: Bool' in pro_store
assert 'localized("Trial ended")' in access_banner
assert 'Netmin is now limited to 5 diagnostic requests per day.' in access_banner
assert 'localized("Restore Purchases")' in access_banner
assert 'Button(localized("Purchase"))' in access_banner
assert 'Color(nsColor: .systemOrange).opacity(0.16)' in access_banner
assert 'Color(nsColor: .systemOrange).opacity(0.48)' in access_banner
assert '.buttonStyle(.bordered)' in access_banner
assert 'AppLinks.purchase' not in access_banner
assert 'cryptocurrency' not in access_banner and 'Not now' not in access_banner
assert 'Support Netmin' not in sidebar and 'SourceSupportStore' not in sidebar
assert 'NetminProStore.shared' not in sidebar and 'store.statusText' not in sidebar
assert 'NetminEdition.localProAccess' in pro_store
assert 'var isLocalBuild: Bool' in pro_store
assert 'static let trialLengthDays = 30' in (app / 'ProEntitlementLogic.swift').read_text()
assert 'static let dailyRequestLimit = 5' in (app / 'ProEntitlementLogic.swift').read_text()
assert 'func beginDiagnosticRequest' in pro_store
assert 'guard beginDiagnosticRequest() else { return }' in model_source
assert model_source.count('guard beginDiagnosticRequest() else { return }') == 3
assert 'five diagnostic requests per day' in pro_store
assert 'NetminDidShowTrialWelcome' in app_source
assert '30 days of full access' in app_source
assert 'No subscription starts, and you will not be charged.' in app_source
assert 'presentTrialWelcomeIfNeeded()' in app_source
assert 'func beginAppTrial(now: Date = Date())' in pro_store
assert 'startTrialIfNeeded: Bool = false' in pro_store
acknowledge = app_source.index('_ = alert.runModal()')
begin_trial = app_source.index('store.beginAppTrial()', acknowledge)
record_disclosure = app_source.index('UserDefaults.standard.set(true, forKey: Self.didShowTrialWelcomeKey)', begin_trial)
assert acknowledge < begin_trial < record_disclosure
assert 'applicationMenu.insertItem(item(localized("Netmin Pro…"), .showPro), at: insertion)' in app_source
assert 'applicationMenu.insertItem(item(localized("Privacy Policy…"), .showPrivacy), at: insertion + 1)' in app_source
assert 'else if !store.hasFullAccess' in result
assert 'store.present(feature: .structuredReports)' in result
assert 'localized("Clear Recent Data…")' in app_source
assert 'model.clearRecentData()' in app_source

print('Result flow: bounded live output, Pro reports, clear-data controls and compact actions passed')
