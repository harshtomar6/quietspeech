import Foundation

public enum LicenseAPIError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured
    case invalidKey
    case licenseLimit
    case revoked
    case expired
    case network(String)
    case server(status: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Licensing isn’t configured in this build."
        case .invalidKey:
            return "That license key wasn’t found. Check it and try again."
        case .licenseLimit:
            return "This key has reached its activation limit. Deactivate another Mac in the customer portal, then try again."
        case .revoked:
            return "This license is no longer active."
        case .expired:
            return "This license has expired."
        case .network:
            return "Couldn’t reach Polar. Check your connection and try again."
        case .server(_, let message):
            return message.isEmpty ? "Polar couldn’t complete the request." : message
        case .invalidResponse:
            return "Polar returned an unexpected response."
        }
    }

    public var isDefinitiveFailure: Bool {
        switch self {
        case .invalidKey, .licenseLimit, .revoked, .expired:
            return true
        case .server(let status, _):
            return (400..<500).contains(status)
                && status != 408
                && status != 429
        case .notConfigured, .network, .invalidResponse:
            return false
        }
    }
}

public protocol LicenseAPI: Sendable {
    func activate(key: String, label: String, meta: [String: String]) async throws -> LicenseActivation
    func validate(key: String, activationID: String) async throws -> LicenseValidation
    func deactivate(key: String, activationID: String) async throws
}

public struct PolarLicenseClient: LicenseAPI, @unchecked Sendable {
    private let configuration: LicenseConfiguration
    private let session: URLSession

    public init(
        configuration: LicenseConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    public func activate(
        key: String,
        label: String,
        meta: [String: String]
    ) async throws -> LicenseActivation {
        let body: [String: Any] = [
            "key": key,
            "organization_id": configuration.organizationID,
            "label": label,
            "conditions": [:],
            "meta": meta,
        ]
        let data = try await post(path: "v1/customer-portal/license-keys/activate", body: body)
        let response: ActivationResponse = try decode(data)

        guard response.licenseKey.status == "granted" else {
            throw LicenseAPIError.revoked
        }
        if let expiresAt = response.licenseKey.expiresAt, expiresAt <= Date() {
            throw LicenseAPIError.expired
        }

        return LicenseActivation(
            activationID: response.id,
            key: key,
            displayKey: response.licenseKey.displayKey,
            status: response.licenseKey.status,
            limitActivations: response.licenseKey.limitActivations,
            expiresAt: response.licenseKey.expiresAt
        )
    }

    public func validate(
        key: String,
        activationID: String
    ) async throws -> LicenseValidation {
        let body: [String: Any] = [
            "key": key,
            "organization_id": configuration.organizationID,
            "activation_id": activationID,
        ]
        let data = try await post(path: "v1/customer-portal/license-keys/validate", body: body)
        let response: ValidationResponse = try decode(data)

        guard response.status == "granted" else {
            throw LicenseAPIError.revoked
        }
        if let expiresAt = response.expiresAt, expiresAt <= Date() {
            throw LicenseAPIError.expired
        }

        return LicenseValidation(
            status: response.status,
            activationID: response.activation?.id,
            limitActivations: response.limitActivations,
            expiresAt: response.expiresAt
        )
    }

    public func deactivate(key: String, activationID: String) async throws {
        let body: [String: Any] = [
            "key": key,
            "organization_id": configuration.organizationID,
            "activation_id": activationID,
        ]
        _ = try await post(path: "v1/customer-portal/license-keys/deactivate", body: body)
    }

    // MARK: - HTTP

    private func post(path: String, body: [String: Any]) async throws -> Data {
        guard configuration.isConfigured else {
            throw LicenseAPIError.notConfigured
        }

        let url = configuration.apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw error(status: http.statusCode, data: data)
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = PolarDate.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO-8601 date."
                )
            }
            return date
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LicenseAPIError.invalidResponse
        }
    }

    private func error(status: Int, data: Data) -> LicenseAPIError {
        let message = Self.errorMessage(from: data)

        if status == 404 || status == 410 {
            return .invalidKey
        }
        if status == 403 {
            if message.range(of: "activation", options: .caseInsensitive) != nil
                || message.range(of: "limit", options: .caseInsensitive) != nil {
                return .licenseLimit
            }
            return .revoked
        }
        if status == 422 {
            return .invalidKey
        }
        if status == 429 {
            return .server(status: status, message: "Too many requests. Try again in a moment.")
        }
        if status >= 500 {
            return .server(status: status, message: message)
        }
        if message.range(of: "activation", options: .caseInsensitive) != nil
            || message.range(of: "limit", options: .caseInsensitive) != nil {
            return .licenseLimit
        }
        return .server(
            status: status,
            message: message.isEmpty ? "Polar returned an error (\(status))." : message
        )
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let detail = object["detail"] as? [[String: Any]],
           let message = detail.first?["msg"] as? String,
           !message.isEmpty {
            return message
        }
        if let message = object["error"] as? String, !message.isEmpty {
            return message
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return ""
    }
}

private enum PolarDate {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct ActivationResponse: Decodable {
    let id: String
    let licenseKey: LicenseKeyPayload

    enum CodingKeys: String, CodingKey {
        case id
        case licenseKey = "license_key"
    }
}

private struct LicenseKeyPayload: Decodable {
    let key: String?
    let displayKey: String?
    let status: String
    let limitActivations: Int?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case key
        case displayKey = "display_key"
        case status
        case limitActivations = "limit_activations"
        case expiresAt = "expires_at"
    }
}

private struct ValidationResponse: Decodable {
    let status: String
    let limitActivations: Int?
    let expiresAt: Date?
    let activation: ActivationPayload?

    enum CodingKeys: String, CodingKey {
        case status
        case limitActivations = "limit_activations"
        case expiresAt = "expires_at"
        case activation
    }
}

private struct ActivationPayload: Decodable {
    let id: String
}
