#!/usr/bin/env python3
"""Exercise the real paywall actions with suspended, isolated StoreKit substitutes."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

fixture = r'''
import AppKit
import SwiftUI

func localized(_ key: String) -> String { key }
func localizedFormat(_ format: String, _ argument: String) -> String {
    String(format: format, argument)
}
extension View { func keyboardFocusable() -> some View { self } }
enum NetminProFeature: String { case example = "Example" }
struct Product { let displayPrice = "$1.00" }

// Suspend each store call so assertions observe the UI while that action is pending.
@MainActor final class NetminProStore: ObservableObject {
    enum PurchaseOutcome { case unlocked, pending, cancelled }
    struct Failure: LocalizedError {
        var errorDescription: String? { "Test store error" }
    }
    static let manageSubscriptionsURL = URL(string: "https://example.com")!
    @Published var isLoading = false
    var storeError: String?
    struct Entitlement { enum Kind { case none, subscription }; var kind = Kind.none }
    var entitlement = Entitlement()
    var isPro = false
    var isAppTrialActive = true
    var canManageSubscription = false
    var yearly: Product?, lifetime: Product?
    var outcome: PurchaseOutcome = .cancelled
    var restored = false
    var calls: [String] = []
    var continuation: CheckedContinuation<Void, Error>?
    var statusText: String { "Full access trial · 24 days remaining" }
    func suspend(_ action: String) async throws {
        calls.append(action)
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func refreshProducts() async {
        isLoading = true
        storeError = nil
        defer { isLoading = false }
        do { try await suspend("load") }
        catch { storeError = error.localizedDescription }
    }
    func purchase(_ product: Product, confirmIn window: NSWindow?) async throws -> PurchaseOutcome {
        try await suspend("purchase")
        return outcome
    }
    func restore() async throws -> Bool {
        try await suspend("restore")
        return restored
    }
    func complete(failing: Bool = false) {
        let pending = continuation!
        continuation = nil
        if failing { pending.resume(throwing: Failure()) }
        else { pending.resume() }
    }
}
'''
# Compile the complete production view and its state; replace only external store access.
source = (ROOT / 'Sources/NetminApp/ProStore.swift').read_text()
fixture += (ROOT / 'Sources/NetminApp/BuildEdition.swift').read_text()
fixture += '@MainActor\n' + source[source.index('private final class NetminPaywallState:'):].replace('private ', '')
fixture += r'''
@main enum PaywallTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1
        }
        // Bound asynchronous waits so an action that never completes fails clearly.
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<2000 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            fatalError("Timed out waiting for the paywall action")
        }
        let store = NetminProStore()
        let state = NetminPaywallState()
        let view = NetminProView(store: store, feature: nil, state: state, resize: { _ in })
        check(!view.isWorking && view.progressText == nil, "Idle has no progress label")

        // Price loading uses neutral wording and blocks competing purchase/restore actions.
        let loading = Task { await view.load() }
        try await waitFor { store.continuation != nil }
        check(view.isWorking, "Loading is busy")
        check(view.progressText == "Loading App Store products…", "Price loading is not restoring")
        view.buy(Product())
        view.restore()
        check(store.calls == ["load"], "Busy loading rejects competing operations")
        store.complete()
        await loading.value
        check(!view.isWorking && view.progressText == nil, "Loading clears progress")

        // Both purchase products follow the same action; cancellation, pending, and success clear busy state.
        for outcome in [NetminProStore.PurchaseOutcome.cancelled, .pending, .unlocked] {
            store.outcome = outcome
            view.buy(Product())
            check(view.progressText == "Contacting the App Store…", "Purchase never says restoring")
            try await waitFor { store.continuation != nil }
            check(store.calls.last == "purchase", "Purchase calls the purchase API")
            let callCount = store.calls.count
            view.restore()
            view.buy(Product())
            check(store.calls.count == callCount, "Busy purchase rejects duplicate actions")
            store.complete()
            try await waitFor { !view.isWorking }
            check(view.progressText == nil, "Completed purchase clears progress")
            switch outcome {
            case .cancelled: check(state.message == nil, "Cancel does not unlock")
            case .pending: check(state.message == "The purchase is awaiting approval.",
                                 "Pending approval does not unlock")
            case .unlocked: check(state.message == nil, "Success reports unlocked access")
            }
        }

        // Restore alone displays restoring, including the no-purchase and successful cases.
        for restored in [false, true] {
            store.restored = restored
            view.restore()
            check(view.progressText == "Restoring…", "Restore keeps its specific label")
            try await waitFor { store.continuation != nil }
            check(store.calls.last == "restore", "Restore calls the restore API")
            store.complete()
            try await waitFor { !view.isWorking }
            check(view.progressText == nil, "Restore clears progress")
            check(restored ? state.message == nil : state.message == "No Netmin Pro purchase was found for this Apple Account.",
                  "Restore reports the actual entitlement result")
        }

        // Errors must leave controls usable and preserve the relevant error message.
        for restoring in [false, true] {
            if restoring { view.restore() } else { view.buy(Product()) }
            try await waitFor { store.continuation != nil }
            store.complete(failing: true)
            try await waitFor { !view.isWorking }
            check(view.progressText == nil && state.message == "Test store error",
                  "Failed action clears progress and reports its error")
        }
        let failedLoad = Task { await view.load() }
        try await waitFor { store.continuation != nil }
        store.complete(failing: true)
        await failedLoad.value
        check(!view.isWorking && view.progressText == nil && store.storeError == "Test store error",
              "Failed product loading clears progress and remains retryable")
        print("Netmin paywall: \(checks) action and progress checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pastemin-paywall-test-', dir='/private/tmp') as directory:
    folder = Path(directory)
    main = folder / 'main.swift'
    main.write_text(fixture)
    binary = folder / 'tests'
    subprocess.run(swift_compiler() + [
        '-parse-as-library', '-swift-version', '5', '-target', 'arm64-apple-macos14.0',
        '-module-cache-path', str(folder / 'modules'), str(main),
        '-framework', 'AppKit', '-framework', 'SwiftUI', '-o', str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
