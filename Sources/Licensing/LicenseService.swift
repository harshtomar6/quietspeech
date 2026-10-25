import Foundation
import Observation

@MainActor
@Observable
public final class LicenseService {
    public private(set) var status: LicenseStatus
    public private(set) var activity: LicenseActivity = .idle
    public private(set) var message: String?
    public private(set) var messageIsError = false
    public private(set) var isOffline = false
    public private(set) var lastCheckedAt: Date?
    public var keyInput = ""

    public let configuration: LicenseConfiguration

    private let store: LicenseStore
    private let api: LicenseAPI
    private let now: () -> Date
    private var refreshTask: Task<Void, Never>?

    public init(
        configuration: LicenseConfiguration = .current,
        store: LicenseStore = KeychainLicenseStore(),
        api: LicenseAPI? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.store = store
        self.api = api ?? PolarLicenseClient(configuration: configuration)
        self.now = now
        self.status = Self.localStatus(
            configuration: configuration,
            store: store,
            now: now()
        )
    }

    // MARK: - Public state

    public var isConfigured: Bool { configuration.isConfigured }

    public var canUseApp: Bool {
        guard configuration.isConfigured else { return true }
        switch status {
        case .licensed, .unconfigured:
            return true
        case .unlicensed, .needsVerification, .invalid:
            return false
        }
    }

    public var isLicensed: Bool {
        if case .licensed = status { return true }
        return false
    }

    public var isBusy: Bool { activity != .idle }

    public var storedDetails: LicenseDetails? {
        switch status {
        case .licensed(let details), .needsVerification(let details):
            return details
        default:
            return nil
        }
    }

    public var purchaseURL: URL? { configuration.checkoutURL }
    public var portalURL: URL? { configuration.portalURL }

    public var statusTitle: String {
        switch status {
        case .unconfigured:
            return "Licensing not configured"
        case .unlicensed:
            return "License required"
        case .licensed:
            return "Licensed"
        case .needsVerification:
            return "Verification needed"
        case .invalid:
            return "License invalid"
        }
    }

    public var statusDetail: String {
        switch status {
        case .unconfigured:
            return "Add a Polar organization ID to this build before selling it."
        case .unlicensed:
            return "Buy a one-time license, then activate this Mac with your key."
        case .licensed(let details):
            if isOffline {
                let checked = details.lastValidatedAt.map(Self.relative) ?? "earlier"
                return "Offline. Last verified \(checked)."
            }
            if let checked = details.lastValidatedAt {
                return "One-time license · verified \(Self.relative(checked))."
            }
            return "One-time license on this Mac."
        case .needsVerification:
            return "Connect to the internet so this Mac can verify its license."
        case .invalid(let reason):
            return reason
        }
    }

    public var statusTone: LicenseTone {
        switch status {
        case .unconfigured:
            return .neutral
        case .unlicensed:
            return .accent
        case .licensed:
            return .green
        case .needsVerification, .invalid:
            return .amber
        }
    }

    public var overviewStatus: String {
        switch status {
        case .unconfigured:
            return "Not configured"
        case .unlicensed:
            return "Not activated"
        case .licensed:
            return "Licensed"
        case .needsVerification:
            return "Verify"
        case .invalid:
            return "Invalid"
        }
    }

    public var overviewDetail: String {
        switch status {
        case .unconfigured:
            return "Licensing is disabled in this build"
        case .unlicensed:
            return "Buy once, then activate this Mac"
        case .licensed(let details):
            return "This Mac · \(details.maskedKey)"
        case .needsVerification:
            return "Reconnect to verify this Mac"
        case .invalid:
            return "Replace the license key"
        }
    }

    public var activityLabel: String? {
        switch activity {
        case .idle: return nil
        case .activating: return "Activating…"
        case .verifying: return "Verifying…"
        case .deactivating: return "Deactivating…"
        }
    }

    public var blockingMessage: String {
        switch status {
        case .unlicensed:
            return "Activate QuietSpeech with a license key to start dictating."
        case .needsVerification:
            return "Connect to the internet so QuietSpeech can verify your license."
        case .invalid(let reason):
            return reason
        case .unconfigured, .licensed:
            return "QuietSpeech needs a valid license to dictate."
        }
    }

    // MARK: - Checks

