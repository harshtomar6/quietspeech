import Foundation

public struct LicenseConfiguration: Sendable {
    public var organizationID: String
    public var checkoutURL: URL?
    public var portalURL: URL?
    public var apiBaseURL: URL
    public var offlineGraceDays: Int
    /// Length of the free trial for unlicensed Macs; 0 turns it off.
    public var trialDays: Int

    public init(
        organizationID: String,
        checkoutURL: URL? = nil,
        portalURL: URL? = nil,
        apiBaseURL: URL = URL(string: "https://api.polar.sh")!,
        offlineGraceDays: Int = 14,
        trialDays: Int = 7
    ) {
        self.organizationID = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.checkoutURL = checkoutURL
        self.portalURL = portalURL
        self.apiBaseURL = apiBaseURL
        self.offlineGraceDays = max(0, offlineGraceDays)
        self.trialDays = max(0, trialDays)
    }

    public var isConfigured: Bool { !organizationID.isEmpty }

    public static var current: LicenseConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let organizationID = environment["QUIETSPEECH_POLAR_ORG_ID"]
            ?? Self.sellerOrganizationID
        let checkoutURL = URL(
            string: environment["QUIETSPEECH_POLAR_CHECKOUT_URL"]
                ?? Self.sellerCheckoutURL
        )
        let portalURL = URL(
            string: environment["QUIETSPEECH_POLAR_PORTAL_URL"]
                ?? Self.sellerPortalURL
        )
        let apiBaseURL = URL(
            string: environment["QUIETSPEECH_POLAR_API_BASE"]
                ?? "https://api.polar.sh"
        ) ?? URL(string: "https://api.polar.sh")!
        let offlineGraceDays = environment["QUIETSPEECH_OFFLINE_GRACE_DAYS"]
            .flatMap(Int.init)
            ?? 14
        let trialDays = environment["QUIETSPEECH_TRIAL_DAYS"]
            .flatMap(Int.init)
            ?? 7

        return LicenseConfiguration(
            organizationID: organizationID,
            checkoutURL: checkoutURL,
            portalURL: portalURL,
            apiBaseURL: apiBaseURL,
            offlineGraceDays: offlineGraceDays,
            trialDays: trialDays
        )
    }

    // MARK: - Seller configuration

    private static let sellerOrganizationID = "fd63ec1f-0a96-4da9-a046-d48ae69ea34d"
    private static let sellerCheckoutURL = "https://buy.polar.sh/polar_cl_8ooBh11wmw9UodSY2imkMg5OV1WTig6pmp79q2Hr3FQ"
    private static let sellerPortalURL = "https://polar.sh/momentum-apps/portal"
}
