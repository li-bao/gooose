import AppKit
import SwiftUI

struct PermissionCenterView: View {
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var settings = GooseSettings.shared
    @State private var showDiagnostics = false
    @State private var copiedDiagnostics = false
    @State private var recheckingScreen = false
    @State private var liveCapturer = ScreenCapturer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overallHeader
                screenRecordingCard
                accessibilityCard
                diagnosticsCard
            }
            .padding(24)
            .animation(.smooth(duration: 0.25), value: permissions.screenRecordingState)
            .animation(.smooth(duration: 0.25), value: permissions.accessibilityState)
        }
        .frame(minWidth: 640, minHeight: 700)
        .onAppear {
            permissions.refreshAll(validateLiveAX: true)
        }
    }

    private var overallHeader: some View {
        let ready = permissions.allActivePermissionsReady
        return HStack(spacing: 14) {
            Image(systemName: ready ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 34))
                .foregroundStyle(ready ? .green : .orange)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                Text(ready ? L("All permissions ready") : L("Permissions need attention"))
                    .font(.title2.weight(.semibold))
                Text(
                    ready
                    ? L("All active features have verified macOS authorization.")
                    : L("Goose animation, menu bar controls, and independent pranks continue working even while optional permissions are unavailable.")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Card A: Screen Recording

    private var screenRecordingCard: some View {
        SettingsCard(L("Screen Recording")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: permissions.screenRecordingState))
                        .frame(width: 10, height: 10)
                    Text(L(permissions.screenRecordingState.displayTitle))
                        .font(.headline)
                    Spacer()
                }

                Text(L("Needed for local screen capture and on-device Vision OCR context. Screen images stay in memory on this Mac and are never uploaded."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let detail = permissions.screenRecordingState.detailMessage {
                    detailBanner(detail, tint: color(for: permissions.screenRecordingState))
                } else if let err = permissions.lastScreenCaptureError, !permissions.screenRecordingState.isAuthorized {
                    detailBanner(err.localizedDescription, tint: .orange)
                }

                HStack(spacing: 8) {
                    Button(L("Request Access")) {
                        permissions.requestScreenRecordingAccess()
                    }
                    Button(L("Open Screen Recording Settings")) {
                        permissions.openScreenRecordingSettings()
                    }
                    Button(recheckingScreen ? L("Checking…") : L("Recheck")) {
                        recheckingScreen = true
                        Task {
                            await permissions.recheckScreenRecordingWithLiveCapture(capturer: liveCapturer)
                            recheckingScreen = false
                        }
                    }
                    .disabled(recheckingScreen)

                    if case .restartRequired = permissions.screenRecordingState {
                        Spacer()
                        if Bundle.main.bundleURL.pathExtension == "app" {
                            Button(L("Quit & Reopen")) {
                                permissions.relaunchApplication()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Card B: Accessibility

    private var accessibilityCard: some View {
        SettingsCard(L("Accessibility")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: permissions.accessibilityState))
                        .frame(width: 10, height: 10)
                    Text(L(permissions.accessibilityState.displayTitle))
                        .font(.headline)
                    Spacer()
                }

                Text(L("Needed to read focused window titles/bounds and perform Window Pranks or Window Peek. Without Accessibility, basic frontmost app detection via NSWorkspace still works."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("\(L("Live Check")): \(permissions.lastAccessibilityValidation.summaryText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let detail = permissions.accessibilityState.detailMessage {
                    detailBanner(detail, tint: color(for: permissions.accessibilityState))
                }

                HStack(spacing: 8) {
                    Button(L("Request Access")) {
                        permissions.requestAccessibilityAccess()
                    }
                    Button(L("Open Accessibility Settings")) {
                        permissions.openAccessibilitySettings()
                    }
                    Button(L("Recheck")) {
                        permissions.refreshAccessibility(validateLive: true)
                        permissions.refreshDiagnostics()
                    }

                    if case .restartRequired = permissions.accessibilityState,
                       Bundle.main.bundleURL.pathExtension == "app" {
                        Spacer()
                        Button(L("Quit & Reopen")) {
                            permissions.relaunchApplication()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Diagnostics & Recovery

    private var diagnosticsCard: some View {
        SettingsCard(L("TCC & Signing Diagnostics")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DisclosureGroup(L("Show Technical Diagnostics & Recovery Commands"), isExpanded: $showDiagnostics) {
                        if let report = permissions.diagnostics {
                            VStack(alignment: .leading, spacing: 8) {
                                diagnosticRow(L("Bundle ID"), report.bundleIdentifier)
                                diagnosticRow(L("Bundle Path"), report.bundlePath)
                                diagnosticRow(L("Executable"), report.executablePath)
                                diagnosticRow(L("Signing Identity"), report.signingIdentity)
                                diagnosticRow(L("TeamIdentifier"), report.teamIdentifier)
                                diagnosticRow(L("CDHash"), report.cdHash)
                                diagnosticRow(L("Designated Requirement"), report.designatedRequirement)
                                diagnosticRow(L("macOS / Arch"), "\(report.macOSVersion) (\(report.architecture))")

                                if !report.warnings.isEmpty {
                                    Divider()
                                    Text(L("Detected Issues")).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                    ForEach(report.warnings, id: \.self) { warning in
                                        Text("• \(warning)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()
                                Text(L("Optional Terminal Recovery (only run manually if TCC entries are stale):"))
                                    .font(.caption.weight(.semibold))
                                ForEach(report.recoveryCommands, id: \.self) { cmd in
                                    Text(cmd)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(L("Refresh Diagnostics")) {
                        permissions.refreshAll(validateLiveAX: true)
                    }
                    Button(copiedDiagnostics ? L("Copied") : L("Copy Diagnostics")) {
                        let text = permissions.diagnostics?.formattedText() ?? ""
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copiedDiagnostics = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedDiagnostics = false
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 145, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func detailBanner(_ message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .authorized:
            return .green
        case .notAuthorized:
            return .secondary
        case .requestInitiated:
            return .blue
        case .restartRequired, .unableToVerify:
            return .orange
        case .error:
            return .red
        }
    }
}
