import SwiftUI
import AppKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case overview, license, activation, transcription, personalization, ai, output, history, permissions, privacy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .license: return "License"
        case .activation: return "Activation"
        case .transcription: return "Transcription"
        case .personalization: return "Personalization"
        case .ai: return "AI"
        case .output: return "Output"
        case .history: return "History"
        case .permissions: return "Permissions"
        case .privacy: return "Privacy"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .license: return "key"
        case .activation: return "command"
        case .transcription: return "waveform"
        case .personalization: return "text.book.closed"
        case .ai: return "sparkles"
        case .output: return "text.cursor"
        case .history: return "clock.arrow.circlepath"
        case .permissions: return "lock.shield"
        case .privacy: return "shield.lefthalf.filled"
        }
    }

    enum Group: String, CaseIterable {
        case general = "General"
        case dictation = "Dictation"
        case output = "Output"
        case intelligence = "Intelligence"
        case system = "System"

        var panes: [SettingsPane] {
            switch self {
            case .general: return [.overview, .license]
            case .dictation: return [.activation, .transcription, .personalization]
            case .output: return [.output, .history]
            case .intelligence: return [.ai]
            case .system: return [.permissions, .privacy]
            }
        }
    }

    var group: Group {
        switch self {
        case .overview, .license: return .general
        case .activation, .transcription, .personalization: return .dictation
        case .output, .history: return .output
        case .ai: return .intelligence
        case .permissions, .privacy: return .system
        }
    }

    var keywords: String {
        switch self {
        case .overview: return "home summary status ready dashboard"
        case .license: return "license key purchase buy activate deactivate polar payment"
        case .activation: return "shortcut hotkey hold fn tap key binding paste again"
        case .transcription: return "language cleanup context profile formatting code terminal email chat document"
        case .personalization: return "vocabulary replacements names jargon spelling learning corrections screen"
        case .ai: return "polish edit generate trigger transcription whisper audio provider apple intelligence foundation models endpoint model key groq openai ollama local connection"
        case .output: return "insertion clipboard overlay capsule card typing paste preview"
        case .history: return "recent dictations saved copy delete search"
        case .permissions: return "microphone accessibility grant recheck relaunch privacy security"
        case .privacy: return "data local storage capture files analytics keychain"
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = (label + " " + keywords).lowercased()
        return haystack.contains(query)
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var selectedPane: SettingsPane = .overview
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var filteredQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasSearchResults: Bool {
        SettingsPane.allCases.contains { $0.matches(filteredQuery) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(SettingsColor.border)
                .frame(width: 1)
            content
        }
        .frame(width: 942, height: 704)
        .background(SettingsColor.window)
        .onAppear {
            model.refreshPermissions()
            model.refreshCaptureStatus()
            applyRequestedPane()
            DispatchQueue.main.async { searchFocused = false }
        }
        .onChange(of: model.requestedSettingsPane) { _, _ in
            applyRequestedPane()
        }
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    // MARK: - Sidebar

    private var appIcon: NSImage {
        if let icon = NSApp.applicationIconImage { return icon }
        if let icon = NSImage(named: "AppIcon") { return icon }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { return icon }
        return BrandMark.image(size: 34)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("QuietSpeech")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 26)
            .padding(.bottom, 12)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SettingsPane.Group.allCases, id: \.self) { group in
                        let panes = group.panes.filter { $0.matches(filteredQuery) }
                        if !panes.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.rawValue.uppercased())
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .kerning(0.7)
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 10)
                                    .padding(.bottom, 4)

                                ForEach(panes) { pane in
                                    navItem(pane)
                                }
                            }
                        }
                    }

                    if !hasSearchResults {
                        Text("No settings found")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            sidebarFooter
        }
        .frame(width: 216)
        .background(SettingsColor.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search settings", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onExitCommand {
                    search = ""
                    searchFocused = false
                }

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text("\u{2318}K")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .frame(height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsColor.cardMuted)
                    )
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 29)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(SettingsColor.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(searchFocused ? SettingsColor.accent.opacity(0.65) : SettingsColor.border,
                              lineWidth: 1)
        )
    }

    private func navItem(_ pane: SettingsPane) -> some View {
        let isSelected = selectedPane == pane
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedPane = pane
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(pane.label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer(minLength: 4)
                if pane == .ai {
                    Text(aiBadgeText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? SettingsColor.sidebarSelectedText : .secondary)
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isSelected ? SettingsColor.sidebarSelectedText.opacity(0.16)
                                                 : SettingsColor.cardMuted)
                        )
                }
            }
            .foregroundStyle(isSelected ? SettingsColor.sidebarSelectedText : Color.primary.opacity(0.84))
            .padding(.horizontal, 9)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? SettingsColor.sidebarSelected : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var aiBadgeText: String {
        if model.aiReady { return model.aiProvider.badgeName }
        if model.aiConfigured { return "Off" }
        return "Off"
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsColor.border)
                .frame(height: 1)

            HStack(spacing: 6) {
                Circle()
                    .fill(footerTone)
                    .frame(width: 5, height: 5)
                Text(footerText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("v\(SettingsView.version)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
        }
    }

    private var footerTone: Color {
        if !model.microphoneGranted || !model.accessibilityGranted { return SettingsColor.amber }
        return model.aiReady ? SettingsColor.green : SettingsColor.faintText
    }

    private var footerText: String {
        if !model.microphoneGranted || !model.accessibilityGranted { return "Setup needed" }
        if model.aiReady {
            return model.aiRunsOnDevice
                ? "\(model.settingsProviderName) on-device"
                : "\(model.settingsProviderName) connected"
        }
        return "On-device only"
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private func applyRequestedPane() {
        guard let pane = model.requestedSettingsPane else { return }
        selectedPane = pane
        model.requestedSettingsPane = nil
    }

    // MARK: - Content

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 1).id("top")
                    paneContent
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                        .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.automatic)
            .background(SettingsColor.window)
            .onChange(of: selectedPane) { _, _ in
                proxy.scrollTo("top", anchor: .top)
                search = ""
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .overview:
            OverviewPane(model: model) { pane in
                withAnimation(.easeOut(duration: 0.12)) { selectedPane = pane }
            }
        case .license:
            LicensePane(license: model.license)
        case .activation:
            ActivationPane(model: model)
        case .transcription:
            TranscriptionPane(model: model)
        case .personalization:
            PersonalizationPane(model: model)
        case .ai:
            AIPane(model: model)
        case .output:
            OutputPane(model: model)
        case .history:
            HistoryPane(model: model)
        case .permissions:
            PermissionsPane(model: model)
        case .privacy:
            PrivacyPane(model: model) { pane in
                withAnimation(.easeOut(duration: 0.12)) { selectedPane = pane }
            }
        }
    }
}

extension AppModel {
    var settingsProviderName: String {
        aiProvider.name
    }

    var settingsProviderHost: String {
        if aiProvider == .apple { return "this Mac" }
        return URL(string: aiEndpoint)?.host ?? "your endpoint"
    }

    var settingsCaptureFileExists: Bool {
        FileManager.default.fileExists(atPath: Self.captureFileURL.path)
    }

    var settingsSetupComplete: Bool {
        microphoneGranted && accessibilityGranted
    }
}