    public func beginPeriodicChecks() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12 * 60 * 60))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    public func refresh() async {
        guard configuration.isConfigured else {
            status = .unconfigured
            return
        }
        guard activity == .idle else { return }
        guard let details = loadedDetails() else {
            status = Self.localStatus(
                configuration: configuration,
                store: store,
                now: now()
            )
            return
        }

        activity = .verifying
        defer { activity = .idle }

        do {
            let validation = try await api.validate(
                key: details.key,
                activationID: details.activationID
            )
            var updated = details
            updated.lastValidatedAt = now()
            updated.expiresAt = validation.expiresAt ?? updated.expiresAt
            updated.limitActivations = validation.limitActivations ?? updated.limitActivations
            updated.licenseStatus = validation.status
            if let label = store.string(for: Field.activationLabel.rawValue), !label.isEmpty {
                updated.activationLabel = label
            }
            persist(updated)
            status = .licensed(updated)
            isOffline = false
            lastCheckedAt = now()
            message = nil
        } catch let error as LicenseAPIError {
            handleValidationFailure(error, details: details)
        } catch {
            handleValidationFailure(
                .network(error.localizedDescription),
                details: details
            )
        }
    }

    public func activate() async {
        await activate(key: keyInput)
    }

    public func activate(key: String) async {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            message = "Enter a license key first."
            messageIsError = true
            return
        }
        guard configuration.isConfigured else {
            message = LicenseAPIError.notConfigured.localizedDescription
            messageIsError = true
            return
        }
        guard activity == .idle else {
            message = "Still checking this license. Try again in a moment."
            messageIsError = true
            return
        }

        if let existing = loadedDetails(),
           existing.key.caseInsensitiveCompare(normalized) == .orderedSame {
            keyInput = ""
            await refresh()
            return
        }

        activity = .activating
        defer { activity = .idle }

        do {
            let activation = try await api.activate(
                key: normalized,
                label: Self.deviceLabel,
                meta: Self.deviceMeta
            )
            let details = LicenseDetails(
                key: normalized,
                displayKey: activation.displayKey,
                activationID: activation.activationID,
                activationLabel: Self.deviceLabel,
                lastValidatedAt: now(),
                expiresAt: activation.expiresAt,
                limitActivations: activation.limitActivations,
                licenseStatus: activation.status
            )
            persist(details)
            status = .licensed(details)
            isOffline = false
            lastCheckedAt = now()
            keyInput = ""
            message = "Activated. This Mac is licensed."
            messageIsError = false
        } catch let error as LicenseAPIError {
            message = error.localizedDescription
            messageIsError = true
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    public func deactivate() async {
        guard let details = loadedDetails() else { return }
        guard activity == .idle else {
            message = "Still checking this license. Try again in a moment."
            messageIsError = true
            return
        }

        activity = .deactivating
        defer { activity = .idle }

        var deactivationError: Error?
        do {
            try await api.deactivate(
                key: details.key,
                activationID: details.activationID
            )
        } catch {
            deactivationError = error
        }

        clearStoredLicense()
        status = Self.localStatus(
            configuration: configuration,
            store: store,
            now: now()
        )
        isOffline = false
        lastCheckedAt = now()

        if let deactivationError {
            message = "Removed this Mac. The server couldn’t be reached, so free the device in the customer portal if needed. \(deactivationError.localizedDescription)"
            messageIsError = true
        } else {
            message = "Deactivated this Mac. The same key can be used again later."
            messageIsError = false
        }
    }

    public func removeLocalLicense() {
        clearStoredLicense()
        status = Self.localStatus(
            configuration: configuration,
            store: store,
            now: now()
        )
        message = "Removed the license from this Mac."
        messageIsError = false
    }

    public func clearMessage() {
        message = nil
        messageIsError = false
    }

    // MARK: - Validation handling

    private func handleValidationFailure(
        _ error: LicenseAPIError,
        details: LicenseDetails
    ) {
        messageIsError = true
        if error.isDefinitiveFailure {
            store.set(error.localizedDescription, for: Field.invalidReason.rawValue)
            status = .invalid(error.localizedDescription)
            isOffline = false
            message = error.localizedDescription
            return
        }

        if let reason = store.string(for: Field.invalidReason.rawValue),
           !reason.isEmpty {
            status = .invalid(reason)
            isOffline = false
            message = reason
            return
        }

        if withinGrace(details) {
            var offline = details
            if offline.activationLabel.isEmpty {
                offline.activationLabel = Self.deviceLabel
            }
            status = .licensed(offline)
            isOffline = true
            message = nil
        } else {
            status = .needsVerification(details)
            isOffline = false
            message = "Connect to the internet to verify this license."
        }
    }

    private func withinGrace(_ details: LicenseDetails) -> Bool {
        guard let last = details.lastValidatedAt else { return false }
        let elapsed = now().timeIntervalSince(last)
        return elapsed <= Double(configuration.offlineGraceDays) * 86_400
    }

    // MARK: - Persistence

    private enum Field: String {
        case key = "license.key"
        case displayKey = "license.displayKey"
        case activationID = "license.activationID"
        case activationLabel = "license.activationLabel"
        case lastValidatedAt = "license.lastValidatedAt"
        case expiresAt = "license.expiresAt"
        case limitActivations = "license.limitActivations"
        case licenseStatus = "license.status"
        case invalidReason = "license.invalidReason"
    }

    private func loadedDetails() -> LicenseDetails? {
        Self.storedDetails(store: store)
    }

    private func persist(_ details: LicenseDetails) {
        store.set(details.key, for: Field.key.rawValue)
        store.set(details.displayKey, for: Field.displayKey.rawValue)
        store.set(details.activationID, for: Field.activationID.rawValue)
        store.set(details.activationLabel, for: Field.activationLabel.rawValue)
        store.set(details.lastValidatedAt.map(Self.isoString), for: Field.lastValidatedAt.rawValue)
        store.set(details.expiresAt.map(Self.isoString), for: Field.expiresAt.rawValue)
        store.set(details.limitActivations.map(String.init), for: Field.limitActivations.rawValue)
        store.set(details.licenseStatus, for: Field.licenseStatus.rawValue)
        store.set(nil, for: Field.invalidReason.rawValue)
    }

    private func clearStoredLicense() {
        for field in [
            Field.key, .displayKey, .activationID, .activationLabel,
            .lastValidatedAt, .expiresAt, .limitActivations, .licenseStatus,
            .invalidReason,
        ] {
            store.set(nil, for: field.rawValue)
        }
    }

    private static func storedDetails(store: LicenseStore) -> LicenseDetails? {
        guard let key = store.string(for: Field.key.rawValue), !key.isEmpty,
              let activationID = store.string(for: Field.activationID.rawValue),
              !activationID.isEmpty else {
            return nil
        }

        return LicenseDetails(
            key: key,
            displayKey: store.string(for: Field.displayKey.rawValue),
            activationID: activationID,
            activationLabel: store.string(for: Field.activationLabel.rawValue) ?? "",
            lastValidatedAt: store.string(for: Field.lastValidatedAt.rawValue).flatMap(parseDate),
            expiresAt: store.string(for: Field.expiresAt.rawValue).flatMap(parseDate),
            limitActivations: store.string(for: Field.limitActivations.rawValue).flatMap(Int.init),
            licenseStatus: store.string(for: Field.licenseStatus.rawValue) ?? "granted"
        )
    }

    private static func localStatus(
        configuration: LicenseConfiguration,
        store: LicenseStore,
        now: Date
    ) -> LicenseStatus {
        guard configuration.isConfigured else { return .unconfigured }

        if let details = storedDetails(store: store) {
            if let reason = store.string(for: Field.invalidReason.rawValue),
               !reason.isEmpty {
                return .invalid(reason)
            }
            if details.licenseStatus != "granted" {
                return .invalid("This license is no longer active.")
            }
            if let expiresAt = details.expiresAt, expiresAt <= now {
                return .invalid("This license has expired.")
            }
            if let last = details.lastValidatedAt,
               now.timeIntervalSince(last) <= Double(configuration.offlineGraceDays) * 86_400 {
                return .licensed(details)
            }
            return .needsVerification(details)
        }

        return .unlicensed
    }

    // MARK: - Device

    private static var deviceLabel: String {
        let host = ProcessInfo.processInfo.hostName
        let trimmed = host.hasSuffix(".local")
            ? String(host.dropLast(".local".count))
            : host
        return trimmed.isEmpty ? "This Mac" : trimmed
    }

    private static var deviceMeta: [String: String] {
        [
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
    }

    // MARK: - Dates

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
