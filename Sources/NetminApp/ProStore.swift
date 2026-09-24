import AppKit
import StoreKit
import SwiftUI

@MainActor
final class NetminProStore: ObservableObject {
    static let shared = NetminProStore()
    static let entitlementDidChange = Notification.Name("NetminProEntitlementDidChange")
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    enum PurchaseOutcome: Equatable { case unlocked, pending, cancelled }

    @Published private(set) var entitlement = NetminEntitlement.free
    @Published private(set) var yearly: Product?
    @Published private(set) var lifetime: Product?
    @Published private(set) var storeError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var appTrialStartedAt: Date?
    @Published private(set) var hasResolvedEntitlement = false
    @Published private(set) var freeRequestsUsedToday = 0

    private var updates: Task<Void, Never>?
    private var refreshGeneration = 0
    private var entitlementTimer: Timer?
    private var appTrialTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var panel: NSWindowController?
    private var freeUsageDay: Date?
    private let defaults = UserDefaults.standard

    private static let appTrialStartedAtKey = "NetminAppTrialStartedAt"
    private static let freeUsageDayKey = "NetminFreeUsageDay"
    private static let freeUsageCountKey = "NetminFreeUsageCount"

    // Only an ignored private build input can provide local Pro access.
    private var developerOverride: Bool? { NetminEdition.localProAccess }

    var isPro: Bool { developerOverride ?? entitlement.isPro }
    var isLocalBuild: Bool { developerOverride == true }
    var isAppTrialActive: Bool {
        guard developerOverride == nil, !entitlement.isPro, let appTrialStartedAt else { return false }
        return NetminFreeAccessPolicy.isTrialActive(startedAt: appTrialStartedAt)
    }
    var hasFullAccess: Bool { isPro || isAppTrialActive }
    var hasPreparedFreeAccess: Bool { isLocalBuild || appTrialStartedAt != nil }
    var freeRequestsRemainingToday: Int {
        let used = NetminFreeAccessPolicy.requestsUsedToday(
            storedDay: freeUsageDay,
            storedCount: freeRequestsUsedToday
        )
        return NetminFreeAccessPolicy.requestsRemaining(used: used)
    }

