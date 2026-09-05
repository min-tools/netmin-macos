import Foundation

// Product identifiers must match App Store Connect. The app's 30-day trial is independent of them.
enum NetminProductID {
    static let yearly = "tools.min.netmin.pro.yearly"
    static let lifetime = "tools.min.netmin.pro.lifetime"
    static let all = [yearly, lifetime]
}

/// The App Store build starts with full access, then becomes a small but useful free tier.
/// Keeping the date arithmetic here makes the policy testable without StoreKit or UserDefaults.
enum NetminFreeAccessPolicy {
    static let trialLengthDays = 30
    static let dailyRequestLimit = 5
    static let trialDuration: TimeInterval = TimeInterval(trialLengthDays * 24 * 60 * 60)

    static func isTrialActive(startedAt: Date, now: Date = Date()) -> Bool {
        now < startedAt.addingTimeInterval(trialDuration)
    }

    static func trialDaysRemaining(startedAt: Date, now: Date = Date()) -> Int {
        let seconds = startedAt.addingTimeInterval(trialDuration).timeIntervalSince(now)
        return max(0, Int(ceil(seconds / (24 * 60 * 60))))
    }

    static func requestsUsedToday(
        storedDay: Date?,
        storedCount: Int,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        guard let storedDay, calendar.isDate(storedDay, inSameDayAs: now) else { return 0 }
        return min(max(0, storedCount), dailyRequestLimit)
    }

    static func requestsRemaining(used: Int) -> Int {
        max(0, dailyRequestLimit - min(max(0, used), dailyRequestLimit))
    }

    static func countAfterStartingRequest(used: Int) -> Int? {
        let normalized = min(max(0, used), dailyRequestLimit)
        guard normalized < dailyRequestLimit else { return nil }
        return normalized + 1
    }
}

struct NetminTransactionSummary: Equatable {
    var productID: String
    var purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?
    var isFamilyShared: Bool
    var isIntroductoryOffer: Bool
}

struct NetminEntitlement: Equatable {
    enum Kind: Equatable { case none, lifetime, subscription }
    var kind: Kind = .none
    var expirationDate: Date?
    var isTrial = false
    var isFamilyShared = false
    var willAutoRenew: Bool?
    var isPro: Bool { kind != .none }
    static let free = NetminEntitlement()
}

enum NetminStatusKind: Equatable {
    case free
    case active
    case lifetime
    case familyShared
    case trialRenews(Date)
    case trialEnds(Date)
    case trialUntil(Date)
    case renews(Date)
    case ends(Date)
    case activeUntil(Date)
}

enum NetminEntitlementLogic {
    // StoreKit's current-entitlement sequence already accounts for expiry and billing grace.
    static func evaluate(_ transactions: [NetminTransactionSummary]) -> NetminEntitlement {
        let live = transactions.filter {
            $0.revocationDate == nil && NetminProductID.all.contains($0.productID)
        }
        if let lifetime = preferred(live.filter { $0.productID == NetminProductID.lifetime }) {
            return NetminEntitlement(kind: .lifetime, isFamilyShared: lifetime.isFamilyShared)
        }
        guard let subscription = preferred(live.filter { $0.productID == NetminProductID.yearly }) else {
            return .free
        }
        return NetminEntitlement(
            kind: .subscription,
            expirationDate: subscription.expirationDate,
            isTrial: subscription.isIntroductoryOffer,
            isFamilyShared: subscription.isFamilyShared
        )
    }

    private static func preferred(_ candidates: [NetminTransactionSummary]) -> NetminTransactionSummary? {
        candidates.max { first, second in
            if first.isFamilyShared != second.isFamilyShared { return first.isFamilyShared }
            return (first.expirationDate ?? .distantFuture) < (second.expirationDate ?? .distantFuture)
        }
    }

    static func statusKind(for entitlement: NetminEntitlement, now: Date = Date()) -> NetminStatusKind {
        switch entitlement.kind {
        case .none:
            return .free
        case .lifetime:
            return entitlement.isFamilyShared ? .familyShared : .lifetime
        case .subscription:
            if entitlement.isFamilyShared { return .familyShared }
            guard let date = entitlement.expirationDate, date > now else { return .active }
            switch (entitlement.isTrial, entitlement.willAutoRenew) {
            case (true, .some(true)): return .trialRenews(date)
            case (true, .some(false)): return .trialEnds(date)
            case (true, .none): return .trialUntil(date)
            case (false, .some(true)): return .renews(date)
            case (false, .some(false)): return .ends(date)
            case (false, .none): return .activeUntil(date)
            }
        }
    }
}
