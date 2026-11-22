import AppKit
import SwiftUI

/// Report a Problem: a short description, the app it happened in, and
/// optional diagnostics, sent as an email the user reviews before sending.
struct ReportProblemView: View {
    var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var details = ""
    @State private var appName = ""
    @State private var includeDiagnostics = true
    @State private var showDiagnostics = false
    @State private var summary: [String] = []
    @State private var log: [String] = []
    @State private var loadingLog = true
    @State private var copied = false
    @State private var mailFailed = false
    @FocusState private var detailsFocused: Bool

    private var report: ProblemReport {
        ProblemReport(
            description: details,
            appName: appName,
            summary: includeDiagnostics ? summary : [],
            log: includeDiagnostics ? log : []
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Report a Problem")
                    .font(.title2.weight(.semibold))
                Text("Tell us what went wrong. Your report opens as an email to \(ProblemReport.supportEmail), so you can read it before sending.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What happened?").font(.headline)
                TextEditor(text: $details)
                    .font(.body)
                    .focused($detailsFocused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if details.isEmpty {
                            Text("For example: I held Fn in Slack, saw “Inserted”, but no text appeared.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("App you were typing into").font(.headline)
                TextField("Optional", text: $appName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Include diagnostics", isOn: $includeDiagnostics)
                Text("Your QuietSpeech and macOS versions, Mac model, settings, and the app’s log from the last 30 minutes. Never audio or anything you dictated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if includeDiagnostics {
                    DisclosureGroup("Show what’s included", isExpanded: $showDiagnostics) {
                        ScrollView {
                            Text(loadingLog ? "Reading the log…" : report.diagnosticsText)
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 160)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .font(.caption)
                }
            }

            if mailFailed {
                Text("No mail app opened. Use Copy Report and email it to \(ProblemReport.supportEmail).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button(copied ? "Copied" : "Copy Report") { copyReport() }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Send Email…") { sendEmail() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(loadingLog && includeDiagnostics)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { await load() }
    }

    private func load() async {
        summary = Diagnostics.systemLines() + model.diagnosticSummary()
        if appName.isEmpty, let name = model.targetApp?.localizedName { appName = name }
        detailsFocused = true
        log = await Task.detached(priority: .userInitiated) { Diagnostics.recentLog() }.value
        loadingLog = false
    }

    private func sendEmail() {
        guard let url = report.mailtoURL, NSWorkspace.shared.open(url) else {
            mailFailed = true
            return
        }
        close()
    }

    private func copyReport() {
        let text = "To: \(ProblemReport.supportEmail)\nSubject: \(report.subject)\n\n\(report.body)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private func close() {
        dismissWindow(id: ReportProblemView.windowID)
    }

    static let windowID = "report-problem"
}
