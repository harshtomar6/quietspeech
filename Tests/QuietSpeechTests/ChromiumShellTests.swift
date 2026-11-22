import XCTest
@testable import QuietSpeech

final class ChromiumShellTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChromiumShellTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeBundle(_ name: String, framework: String?) throws -> URL {
        let bundle = root.appendingPathComponent("\(name).app")
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        if let framework {
            try FileManager.default.createDirectory(at: frameworks.appendingPathComponent(framework),
                                                    withIntermediateDirectories: true)
        }
        return bundle
    }

    func testDetectsElectronApps() throws {
        let bundle = try makeBundle("Orca", framework: "Electron Framework.framework")
        XCTAssertEqual(ChromiumShell.kind(ofBundleAt: bundle), .electron)
    }

    func testDetectsChromiumEmbeddedFrameworkApps() throws {
        // The Yab browser ships CEF, not Electron, and drops AX writes.
        let bundle = try makeBundle("Yab", framework: "Chromium Embedded Framework.framework")
        XCTAssertEqual(ChromiumShell.kind(ofBundleAt: bundle), .cef)
        XCTAssertEqual(ChromiumShell.cef.rawValue, "chromium")
    }

    func testNativeAppsAreNotChromiumShells() throws {
        let bundle = try makeBundle("TextEdit", framework: "Sparkle.framework")
        XCTAssertNil(ChromiumShell.kind(ofBundleAt: bundle))
        XCTAssertNil(ChromiumShell.kind(ofBundleAt: root.appendingPathComponent("Missing.app")))
    }

    func testRealYabInstallIsDetectedWhenPresent() throws {
        let yab = URL(fileURLWithPath: "/Applications/yab.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: yab.path), "Yab not installed")
        XCTAssertEqual(ChromiumShell.kind(ofBundleAt: yab), .cef)
    }
}
