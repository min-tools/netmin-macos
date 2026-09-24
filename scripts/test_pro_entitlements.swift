import Foundation

@main
struct EntitlementTests {
    static let now = Date(timeIntervalSince1970: 2_000_000)
    static let later = now.addingTimeInterval(3_600)

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func transaction(_ product: String, expiration: Date? = nil, revoked: Bool = false,
                            shared: Bool = false, trial: Bool = false) -> NetminTransactionSummary {
        NetminTransactionSummary(
            productID: product,
            purchaseDate: now,
            expirationDate: expiration,
            revocationDate: revoked ? now : nil,
            isFamilyShared: shared,
            isIntroductoryOffer: trial
        )
    }

    static func main() {
        let trialStart = now
        check(NetminFreeAccessPolicy.isTrialActive(
            startedAt: trialStart,
            now: trialStart.addingTimeInterval(29 * 24 * 60 * 60)
        ), "The app trial lasts through day 29")
        check(!NetminFreeAccessPolicy.isTrialActive(
            startedAt: trialStart,
            now: trialStart.addingTimeInterval(30 * 24 * 60 * 60)
        ), "The app trial expires after 30 days")
        check(NetminFreeAccessPolicy.trialDaysRemaining(startedAt: trialStart, now: trialStart) == 30,
              "A new trial reports 30 days remaining")

        let localStart = now.addingTimeInterval(24 * 60 * 60)
        check(NetminFreeAccessPolicy.authoritativeTrialStartDate(
            appStoreOriginalPurchaseDate: now,
            localStartedAt: localStart,
            usesAppStoreDate: true
        ) == now, "The signed App Store date overrides local state")
        check(NetminFreeAccessPolicy.authoritativeTrialStartDate(
            appStoreOriginalPurchaseDate: nil,
            localStartedAt: localStart,
            usesAppStoreDate: true
        ) == nil, "A missing signed date never falls back to local state")
        check(NetminFreeAccessPolicy.authoritativeTrialStartDate(
            appStoreOriginalPurchaseDate: nil,
            localStartedAt: localStart,
            usesAppStoreDate: false
        ) == localStart, "Source builds retain their local trial date")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        check(NetminFreeAccessPolicy.requestsUsedToday(
            storedDay: now, storedCount: 4, now: now.addingTimeInterval(60), calendar: calendar
        ) == 4, "Usage is retained during the same local day")
        check(NetminFreeAccessPolicy.requestsUsedToday(
            storedDay: now, storedCount: 5, now: now.addingTimeInterval(24 * 60 * 60), calendar: calendar
        ) == 0, "Usage resets on the next local day")
        check(NetminFreeAccessPolicy.requestsRemaining(used: 0) == 5,
              "The Free tier starts each day with five requests")
        check(NetminFreeAccessPolicy.requestsRemaining(used: 5) == 0,
              "The sixth Free request is unavailable")
        var used = 0
        for expected in 1...5 {
            used = NetminFreeAccessPolicy.countAfterStartingRequest(used: used) ?? -1
            check(used == expected, "Each of the first five Free requests is allowed")
        }
        check(NetminFreeAccessPolicy.countAfterStartingRequest(used: used) == nil,
              "The sixth Free request is rejected")

        check(!NetminEntitlementLogic.evaluate([]).isPro, "No transaction is free")
        check(!NetminEntitlementLogic.evaluate([transaction("unknown")]).isPro, "Unknown products are ignored")
        check(!NetminEntitlementLogic.evaluate([
            transaction(NetminProductID.lifetime, revoked: true)
        ]).isPro, "Revoked purchases are ignored")
        let lifetime = NetminEntitlementLogic.evaluate([
            transaction(NetminProductID.yearly, expiration: later),
            transaction(NetminProductID.lifetime)
        ])
        check(lifetime.kind == .lifetime, "Lifetime access wins over subscription access")
        let owned = NetminEntitlementLogic.evaluate([
            transaction(NetminProductID.yearly, expiration: later, shared: true),
            transaction(NetminProductID.yearly, expiration: later.addingTimeInterval(-10))
        ])
        check(!owned.isFamilyShared, "An owned subscription wins over a shared subscription")
        var trial = NetminEntitlementLogic.evaluate([
            transaction(NetminProductID.yearly, expiration: later, trial: true)
        ])
        trial.willAutoRenew = true
        check(NetminEntitlementLogic.statusKind(for: trial, now: now) == .trialRenews(later),
              "A renewing trial reports its first payment date")
        trial.willAutoRenew = false
        check(NetminEntitlementLogic.statusKind(for: trial, now: now) == .trialEnds(later),
              "A cancelled trial reports its end date")
        print("Netmin trial, Free allowance, and Pro entitlement decisions passed")
    }
}
