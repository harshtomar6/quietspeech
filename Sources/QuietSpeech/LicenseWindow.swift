import SwiftUI
import AppKit
import Licensing

@MainActor
final class LicenseWindowController: NSObject, NSWindowDelegate {
    static let shared = LicenseWindowController()

    private var licenseWindow: NSWindow?

    func present(model: AppModel) {
        if let licenseWindow {
            NSApp.activate(ignoringOtherApps: true)
            licenseWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = LicenseGateView(license: model.license) { [weak self] in
            self?.close()
        }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "QuietSpeech License"
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 560))
        window.center()
        window.delegate = self

        licenseWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        licenseWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        licenseWindow = nil
    }
}

struct LicenseGateView: View {
    @Bindable var license: LicenseService
    var close: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            SettingsDivider()
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 14) {
                status
                activation
                purchase
                message
            }
            .padding(.top, 18)

            Spacer(minLength: 14)

            footer
        }
        .padding(.horizontal, 26)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 460, height: 560)
        .background(SettingsColor.window)
        .tint(SettingsColor.accent)
        .onChange(of: license.canUseApp) { _, canUse in
            if canUse { close() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SettingsColor.accentSoft)
                .frame(width: 50, height: 50)
                .overlay(
                    Image(nsImage: BrandMark.image(size: 30))
                        .renderingMode(.template)
                        .foregroundStyle(SettingsColor.accent)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SettingsColor.accent.opacity(0.14), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch license.status {
        case .needsVerification:
            return "Verify your license"
        case .invalid:
            return "License needed"
        default:
            return "Activate QuietSpeech"
        }
    }

    private var subtitle: String {
        switch license.status {
        case .needsVerification:
            return "QuietSpeech is already licensed on this Mac. Reconnect to verify it."
        case .invalid:
            return "This license is no longer active. Enter a new key or buy QuietSpeech."
        default:
            return "Buy once, then enter your key to start dictating."
        }
    }

    // MARK: - Status

    private var status: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(symbol: statusSymbol, tint: statusTint, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(license.statusTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(license.statusDetail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if license.isBusy, let label = license.activityLabel {
                    Text(label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        }
    }

    private var statusSymbol: String {
        switch license.status {
        case .needsVerification: return "wifi.exclamationmark"
        case .invalid: return "exclamationmark.triangle.fill"
        default: return "key"
        }
    }

    private var statusTint: Color {
        switch license.statusTone {
        case .green: return SettingsColor.green
        case .amber: return SettingsColor.amber
        case .accent: return SettingsColor.accent
        case .neutral: return SettingsColor.faintText
        }
    }

    // MARK: - Form

    private var activation: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Have a license key?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            SettingsCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        SettingsField(
                            placeholder: "XXXX-XXXX-XXXX-XXXX",
                            text: $license.keyInput
                        )
                        .onSubmit { activate() }

                        Button {
                            activate()
                        } label: {
                            Text("Activate")
                                .foregroundStyle(SettingsColor.onAccent)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SettingsColor.accentFill)
                        .controlSize(.small)
                        .disabled(license.isBusy || trimmedKey.isEmpty)
                    }

                    if case .needsVerification = license.status {
                        Button("Try again") {
                            Task { await license.refresh() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(license.isBusy)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
            }
        }
    }

    private var purchase: some View {
        HStack(spacing: 8) {
            if let checkout = license.purchaseURL {
                Button {
                    openURL(checkout)
                } label: {
                    Text("Buy QuietSpeech")
                        .foregroundStyle(SettingsColor.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(SettingsColor.accentFill)
                .controlSize(.regular)
            }

            if let portal = license.portalURL {
                Button("Manage devices") { openURL(portal) }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var message: some View {
        if let text = license.message {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: license.messageIsError
                      ? "exclamationmark.triangle.fill"
                      : "checkmark.circle.fill")
                    .font(.system(size: 10.5))
                Text(text)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(license.messageIsError ? SettingsColor.amber : SettingsColor.green)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.regular)
            .keyboardShortcut("q")
        }
    }

    // MARK: - Actions

    private var trimmedKey: String {
        license.keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func activate() {
        guard !trimmedKey.isEmpty, !license.isBusy else { return }
        Task { await license.activate() }
    }
}