    var statusText: String {
        if isLocalBuild {
            return NetminEdition.localAccessStatus ?? localized("Pro")
        }
        if isAppTrialActive, let appTrialStartedAt {
            let days = NetminFreeAccessPolicy.trialDaysRemaining(startedAt: appTrialStartedAt)
            return days == 1 ? localized("Pro trial · 1 day remaining")
                : localizedFormat("Pro trial · %lld days remaining", Int64(days))
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        switch NetminEntitlementLogic.statusKind(for: entitlement) {
        case .free: return localizedFormat("Free · %lld of %lld requests left today", Int64(freeRequestsRemainingToday), Int64(NetminFreeAccessPolicy.dailyRequestLimit))
        case .active: return localized("Pro")
        case .lifetime: return localized("Pro · lifetime")
        case .familyShared: return localized("Pro · shared with your family")
        case .trialRenews(let date): return localizedFormat("Pro trial · first payment %@", formatter.string(from: date))
        case .trialEnds(let date): return localizedFormat("Pro trial · ends %@", formatter.string(from: date))
        case .trialUntil(let date): return localizedFormat("Pro trial · until %@", formatter.string(from: date))
        case .renews(let date): return localizedFormat("Pro · renews %@", formatter.string(from: date))
        case .ends(let date): return localizedFormat("Pro · ends %@", formatter.string(from: date))
        case .activeUntil(let date): return localizedFormat("Pro · until %@", formatter.string(from: date))
        }
    }

    func start() {
        guard developerOverride == nil else {
            hasResolvedEntitlement = true
            return
        }
        prepareFreeAccess()
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        // Recheck after wake or an Apple Account change while the app was inactive.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.prepareFreeAccess()
                self.objectWillChange.send()
                await self.refreshEntitlement()
            }
        }
        Task { [weak self] in await self?.refreshEntitlement() }
    }

    deinit {
        updates?.cancel()
        entitlementTimer?.invalidate()
        appTrialTimer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    func loadProducts() async throws {
        guard developerOverride == nil else { return }
        isLoading = true
        storeError = nil
        defer { isLoading = false }
        let products = try await Product.products(for: NetminProductID.all)
        let yearly = products.first { $0.id == NetminProductID.yearly }
        let lifetime = products.first { $0.id == NetminProductID.lifetime }
        guard yearly != nil || lifetime != nil else {
            throw StoreFailure(localized("Pro purchases are unavailable right now. Please try again later."))
        }
        self.yearly = yearly
        self.lifetime = lifetime
    }

    /// Counts a diagnostic when it starts. Viewing or copying an existing result is never counted.
    func beginDiagnosticRequest(now: Date = Date()) -> Bool {
        guard developerOverride == nil else { return true }
        prepareFreeAccess(now: now)
        guard !hasFullAccess else { return true }
        refreshFreeUsage(now: now)
        guard let nextCount = NetminFreeAccessPolicy.countAfterStartingRequest(
            used: freeRequestsUsedToday
        ) else { return false }
        freeRequestsUsedToday = nextCount
        defaults.set(freeRequestsUsedToday, forKey: Self.freeUsageCountKey)
        return true
    }

    func purchase(_ product: Product, confirmIn window: NSWindow?) async throws -> PurchaseOutcome {
        if developerOverride == true { return .unlocked }
        let result: Product.PurchaseResult
        if #available(macOS 15.2, *), let window {
            result = try await product.purchase(confirmIn: window, options: [])
        } else {
            result = try await product.purchase(options: [])
        }
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw StoreFailure(localized("The App Store could not verify this purchase."))
            }
            await transaction.finish()
            await refreshEntitlement()
            return .unlocked
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws -> Bool {
        if developerOverride == true { return true }
        try await AppStore.sync()
        await refreshEntitlement()
        return isPro
    }

    func refreshProducts() async {
        do {
            try await loadProducts()
        } catch {
            storeError = error.localizedDescription
        }
    }

    func present(feature: NetminProFeature? = nil) {
        if let panel {
            panel.showWindow(nil)
            panel.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = NetminProPanelController(store: self, feature: feature)
        panel = controller
        controller.onClose = { [weak self] in self?.panel = nil }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshEntitlement() async {
        guard developerOverride == nil else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        var summaries: [NetminTransactionSummary] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            summaries.append(summary(of: transaction))
        }
        // A newer StoreKit refresh supersedes this result.
        guard generation == refreshGeneration else { return }
        // Do not show post-trial UI until StoreKit's cached entitlement state is known.
        hasResolvedEntitlement = true
        var next = NetminEntitlementLogic.evaluate(summaries)
        // Preserve known renewal state while refreshing the same entitlement.
        if next.kind == entitlement.kind,
           next.expirationDate == entitlement.expirationDate,
           next.isFamilyShared == entitlement.isFamilyShared {
            next.willAutoRenew = entitlement.willAutoRenew
        }
        applyEntitlement(next)
        scheduleEntitlementRefresh()
        // Publish verified access before an optional network-backed renewal lookup finishes.
        if next.kind == .subscription {
            next.willAutoRenew = await subscriptionWillAutoRenew(for: next)
            guard generation == refreshGeneration else { return }
            applyEntitlement(next)
        }
    }

    /// Starts the local trial after the first-launch disclosure is accepted.
    func beginAppTrial(now: Date = Date()) {
        prepareFreeAccess(startTrialIfNeeded: true, now: now)
    }

    /// Restores local trial and free-allowance state, optionally starting the trial.
    private func prepareFreeAccess(startTrialIfNeeded: Bool = false, now: Date = Date()) {
        if let forced = NetminEdition.forcedTrialStartedAt {
            // Private previews must not change the real trial date in preferences.
            appTrialStartedAt = forced
        } else if appTrialStartedAt == nil {
            if let stored = defaults.object(forKey: Self.appTrialStartedAtKey) as? Date {
                appTrialStartedAt = stored
            } else if startTrialIfNeeded {
                appTrialStartedAt = now
                defaults.set(now, forKey: Self.appTrialStartedAtKey)
            }
        }
        refreshFreeUsage(now: now)
        scheduleAppTrialExpiry(now: now)
    }

    // scheduleAppTrialExpiry([now]): Publish the free tier as soon as the local trial expires.
    private func scheduleAppTrialExpiry(now: Date = Date()) {
        appTrialTimer?.invalidate()
        appTrialTimer = nil
        guard let appTrialStartedAt,
              NetminFreeAccessPolicy.isTrialActive(startedAt: appTrialStartedAt, now: now) else {
            return
        }
        let expiry = appTrialStartedAt.addingTimeInterval(NetminFreeAccessPolicy.trialDuration)
        appTrialTimer = Timer.scheduledTimer(
            withTimeInterval: max(1, expiry.timeIntervalSince(now)),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    private func refreshFreeUsage(now: Date) {
        let storedDay = defaults.object(forKey: Self.freeUsageDayKey) as? Date
        let storedCount = defaults.integer(forKey: Self.freeUsageCountKey)
        let isSameDay = storedDay.map {
            Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: now)
        } ?? false
        let used = NetminFreeAccessPolicy.requestsUsedToday(
            storedDay: storedDay,
            storedCount: storedCount,
            now: now
        )
        freeUsageDay = now
        freeRequestsUsedToday = used
        if used != storedCount || !isSameDay {
            defaults.set(now, forKey: Self.freeUsageDayKey)
            defaults.set(used, forKey: Self.freeUsageCountKey)
        }
    }

    private func applyEntitlement(_ updated: NetminEntitlement) {
        guard updated != entitlement else { return }
        entitlement = updated
        NotificationCenter.default.post(name: Self.entitlementDidChange, object: self)
    }

    private func summary(of transaction: StoreKit.Transaction) -> NetminTransactionSummary {
        let introductory: Bool
        if #available(macOS 14.2, *) {
            introductory = transaction.offer?.type == .introductory
        } else {
            introductory = transaction.offerType == .introductory
        }
        return NetminTransactionSummary(
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isFamilyShared: transaction.ownershipType == .familyShared,
            isIntroductoryOffer: introductory
        )
    }

    private func subscriptionWillAutoRenew(for current: NetminEntitlement) async -> Bool? {
        guard current.kind == .subscription else { return nil }
        if yearly == nil { try? await loadProducts() }
        guard let statuses = try? await yearly?.subscription?.status else { return nil }
        for status in statuses {
            guard case .verified(let transaction) = status.transaction,
                  transaction.productID == NetminProductID.yearly,
                  transaction.revocationDate == nil,
                  transaction.expirationDate == current.expirationDate,
                  (transaction.ownershipType == .familyShared) == current.isFamilyShared,
                  case .verified(let renewal) = status.renewalInfo else { continue }
            return renewal.willAutoRenew
        }
        return nil
    }

    private func scheduleEntitlementRefresh() {
        entitlementTimer?.invalidate()
        entitlementTimer = nil
        guard entitlement.kind == .subscription else { return }
        let remaining = entitlement.expirationDate?.timeIntervalSinceNow ?? 60
        let delay = remaining > 0 ? max(1, min(60, remaining)) : 60
        entitlementTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshEntitlement() }
        }
    }
}

