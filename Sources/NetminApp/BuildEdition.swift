import Foundation

// App identity is shared by public, App Store, and private local builds.
enum NetminEdition {
    static let bundleIdentifier = "tools.min.netmin"
    static let displayName = "Netmin"

    // Only the ignored private input can bypass verified access locally.
    #if NETMIN_LOCAL_BUILD && NETMIN_APP_STORE
    #error("Local access must not be included in an App Store build.")
    #elseif NETMIN_LOCAL_BUILD && NETMIN_EXPIRED_TRIAL_BUILD
    // Preview the public post-trial state without granting local Pro access.
    static let localProAccess: Bool? = nil
    static let localAccessStatus: String? = nil
    static let forcedTrialStartedAt: Date? = NetminLocalAccess.expiredTrialStartedAt
    static let isExpiredTrialPreview = true
    #elseif NETMIN_LOCAL_BUILD
    static let localProAccess: Bool? = NetminLocalAccess.isPro
    static let localAccessStatus: String? = NetminLocalAccess.status
    static let forcedTrialStartedAt: Date? = nil
    static let isExpiredTrialPreview = false
    #else
    // Public Debug and Release builds use the normal trial and purchase rules.
    static let localProAccess: Bool? = nil
    static let localAccessStatus: String? = nil
    static let forcedTrialStartedAt: Date? = nil
    static let isExpiredTrialPreview = false
    #endif
}

enum AppLinks {
    static let website = URL(string: "https://min.tools/netmin/")!
    static let privacyPolicy = URL(string: "https://min.tools/netmin/privacy/")!
    static let support = URL(string: "https://min.tools/netmin/support/")!
}
