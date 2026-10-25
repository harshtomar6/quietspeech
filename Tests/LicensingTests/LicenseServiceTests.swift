import XCTest
@testable import Licensing

@MainActor
final class LicenseServiceTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let store = MemoryLicenseStore()
    private let api = MockAPI()

    func testUnconfiguredBuildDoesNotEnforceLicense() {
        let service = makeService(configured: false)

        XCTAssertTrue(service.canUseApp)
        guard case .unconfigured = service.status else {
            return XCTFail("Expected unconfigured status")
        }
    }

    func testConfiguredBuildRequiresActivation() {
        let service = makeService()

        XCTAssertFalse(service.canUseApp)
        guard case .unlicensed = service.status else {
            return XCTFail("Expected unlicensed status")
        }

        let relaunched = makeService()
        guard case .unlicensed = relaunched.status else {
            return XCTFail("Unlicensed status should survive relaunch")
        }
        XCTAssertFalse(relaunched.canUseApp)
    }

    func testActivationPersistsLicenseDetails() async {
        let service = makeService()
        XCTAssertFalse(service.canUseApp)
        service.keyInput = "  TEST-KEY-1234  "
        await service.activate()

        XCTAssertTrue(service.canUseApp)
        XCTAssertTrue(service.isLicensed)
        XCTAssertEqual(service.messageIsError, false)
        XCTAssertEqual(store.string(for: "license.key"), "TEST-KEY-1234")
        XCTAssertEqual(store.string(for: "license.activationID"), "activation-1")
        XCTAssertEqual(api.activateCallCount, 1)
    }

    func testLicenseRemainsUsableOfflineWithinGrace() async {
        seedLicense(lastValidatedAt: now)
        now = now.addingTimeInterval(5 * 86_400)
        api.validationError = LicenseAPIError.network("offline")

        let service = makeService(graceDays: 14)
        XCTAssertTrue(service.canUseApp)
        await service.refresh()

        XCTAssertTrue(service.canUseApp)
        XCTAssertTrue(service.isLicensed)
        XCTAssertTrue(service.isOffline)
    }

    func testLicenseNeedsVerificationAfterGrace() async {
        seedLicense(lastValidatedAt: now)
        now = now.addingTimeInterval(20 * 86_400)
        api.validationError = LicenseAPIError.network("offline")

        let service = makeService(graceDays: 14)
        XCTAssertFalse(service.canUseApp)
        guard case .needsVerification = service.status else {
            return XCTFail("Expected verification state")
        }

        await service.refresh()
        XCTAssertFalse(service.canUseApp)
    }

    func testDefinitiveValidationFailureInvalidatesStoredLicense() async {
        seedLicense(lastValidatedAt: now)
        now = now.addingTimeInterval(86_400)
        api.validationError = LicenseAPIError.invalidKey

        let service = makeService(graceDays: 14)
        await service.refresh()

        XCTAssertFalse(service.canUseApp)
        guard case .invalid = service.status else {
            return XCTFail("Expected invalid status")
        }

        let relaunched = makeService(graceDays: 14)
        guard case .invalid = relaunched.status else {
            return XCTFail("Invalid reason should survive relaunch")
        }
    }

    func testNetworkFailureDoesNotUndoInvalidLicense() async {
        seedLicense(lastValidatedAt: now)
        now = now.addingTimeInterval(86_400)
        api.validationError = LicenseAPIError.invalidKey

        let service = makeService(graceDays: 14)
        await service.refresh()
        guard case .invalid = service.status else {
            return XCTFail("Expected invalid status")
        }

        api.validationError = LicenseAPIError.network("offline")
        now = now.addingTimeInterval(86_400)
        await service.refresh()

        guard case .invalid = service.status else {
            return XCTFail("Network failure must not restore an invalid license")
        }
        XCTAssertFalse(service.canUseApp)
    }

    func testDeactivationClearsLocalLicenseEvenWhenServerFails() async {
        seedLicense(lastValidatedAt: now)
        api.deactivateError = LicenseAPIError.network("offline")

        let service = makeService(graceDays: 14)
        await service.deactivate()

        XCTAssertNil(store.string(for: "license.key"))
        XCTAssertNil(store.string(for: "license.activationID"))
        XCTAssertTrue(service.messageIsError)
    }

    func testExpiredStoredLicenseIsInvalidBeforeNetwork() {
        seedLicense(
            lastValidatedAt: now.addingTimeInterval(-86_400),
            expiresAt: now.addingTimeInterval(-3_600)
        )
        let service = makeService(graceDays: 14)

        XCTAssertFalse(service.canUseApp)
        guard case .invalid = service.status else {
            return XCTFail("Expected expired license to be invalid")
        }
    }

    // MARK: - Helpers

    private func makeService(
        configured: Bool = true,
        graceDays: Int = 14
    ) -> LicenseService {
        let configuration = LicenseConfiguration(
            organizationID: configured ? "test-org" : "",
            checkoutURL: URL(string: "https://example.com/buy"),
            portalURL: URL(string: "https://example.com/portal"),
            apiBaseURL: URL(string: "https://api.polar.sh")!,
            offlineGraceDays: graceDays
        )
        return LicenseService(
            configuration: configuration,
            store: store,
            api: api,
            now: { [weak self] in self?.now ?? Date() }
        )
    }

    private func seedLicense(
        lastValidatedAt: Date?,
        expiresAt: Date? = nil
    ) {
        store.set("TEST-KEY-1234", for: "license.key")
        store.set("activation-1", for: "license.activationID")
        store.set("test-mac", for: "license.activationLabel")
        store.set("granted", for: "license.status")
        if let lastValidatedAt {
            store.set(isoString(lastValidatedAt), for: "license.lastValidatedAt")
        }
        if let expiresAt {
            store.set(isoString(expiresAt), for: "license.expiresAt")
        }
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private final class MockAPI: LicenseAPI, @unchecked Sendable {
    var activateCallCount = 0
    var validateCallCount = 0
    var deactivateCallCount = 0

    var activateError: Error?
    var validationError: Error?
    var deactivateError: Error?

    var activation = LicenseActivation(
        activationID: "activation-1",
        key: "TEST-KEY-1234",
        displayKey: "****-1234",
        status: "granted",
        limitActivations: 3
    )
    var validation = LicenseValidation(
        status: "granted",
        activationID: "activation-1",
        limitActivations: 3
    )

    func activate(
        key: String,
        label: String,
        meta: [String: String]
    ) async throws -> LicenseActivation {
        activateCallCount += 1
        if let activateError { throw activateError }
        return activation
    }

    func validate(
        key: String,
        activationID: String
    ) async throws -> LicenseValidation {
        validateCallCount += 1
        if let validationError { throw validationError }
        return validation
    }

    func deactivate(key: String, activationID: String) async throws {
        deactivateCallCount += 1
        if let deactivateError { throw deactivateError }
    }
}
