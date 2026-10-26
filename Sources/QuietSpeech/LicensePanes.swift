import SwiftUI
import AppKit
import Licensing

struct LicensePane: View {
    @Bindable var license: LicenseService
    @Environment(\.openURL) private var openURL
    @State private var confirmDeactivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsPaneHeader(
                title: "License",
                subtitle: "Buy once. Activate this Mac with your key.",
                pill: SettingsStatusPill(text: license.overviewStatus, tone: tone)
            )
            .padding(.bottom, 2)

            statusCard

            if license.isConfigured {
                if license.isLicensed {
                    licensedCard
                } else {
                    activationCard
                }
            } else {
                configurationCard
            }

            if license.isConfigured, !license.isLicensed {
                purchaseCard
            }
        }
    }

    // MARK: - Status

    private var tone: SettingsStatusPill.Tone {
        switch license.statusTone {
        case .green: return .green
        case .amber: return .amber
        case .accent: return .accent
        case .neutral: return .neutral
        }
    }

    private var statusSymbol: String {
        switch license.status {
        case .unconfigured: return "questionmark.circle"
        case .unlicensed: return "key"
        case .licensed: return "checkmark.seal.fill"
        case .needsVerification: return "wifi.exclamationmark"
        case .invalid: return "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch license.statusTone {
        case .green: return SettingsColor.green
        case .amber: return SettingsColor.amber
        case .accent: return Color.accentColor
        case .neutral: return SettingsColor.faintText
        }
    }

    private var statusCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(symbol: statusSymbol, tint: statusTint, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(license.statusTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(license.statusDetail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                if license.isBusy, let label = license.activityLabel {
                    Text(label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Licensed

    private var licensedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("This Mac")

            SettingsCard {
                if let details = license.storedDetails {
                    SettingsRow("License key", subtitle: details.maskedKey) {
                        SettingsStatusPill(text: "Active", tone: .green)
                    }

                    SettingsDivider()

                    SettingsRow("Activation", subtitle: details.activationLabel.isEmpty ? "This Mac" : details.activationLabel) {
                        HStack(spacing: 0) {
                            if let checked = details.lastValidatedAt {
                                Text(relative(checked))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SettingsDivider()

                    SettingsRow("Manage", subtitle: "Move this license to another Mac, or deactivate this one.") {
                        HStack(spacing: 7) {
                            if let portal = license.portalURL {
                                Button("Devices") { openURL(portal) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                            Button("Deactivate") { confirmDeactivate = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(SettingsColor.red)
                                .disabled(license.isBusy)
                        }
                    }
                }
            }

            if license.isOffline {
                SettingsNote("The last verification failed, but this Mac is still inside the offline grace period.", icon: "wifi.slash")
                    .padding(.horizontal, 2)
            }
        }
        .confirmationDialog("Deactivate this Mac?", isPresented: $confirmDeactivate) {
            Button("Deactivate", role: .destructive) {
                Task { await license.deactivate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees the activation so you can use the same key on another Mac.")
        }
    }

    // MARK: - Activation

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(license.isLicensed ? "License" : "Have a key?")

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste the key from your QuietSpeech receipt. One key can be activated on the number of Macs shown at checkout.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(license.isBusy || trimmedKey.isEmpty)

                        if license.activity == .activating {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let message = license.message {
                        messageRow(message, isError: license.messageIsError)
                    }

                    if case .needsVerification = license.status {
                        HStack(spacing: 7) {
                            Button("Try again") {
                                Task { await license.refresh() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(license.isBusy)
                        }
                    }

                    if case .invalid = license.status {
                        HStack(spacing: 7) {
                            Button("Remove from this Mac") {
                                license.removeLocalLicense()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(SettingsColor.red)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Purchase

    private var purchaseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("Buy")

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        SettingsIconTile(symbol: "cart", tint: Color.accentColor, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QuietSpeech")
                                .font(.system(size: 13, weight: .medium))
                            Text("A one-time purchase. No subscription, no account, and no telemetry.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        if let checkout = license.purchaseURL {
                            Button {
                                openURL(checkout)
                            } label: {
                                Text("Buy QuietSpeech")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        if let portal = license.portalURL {
                            Button("Manage devices") { openURL(portal) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Configuration

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("Setup")

            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Licensing is not configured in this build.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add your Polar organization ID and checkout URL in Sources/Licensing/LicenseConfiguration.swift, then rebuild. Until then the app runs without a license check.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Pieces

    private var trimmedKey: String {
        license.keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func activate() {
        guard !trimmedKey.isEmpty, !license.isBusy else { return }
        Task { await license.activate() }
    }

    private func messageRow(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10.5))
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(isError ? SettingsColor.amber : SettingsColor.green)
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
