import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case behavior = "Goose Behavior"
    case audio = "Audio"
    case memes = "Memes"
    case notepadMessages = "Notepad Messages"
    case personalityPacks = "Personality Packs"
    case screenObservation = "Screen Observation"
    case permissions = "Permissions"
    case advanced = "Advanced Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview:          return "house"
        case .behavior:          return "bird"
        case .audio:             return "speaker.wave.2"
        case .memes:             return "photo.on.rectangle.angled"
        case .notepadMessages:   return "note.text"
        case .personalityPacks:  return "text.bubble"
        case .screenObservation: return "eye"
        case .permissions:       return "hand.raised"
        case .advanced:          return "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = GooseSettings.shared
    @State private var selection: SettingsTab = .overview

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(L(tab.rawValue), systemImage: tab.symbol).tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 185, ideal: 210, max: 245)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(title: L(selection.rawValue), symbol: selection.symbol)
                    page(for: selection)
                }
                .padding(24)
                .frame(maxWidth: 740, alignment: .leading)
                .id(selection)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.25), value: selection)
        }
        .frame(minWidth: 860, minHeight: 590)
    }

    @ViewBuilder
    private func page(for tab: SettingsTab) -> some View {
        switch tab {
        case .overview:          OverviewPage()
        case .behavior:          GooseBehaviorPage()
        case .audio:             AudioPage()
        case .memes:             MemesPage()
        case .notepadMessages:   NotepadMessagesPage()
        case .personalityPacks:  PersonalityPacksPage()
        case .screenObservation: ScreenObservationPage()
        case .permissions:       PermissionsSettingsPage()
        case .advanced:          AdvancedSettingsPage()
        }
    }
}

// MARK: - 1. Overview

private struct OverviewPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared

    var body: some View {
        SettingsCard(L("Startup")) {
            ToggleRow(title: L("Launch at Login"), subtitle: settings.launchAtLoginError ?? L("Open Super Goose Desktop automatically when you log in."), isOn: $settings.launchAtLogin)
            RowDivider()
            ToggleRow(title: L("Start Goose on Launch"), subtitle: L("Spawn the goose as soon as the app opens. Off = start with no geese."), isOn: $settings.startGooseOnLaunch)
            RowDivider()
            ToggleRow(title: L("Pause on Launch"), subtitle: L("Start with the goose frozen until you press Resume."), isOn: $settings.pauseOnLaunch)
            RowDivider()
            ToggleRow(title: L("Show Menu Bar Icon"), subtitle: L("If hidden, reopen the app from Finder to reach Settings."), isOn: $settings.showMenuBarIcon)
        }
        SettingsCard(L("Appearance")) {
            SliderRow(title: L("Goose Size"), value: $settings.gooseSize, range: 0.5...2.5, step: 0.05, format: Fmt.multiplier)
            RowDivider()
            SettingRow(title: L("Language")) {
                Picker("", selection: $settings.language) {
                    Text(L("System")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("繁體中文").tag(AppLanguage.traditionalChinese)
                }
                .labelsHidden().frame(width: 170)
            }
        }
        SettingsCard(L("Quick Controls")) {
            HStack(spacing: 10) {
                Button(controller.state == .running ? L("Pause Goose") : L("Resume Goose")) { controller.togglePause() }
                Button(L("Deliver Meme Now")) { controller.deliverMemeNow() }
                Button(L("Deliver Notepad Now")) { controller.deliverNotepadNow() }
                Spacer()
                Button(L("Open Control Center")) { Windows.controlCenter.show() }
            }
            .padding(16)
        }
    }
}

// MARK: - 2. Goose Behavior

