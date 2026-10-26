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
    @FocusState private var sidebarFocused: Bool
    /// Panes visited before and after the current one, for Back and Forward.
    @State private var backStack: [SettingsPane] = []
    @State private var forwardStack: [SettingsPane] = []
    @State private var movingThroughHistory = false

    private var filteredQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasSearchResults: Bool {
        SettingsPane.allCases.contains { $0.matches(filteredQuery) }
    }

    var body: some View {
        // Native containers give the window macOS 26's Liquid Glass: a
        // floating sidebar, a glass search field and toolbar, and content that
        // scrolls under them.
        NavigationSplitView {
            sidebar
        } detail: {
            content
        }
        .frame(minWidth: 860, idealWidth: 942, minHeight: 600, idealHeight: 704)
        .onAppear {
            model.refreshPermissions()
            model.refreshCaptureStatus()
            model.refreshClipStatus()
            applyRequestedPane()
            clearInitialFocus()
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

    /// Fits "Personalization" and the AI badge.
    private static let sidebarWidth: CGFloat = 228

    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { selectedPane },
            set: { pane in
                guard let pane else { return }
                withAnimation(.easeOut(duration: 0.12)) { selectedPane = pane }
            }
        )
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(SettingsPane.Group.allCases, id: \.self) { group in
                let panes = group.panes.filter { $0.matches(filteredQuery) }
                if !panes.isEmpty {
                    Section(group.rawValue) {
                        ForEach(panes) { pane in
                            Label(pane.label, systemImage: pane.icon)
                                .badge(pane == .ai ? Text(aiBadgeText) : nil)
                                .tag(pane)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .focused($sidebarFocused)
        .overlay {
            if !hasSearchResults {
                Text("No settings found")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search settings")
        .searchFocused($searchFocused)
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
        // The column width alone is ignored on a first open (no saved split
        // view frame), which leaves a 148 pt sidebar with clipped labels, so
        // the list's own frame enforces it too.
        .frame(minWidth: Self.sidebarWidth, idealWidth: Self.sidebarWidth)
        .navigationSplitViewColumnWidth(min: Self.sidebarWidth, ideal: Self.sidebarWidth, max: 300)
        .toolbar(removing: .sidebarToggle)
    }

    private var aiBadgeText: String {
        if model.aiReady { return model.aiProvider.badgeName }
        if model.aiConfigured { return "Off" }
        return "Off"
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
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

    /// AppKit focuses the first text field when a window or pane opens,
    /// which puts a focus ring on a field nobody chose to edit. The sidebar
    /// takes focus instead, as in System Settings.
    private func clearInitialFocus() {
        DispatchQueue.main.async {
            searchFocused = false
            sidebarFocused = true
        }
    }

    private func applyRequestedPane() {
        // `open QuietSpeech.app --args -settingsPane ai` opens a pane directly,
        // and `-previewOverlay YES` plays the overlay preview, for checking
        // the layout.
        if let raw = UserDefaults.standard.string(forKey: "settingsPane"),
           let pane = SettingsPane(rawValue: raw) {
            selectedPane = pane
        }
        if UserDefaults.standard.bool(forKey: "previewOverlay") {
            model.previewOverlay()
        }
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
                        .padding(.top, 6)
                        .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.automatic)
            .toolbar(removing: .title)
            .toolbar {
                // As in System Settings. The toolbar also makes macOS run the
                // sidebar the full window height, traffic lights inside it.
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button(action: goBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(backStack.isEmpty)
                        Button(action: goForward) {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(forwardStack.isEmpty)
                    }
                }
            }
            .onChange(of: selectedPane) { previous, _ in
                if movingThroughHistory {
                    movingThroughHistory = false
                } else {
                    backStack.append(previous)
                    forwardStack.removeAll()
                }
                proxy.scrollTo("top", anchor: .top)
                search = ""
                clearInitialFocus()
            }
        }
    }

    private func goBack() {
        guard let pane = backStack.popLast() else { return }
        forwardStack.append(selectedPane)
        movingThroughHistory = true
        selectedPane = pane
    }

    private func goForward() {
        guard let pane = forwardStack.popLast() else { return }
        backStack.append(selectedPane)
        movingThroughHistory = true
        selectedPane = pane
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