private struct StoreFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private final class NetminProPanelController: NSWindowController, NSWindowDelegate {
    private static let panelWidth: CGFloat = 556

    var onClose: (() -> Void)?

    init(store: NetminProStore, feature: NetminProFeature?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localized("Netmin Pro")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: NetminProView(
            store: store,
            feature: feature,
            resize: { [weak self] height in self?.fitWindow(to: height) }
        ))
        window.contentView?.layoutSubtreeIfNeeded()
        if let height = window.contentView?.fittingSize.height, height > 0 {
            fitWindow(to: height, animate: false)
        }
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) { onClose?() }

    // fitWindow(to, [animate = true]): Match the visible SwiftUI content while
    // keeping the panel's top edge fixed as its store state changes.
    private func fitWindow(to height: CGFloat, animate: Bool = true) {
        guard let window, height > 0 else { return }
        let size = NSSize(width: Self.panelWidth, height: ceil(height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let current = window.frame
        guard abs(current.height - frame.height) >= 1 || abs(current.width - frame.width) >= 1 else { return }
        frame.origin = NSPoint(x: current.minX, y: current.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}

private struct NetminProPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NetminProView: View {
    @ObservedObject var store: NetminProStore
    let feature: NetminProFeature?
    let resize: (CGFloat) -> Void
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Netmin Pro")
                    .font(.system(size: 22, weight: .bold))
                Text(feature.map { localizedFormat("Unlock %@, plus the complete Pro feature set.", localized($0.rawValue)) }
                     ?? localized("Unlimited network diagnostics with readable reports and export tools."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                proFeature("Unlimited use of all 84 diagnostic tools", symbol: "infinity")
                proFeature("Structured reports with tables, metrics, and findings", symbol: "tablecells")
                proFeature("Save reports and copy structured summaries", symbol: "square.and.arrow.down")
            }

            Text("The first 30 days include Pro. After the trial, Free keeps all 84 tools and raw output, with five diagnostic requests per day.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                statusSection
                if store.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading App Store products…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else if !store.isPro {
                    purchaseButtons
                }
                if let message {
                    Text(localized(message))
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }

            HStack {
                if !store.isPro {
                    Button("Restore Purchases") { restore() }
                        .buttonStyle(.link)
                        .keyboardFocusable()
                }
                Spacer()
                Button(store.isPro ? "OK" : "Close") { NSApp.keyWindow?.close() }
                    .keyboardFocusable()
                    .controlSize(.large)
                    .keyboardShortcut(store.isPro ? .defaultAction : .cancelAction)
            }
        }
        .padding(.init(top: 22, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 556)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: NetminProPanelHeightKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(NetminProPanelHeightKey.self, perform: resize)
        .task { await store.refreshProducts() }
    }

    @ViewBuilder private var statusSection: some View {
        if store.isPro || store.isAppTrialActive {
            VStack(alignment: .leading, spacing: 2) {
                Text("You have Netmin Pro.")
                    .font(.system(size: 13))
                Text(localized(store.statusText))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if store.isPro && store.entitlement.kind == .subscription {
                Button("Manage Subscription") {
                    NSWorkspace.shared.open(NetminProStore.manageSubscriptionsURL)
                }
                    .buttonStyle(.link)
                    .keyboardFocusable()
            }
        } else {
            Text(localized(store.statusText))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func proFeature(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(localized(title))
                .font(.system(size: 13))
        }
    }

    @ViewBuilder private var purchaseButtons: some View {
        if let yearly = store.yearly {
            Button { buy(yearly) } label: {
                Text("Netmin Pro Yearly")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardFocusable()
            .controlSize(.large)
            Text(localizedFormat("%@ per year", yearly.displayPrice))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        if let lifetime = store.lifetime {
            Button { buy(lifetime) } label: {
                Text(localizedFormat("Netmin Pro Lifetime · %@", lifetime.displayPrice))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardFocusable()
            .controlSize(.large)
        }
        if store.yearly == nil && store.lifetime == nil {
            Text(localized(store.storeError ?? "Purchases are unavailable right now."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Try Again") { Task { await store.refreshProducts() } }
                .keyboardFocusable()
        }
        Text("Payment goes to your Apple Account. The yearly subscription renews automatically unless cancelled in App Store settings at least a day before the current period ends.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    private func buy(_ product: Product) {
        message = nil
        Task {
            do {
                let outcome = try await store.purchase(product, confirmIn: NSApp.keyWindow)
                if outcome == .pending { message = localized("The purchase is awaiting approval.") }
            } catch { message = error.localizedDescription }
        }
    }

    private func restore() {
        message = nil
        Task {
            do {
                if try await !store.restore() { message = localized("No Netmin Pro purchase was found for this Apple Account.") }
            } catch { message = error.localizedDescription }
        }
    }
}
