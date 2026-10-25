import Foundation

public struct LicenseDetails: Equatable, Sendable {
    public var key: String
    public var displayKey: String?
    public var activationID: String
    public var activationLabel: String
    public var lastValidatedAt: Date?
    public var expiresAt: Date?
    public var limitActivations: Int?
    public var licenseStatus: String

    public init(
        key: String,
        displayKey: String? = nil,
        activationID: String,
        activationLabel: String,
        lastValidatedAt: Date? = nil,
        expiresAt: Date? = nil,
        limitActivations: Int? = nil,
        licenseStatus: String = "granted"
    ) {
        self.key = key
        self.displayKey = displayKey
        self.activationID = activationID
        self.activationLabel = activationLabel
        self.lastValidatedAt = lastValidatedAt
        self.expiresAt = expiresAt
        self.limitActivations = limitActivations
        self.licenseStatus = licenseStatus
    }

    public var maskedKey: String {
        if let displayKey, !displayKey.isEmpty { return displayKey }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "••••" }
        return "\(trimmed.prefix(4))…\(trimmed.suffix(4))"
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public struct LicenseActivation: Equatable, Sendable {
    public let activationID: String
    public let key: String
    public let displayKey: String?
    public let status: String
    public let limitActivations: Int?
    public let expiresAt: Date?

    public init(
        activationID: String,
        key: String,
        displayKey: String? = nil,
        status: String = "granted",
        limitActivations: Int? = nil,
        expiresAt: Date? = nil
    ) {
        self.activationID = activationID
        self.key = key
        self.displayKey = displayKey
        self.status = status
        self.limitActivations = limitActivations
        self.expiresAt = expiresAt
    }
}

public struct LicenseValidation: Equatable, Sendable {
    public let status: String
    public let activationID: String?
    public let limitActivations: Int?
    public let expiresAt: Date?

    public init(
        status: String = "granted",
        activationID: String? = nil,
        limitActivations: Int? = nil,
        expiresAt: Date? = nil
    ) {
        self.status = status
        self.activationID = activationID
        self.limitActivations = limitActivations
        self.expiresAt = expiresAt
    }
}

public enum LicenseTone: Sendable {
    case green
    case amber
    case accent
    case neutral
}

public enum LicenseActivity: Equatable, Sendable {
    case idle
    case activating
    case verifying
    case deactivating
}

public enum LicenseStatus: Equatable, Sendable {
    case unconfigured
    case unlicensed
    case licensed(LicenseDetails)
    case needsVerification(LicenseDetails)
    case invalid(String)
}