private struct GooseBehaviorPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared

    private static let captions: [GooseBehavior: (title: String, subtitle: String)] = [
        .mouseTheft: ("Mouse Theft", "Goose steals the cursor when it catches it. Needs Mouse Chase."),
        .mouseDragging: ("Mouse Dragging", "Stolen cursor is carried to a screen corner. Off = catches it, honks, lets go."),
        .mouseChase: ("Mouse Chase", "Goose chases the cursor when poked or angered."),
        .windowPranks: ("Window Pranks", "Goose pushes active windows, peeks beside them, drags photos and opens web pages."),
        .footprints: ("Footprints", "Directional webbed footprints left behind as the goose walks."),
        .stickyNotes: ("Sticky Notes", "Goose delivers sticky notes with opinions."),
        .fakeErrors: ("Fake Errors", "Goose displays parody fake errors, crash alerts and system notifications."),
        .desktopMess: ("Desktop Mess", "Goose drops visual-only fake files, folders and icons onto the desktop overlay."),
        .gooseTheft: ("Goose Theft", "Goose visually steals a virtual desktop icon without touching real files."),
        .windowPeek: ("Window Peek", "Goose hides behind windows and peeks out from random edges."),
        .honking: ("Honking", "Goose honks (random honks and reactions)."),
        .sleepMode: ("Sleep Mode", "Goose naps and deep-sleeps."),
        .angryMode: ("Angry Mode", "Goose rages when you close its window or wake it from deep sleep."),
        .spotifyChill: ("Spotify Chilling", "Goose puts on headphones and starts music through Spotify."),
    ]

    var body: some View {
        SettingsCard(L("Behavior Switches")) {
            ToggleRow(title: L("Enable Goose Wandering"), isOn: $settings.wanderingEnabled)
            RowDivider()
            ToggleRow(title: L("Enable Meme Deliveries"), isOn: $settings.memesEnabled)
            RowDivider()
            ToggleRow(title: L("Enable Notepad Deliveries"), isOn: $settings.notepadDeliveriesEnabled)
            RowDivider()
            ToggleRow(title: L("Enable Random Duck Sounds"), isOn: $settings.duckSoundsEnabled)
            RowDivider()
            ToggleRow(title: L("Enable Goose Honks"), isOn: $settings.gooseSoundsEnabled)
            RowDivider()
            ToggleRow(title: L("Enable Randomized Behavior"), isOn: $settings.randomBehavior)
            RowDivider()
            ToggleRow(title: L("Quiet Mode"), subtitle: L("Lowers audio volume and reduces intrusive behavior."), isOn: $settings.quietMode)
            RowDivider()
            ToggleRow(title: L("Nighttime Quiet Hours"), subtitle: L("Silences ambient sounds between \(settings.quietStartHour):00 and \(settings.quietEndHour):00."), isOn: $settings.nighttimeQuietHours)
        }
        SettingsCard(L("Motion & Flock")) {
            SliderRow(title: L("Movement Speed"), value: $settings.movementSpeed, range: 0.25...3, step: 0.05, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Animation Speed"), value: $settings.animationSpeed, range: 0.25...3, step: 0.05, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Activity Frequency"), value: $settings.activityFrequency, range: 0.25...4, step: 0.05, format: Fmt.multiplier)
            RowDivider()
            SettingRow(title: L("Maximum Goose Count")) {
                Stepper(value: $settings.maxGooseCount, in: 1...5) {
                    Text("\(settings.maxGooseCount)").monospacedDigit().frame(width: 24, alignment: .trailing)
                }
            }
            RowDivider()
            HStack {
                Button { controller.spawnGoose() } label: { Label(L("Spawn New Goose"), systemImage: "plus.circle") }
                    .disabled(controller.geese.count >= settings.maxGooseCount)
                Button(role: .destructive) { controller.removeGoose() } label: { Label(L("Remove Goose"), systemImage: "minus.circle") }
                    .disabled(controller.geese.isEmpty)
                Spacer()
                Text("\(controller.geese.count) / \(settings.maxGooseCount)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        SettingsCard(L("Individual Prank Toggles")) {
            ForEach(Array(GooseBehavior.allCases.enumerated()), id: \.element) { index, behavior in
                if index > 0 { RowDivider() }
                let caption = Self.captions[behavior]
                ToggleRow(
                    title: L(caption?.title ?? behavior.rawValue),
                    subtitle: L(caption?.subtitle ?? ""),
                    isOn: Binding(get: { settings.isEnabled(behavior) }, set: { settings.setEnabled(behavior, $0) })
                )
            }
        }
        .onAppear { controller.refresh() }
    }
}

// MARK: - 3. Audio

