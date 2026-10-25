import XCTest
@testable import Licensing

final class PolarLicenseClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testActivateSendsPolarRequestAndDecodesResponse() async throws {
        let client = makeClient()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/customer-portal/license-keys/activate")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(Self.bodyData(from: request))
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(object["key"] as? String, "TEST-KEY")
            XCTAssertEqual(object["organization_id"] as? String, "test-org")

            return (
                Self.response(status: 200),
                Self.json("""
                {
                  "id": "activation-1",
                  "license_key": {
                    "key": "TEST-KEY",
                    "display_key": "****-TEST",
                    "status": "granted",
                    "limit_activations": 3,
                    "expires_at": null
                  }
                }
                """)
            )
        }

        let activation = try await client.activate(
            key: "TEST-KEY",
            label: "test-mac",
            meta: ["app_version": "0.1"]
        )

        XCTAssertEqual(activation.activationID, "activation-1")
        XCTAssertEqual(activation.displayKey, "****-TEST")
        XCTAssertEqual(activation.limitActivations, 3)
    }

    func testValidateDecodesTopLevelLicenseKey() async throws {
        let client = makeClient()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/customer-portal/license-keys/validate")
            return (
                Self.response(status: 200),
                Self.json("""
                {
                  "status": "granted",
                  "limit_activations": 3,
                  "expires_at": "2030-01-01T00:00:00.000000Z",
                  "activation": { "id": "activation-1" }
                }
                """)
            )
        }

        let validation = try await client.validate(
            key: "TEST-KEY",
            activationID: "activation-1"
        )

        XCTAssertEqual(validation.status, "granted")
        XCTAssertEqual(validation.activationID, "activation-1")
        XCTAssertNotNil(validation.expiresAt)
    }

    func testMissingKeyBecomesInvalidKey() async {
        let client = makeClient()

        MockURLProtocol.handler = { _ in
            (
                Self.response(status: 404),
                Self.json(#"{"detail":"License key not found"}"#)
            )
        }

        do {
            _ = try await client.validate(key: "NOPE", activationID: "nothing")
            XCTFail("Expected an error")
        } catch let error as LicenseAPIError {
            XCTAssertEqual(error, .invalidKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testActivationLimitErrorIsMapped() async {
        let client = makeClient()

        MockURLProtocol.handler = { _ in
            (
                Self.response(status: 403),
                Self.json(#"{"detail":"License key activation limit reached"}"#)
            )
        }

        do {
            _ = try await client.activate(key: "TEST-KEY", label: "mac", meta: [:])
            XCTFail("Expected an error")
        } catch let error as LicenseAPIError {
            XCTAssertEqual(error, .licenseLimit)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeClient() -> PolarLicenseClient {
        let configuration = LicenseConfiguration(
            organizationID: "test-org",
            apiBaseURL: URL(string: "https://api.example.test")!
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        return PolarLicenseClient(configuration: configuration, session: session)
    }

    private static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.test")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func json(_ string: String) -> Data {
        Data(string.utf8)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
