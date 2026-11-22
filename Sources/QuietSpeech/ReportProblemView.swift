import AppKit
import SwiftUI

/// Report a Problem: a short description, the app it happened in, an
/// optional reply address and optional diagnostics, sent from the app.
struct ReportProblemView: View {
    var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    private enum SendState: Equatable {
        case editing, sending, sent(String), failed(String)
    }

    @State private var details = ""
    @State private var appName = ""
    @State private var email = ""
    @State private var includeDiagnostics = true
    @State private var showDiagnostics = false
    @State private var summary: [String] = []
    @State private var log: [String] = []
    @State private var loadingLog = true
    @State private var copied = false
    @State private var state = SendState.editing
    @FocusState private var detailsFocused: Bool

    private var report: ProblemReport {
        ProblemReport(
            description: details,
            appName: appName,
            email: email,
            summary: includeDiagnostics ? summary : [],
            log: includeDiagnostics ? log : []
        )
    }

    private var canSend: Bool {
        state != .sending
            && !(loadingLog && includeDiagnostics)
            && report.isValidEmail
            && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if case .sent(let id) = state {
                sentView(id: id)
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { await load() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Report a Problem")
                    .font(.title2.weight(.semibold))
                Text("Tell us what went wrong and we’ll look into it. Reports go straight to the QuietSpeech developer.")
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

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App you were typing into").font(.headline)
                    TextField("Optional", text: $appName)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email for a reply").font(.headline)
                    TextField("Optional", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                    if !report.isValidEmail {
                        Text("Check this address.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
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

            if case .failed(let message) = state {
                Text("Couldn’t send the report. \(message) Check your internet connection and try again, or use Copy Report.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(copied ? "Copied" : "Copy Report") { copyReport() }
                Spacer()
                if state == .sending {
                    ProgressView().controlSize(.small)
                }
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Send Report") { Task { await send() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSend)
            }
        }
    }

    private func sentView(id: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Thanks, your report was sent")
                .font(.title3.weight(.semibold))
            Text(email.isEmpty
                 ? "Your reference is \(id)."
                 : "Your reference is \(id). We’ll reply to \(email.trimmingCharacters(in: .whitespaces)).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("Done") { close() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func load() async {
        summary = Diagnostics.systemLines() + model.diagnosticSummary()
        if appName.isEmpty, let name = model.targetApp?.localizedName { appName = name }
        detailsFocused = true
        log = await Task.detached(priority: .userInitiated) { Diagnostics.recentLog() }.value
        loadingLog = false
    }

    private func send() async {
        state = .sending
        do {
            state = .sent(try await report.send())
        } catch {
            state = .failed(error.localizedDescription.hasSuffix(".")
                            ? error.localizedDescription
                            : error.localizedDescription + ".")
        }
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(report.subject)\n\n\(report.body)", forType: .string)
        copied = true
    }

    private func close() {
        dismissWindow(id: ReportProblemView.windowID)
    }

    static let windowID = "report-problem"
}
