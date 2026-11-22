import AppKit

/// Apps whose text fields are Chromium web views: Electron apps, and apps
/// built on the Chromium Embedded Framework (CEF), such as the Yab browser.
/// Their Accessibility bridge reports success for writes it silently drops,
/// so insertion and selection treat them like web browsers.
enum ChromiumShell: String {
    case electron
    case cef = "chromium"

    private static let frameworks: [(name: String, kind: ChromiumShell)] = [
        ("Electron Framework.framework", .electron),
        ("Chromium Embedded Framework.framework", .cef),
    ]

    static func kind(of app: NSRunningApplication) -> ChromiumShell? {
        app.bundleURL.flatMap(kind(ofBundleAt:))
    }

    static func kind(ofBundleAt bundleURL: URL) -> ChromiumShell? {
        let directory = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Frameworks")
        return frameworks.first { entry in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.name).path)
        }?.kind
    }
}