private struct AudioPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var content = UserContentManager.shared

    var body: some View {
        SettingsCard(L("Master Audio")) {
            ToggleRow(title: L("Master Sound"), isOn: $settings.masterSoundEnabled)
            RowDivider()
            ToggleRow(title: L("Mute All Goose & Duck Audio"), isOn: $settings.muteGoose)
            RowDivider()
            SliderRow(title: L("Master Volume"), value: $settings.masterVolume, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Honk Volume"), value: $settings.honkVolume, range: 0...1, step: 0.05, format: Fmt.percent)
        }
        SettingsCard(L("Sound Categories")) {
            ToggleRow(title: L("Duck Sounds"), isOn: $settings.duckSoundsEnabled)
            RowDivider()
            ToggleRow(title: L("Goose Sounds"), isOn: $settings.gooseSoundsEnabled)
            RowDivider()
            ToggleRow(title: L("Footsteps & Movement"), isOn: $settings.footstepsEnabled)
            RowDivider()
            ToggleRow(title: L("Meme Sounds"), isOn: $settings.memeSoundsEnabled)
            RowDivider()
            ToggleRow(title: L("Notepad Sounds"), isOn: $settings.notepadSoundsEnabled)
            RowDivider()
            ToggleRow(title: L("Random Pitch Variation"), isOn: $settings.randomPitchVariation)
            RowDivider()
            SliderRow(title: L("Ambient Sound Frequency"), value: $settings.ambientSoundFrequency, range: 0.25...4, step: 0.05, format: Fmt.multiplier)
        }
        SettingsCard(L("Custom Sounds (UserContent/Sounds)")) {
            HStack(spacing: 8) {
                Button(L("Test Duck Quack")) { _ = SoundEffectEngine.shared.playDuck(.happyQuack, cooldown: 0) }
                Button(L("Test Goose Honk")) { _ = SoundEffectEngine.shared.playGoose(.classicHonk, cooldown: 0) }
                Button(L("Import Sounds…")) { importSoundsPanel() }
                Button(L("Open Sound Folder")) { content.openUserContentInFinder() }
                Spacer()
            }
            .padding(16)
            ForEach(content.sounds) { item in
                RowDivider()
                HStack {
                    Text(item.filename)
                    Spacer()
                    Button(role: .destructive) {
                        content.deleteSound(item)
                        SoundEffectEngine.shared.reloadCustomSounds()
                    } label: { Image(systemName: "trash") }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }

    private func importSoundsPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        if panel.runModal() == .OK {
            _ = content.importSounds(from: panel.urls)
            SoundEffectEngine.shared.reloadCustomSounds()
        }
    }
}

// MARK: - 8. Permissions

private struct PermissionsSettingsPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var activity = ExternalAIActivity.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @State private var confirmExternal = false

    var body: some View {
        SettingsCard(L("Permissions")) {
            SettingRow(title: L("Screen Recording permission")) {
                HStack(spacing: 8) {
                    StatusDot(on: permissions.screenRecordingState.isAuthorized)
                    Text(L(permissions.screenRecordingState.displayTitle)).foregroundStyle(.secondary)
                    if !permissions.screenRecordingState.isAuthorized {
                        Button(L("Request")) { permissions.requestScreenRecordingAccess() }
                        Button(L("Open System Settings")) { permissions.openScreenRecordingSettings() }
                    }
                }
            }
            RowDivider()
            SettingRow(title: L("Accessibility permission")) {
                HStack(spacing: 8) {
                    StatusDot(on: permissions.accessibilityState.isAuthorized)
                    Text(L(permissions.accessibilityState.displayTitle)).foregroundStyle(.secondary)
                    if !permissions.accessibilityState.isAuthorized {
                        Button(L("Request")) { permissions.requestAccessibilityAccess() }
                        Button(L("Open System Settings")) { permissions.openAccessibilitySettings() }
                    }
                }
            }
            RowDivider()
            SettingRow(title: L("Notifications permission")) {
                HStack(spacing: 8) {
                    StatusDot(on: notifications.isAuthorized)
                    Text(L(notifications.authorizationStatusText)).foregroundStyle(.secondary)
                    if !notifications.isAuthorized {
                        Button(L("Request")) { notifications.requestAuthorization() }
                        Button(L("Open System Settings")) { Self.openNotifications() }
                    }
                }
            }
            RowDivider()
            SettingRow(title: L("Permission Center")) {
                HStack(spacing: 8) {
                    Button(L("Recheck")) { permissions.refreshAll(validateLiveAX: true); notifications.refreshStatus() }
                    Button(L("Open Permission Center…")) { Windows.permissionCenter.show() }
                }
            }
        }
        SettingsCard(L("Data Transmission")) {
            SettingRow(title: L("Allow external AI (OpenAI)"), subtitle: L("Off by default. Nothing is sent to any server unless you turn this on.")) {
                Toggle("", isOn: Binding(
                    get: { settings.externalAIOptIn },
                    set: { on in if on { confirmExternal = true } else { settings.externalAIOptIn = false } }
                )).labelsHidden().toggleStyle(.switch)
            }
            RowDivider()
            ToggleRow(title: L("Send app names"), subtitle: L("When external AI is on, include the frontmost app name in the request. Off = only idle time is sent."), isOn: $settings.sendAppNameToExternalAI)
                .disabled(!settings.externalAIOptIn)
            RowDivider()
            ToggleRow(title: L("Allow web pages"), subtitle: L("Let the goose open web pages in a browser window."), isOn: $settings.allowWebBrowsing)
        }
        .confirmationDialog(L("Enable external AI?"), isPresented: $confirmExternal, titleVisibility: .visible) {
            Button(L("Enable")) { settings.externalAIOptIn = true }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The goose will send the frontmost app name (if allowed below), time on app and idle time to OpenAI to write notes. Screen contents and OCR text are never sent. You can turn this off at any time."))
        }
        SettingsCard(L("Network Activity")) {
            SettingRow(title: L("External AI requests this session")) { Text("\(activity.requestCount)").monospacedDigit().foregroundStyle(.secondary) }
            RowDivider()
            SettingRow(title: L("Last request")) {
                Text(activity.lastRequest.map { "\($0.formatted(date: .omitted, time: .standard)) → \(activity.lastHost ?? "")" } ?? L("Never"))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            permissions.refreshAll(validateLiveAX: true)
            notifications.refreshStatus()
        }
    }

    private static func openNotifications() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 9. Advanced Settings

private struct AdvancedSettingsPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared
    @State private var confirmRestore = false
    @State private var updateMessage: String?
    @State private var checking = false

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    private static let repo = URL(string: "https://github.com/li-bao/goose")!

    var body: some View {
        SettingsCard(L("Chaos Preset & Tunables")) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(get: { settings.chaosLevel }, set: { settings.applyChaosLevel($0) })) {
                    ForEach(ChaosLevel.allCases) { Text(L($0.rawValue.capitalized)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            .padding(16)
            RowDivider()
            SliderRow(title: L("Mouse Theft Probability"), value: $settings.mouseTheftProbability, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Prank Frequency"), value: $settings.prankFrequency, range: 0.1...4, step: 0.1, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Mouse Chase Duration"), value: $settings.mouseChaseDuration, range: 2...30, step: 1, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Behavior Cooldown"), value: $settings.behaviorCooldown, range: 0...120, step: 1, format: Fmt.seconds)
        }
        SettingsCard(L("Prank Parameters")) {
            SliderRow(title: L("Mouse Drag Duration"), value: $settings.mouseDragDuration, range: 2...15, step: 0.5, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Mouse Chase Range"), value: $settings.mouseChaseRange, range: 80...500, step: 10, format: { "\(Int($0))px" })
            RowDivider()
            SettingRow(title: L("Max Footprints")) {
                Stepper(value: $settings.footprintMaxCount, in: 16...128, step: 8) {
                    Text("\(settings.footprintMaxCount)").monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }
            RowDivider()
            SliderRow(title: L("Window Push Amplitude"), value: $settings.windowNudgeAmplitude, range: 10...120, step: 5, format: { "\(Int($0))px" })
            RowDivider()
            SettingRow(title: L("Virtual mess items") + ": \(controller.desktopMessCount)") {
                Button(L("Clear Desktop Mess")) { controller.clearDesktopMess() }
            }
        }
        SettingsCard(L("AI Engine")) {
            ToggleRow(title: L("Enable AI"), isOn: $settings.aiEnabled)
            RowDivider()
            SettingRow(title: L("AI Provider")) {
                Picker("", selection: $settings.aiProvider) {
                    Text(L("Automatic")).tag(AIProviderChoice.auto)
                    Text(L("Apple On-Device")).tag(AIProviderChoice.appleOnDevice)
                    Text(L("OpenAI (external)")).tag(AIProviderChoice.openAI)
                }
                .labelsHidden().frame(width: 190)
            }
            RowDivider()
            SettingRow(title: L("AI Model")) {
                TextField("gpt-5-mini", text: $settings.aiModel).textFieldStyle(.roundedBorder).frame(width: 190)
            }
            RowDivider()
            ToggleRow(title: L("AI Prank Text Generation"), isOn: $settings.aiPrankText)
        }
        SettingsCard(L("Fullscreen Awareness & Hotkeys")) {
            ToggleRow(title: L("Fullscreen Awareness"), isOn: $settings.fullscreenAwareness)
            RowDivider()
            SettingRow(title: L("Exception Apps")) {
                TextField("Safari, Xcode", text: $settings.fullscreenExceptionApps).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            RowDivider()
            ToggleRow(title: L("Enable Global Hotkeys"), isOn: $settings.hotkeysEnabled)
            ForEach(HotkeyAction.allCases) { action in
                RowDivider()
                SettingRow(title: L(action.title)) {
                    Text(settings.binding(for: action).display)
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            RowDivider()
            SettingRow(title: L("Reset Hotkeys")) { Button(L("Reset")) { settings.resetHotkeys() } }
        }
        SettingsCard(L("About & Reset")) {
            SettingRow(title: L("Application Version")) { Text("\(version) (\(build))").foregroundStyle(.secondary) }
            RowDivider()
            SettingRow(title: L("GitHub Repository")) { Link("li-bao/goose", destination: Self.repo) }
            RowDivider()
            SettingRow(title: L("Restore Defaults")) {
                Button(L("Reset"), role: .destructive) { confirmRestore = true }
            }
        }
        .confirmationDialog(L("Restore all settings to their defaults?"), isPresented: $confirmRestore) {
            Button(L("Restore"), role: .destructive) { settings.restoreDefaults() }
            Button(L("Cancel"), role: .cancel) {}
        }
    }
}
