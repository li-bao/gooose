import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", goose = "Goose", chaos = "Chaos", behaviors = "Behaviors", sounds = "Sounds"
    case personality = "Personality", ai = "AI", privacy = "Privacy", about = "About"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .goose: return "bird"
        case .chaos: return "flame"
        case .behaviors: return "switch.2"
        case .sounds: return "speaker.wave.2"
        case .personality: return "face.smiling"
        case .ai: return "sparkles"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = GooseSettings.shared
    @State private var selection: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(L(tab.rawValue), systemImage: tab.symbol).tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(title: L(selection.rawValue), symbol: selection.symbol)
                    page(for: selection)
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .id(selection)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.25), value: selection)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    private func page(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralPage()
        case .goose: GoosePage()
        case .chaos: ChaosPage()
        case .behaviors: BehaviorsPage()
        case .sounds: SoundsPage()
        case .personality: PersonalityPage()
        case .ai: AIPage()
        case .privacy: PrivacyPage()
        case .about: AboutPage()
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @State private var confirmRestore = false

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
        SettingsCard(L("Fullscreen Awareness")) {
            ToggleRow(
                title: L("Fullscreen Awareness"),
                subtitle: L("Automatically pause intrusive pranks during fullscreen games and reduce activity during media/presentations."),
                isOn: $settings.fullscreenAwareness
            )
            RowDivider()
            SettingRow(
                title: L("Exception Apps"),
                subtitle: L("Comma-separated app names (e.g. Safari, Terminal)")
            ) {
                TextField("Safari, Xcode", text: $settings.fullscreenExceptionApps)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
        }
        SettingsCard(L("Notifications")) {
            ToggleRow(title: L("Enable Notifications"), isOn: $settings.notificationsEnabled)
            if settings.notificationsEnabled {
                RowDivider()
                ToggleRow(title: L("Goose Prank Notifications"), isOn: $settings.notifyPrank)
                RowDivider()
                ToggleRow(title: L("New Goose Joined"), isOn: $settings.notifyNewGoose)
                RowDivider()
                ToggleRow(title: L("AI Generated Message"), isOn: $settings.notifyAIMessage)
                RowDivider()
                ToggleRow(title: L("Personality Changed"), isOn: $settings.notifyPersonalityChange)
                RowDivider()
                ToggleRow(title: L("Goose Sleeping"), isOn: $settings.notifyGooseSleeping)
            }
        }
        SettingsCard(L("Global Hotkeys")) {
            ToggleRow(title: L("Enable Global Hotkeys"), isOn: $settings.hotkeysEnabled)
            ForEach(HotkeyAction.allCases) { action in
                RowDivider()
                SettingRow(title: L(action.title)) {
                    Text(settings.binding(for: action).display)
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            RowDivider()
            SettingRow(title: L("Reset Hotkeys")) {
                Button(L("Reset")) { settings.resetHotkeys() }
            }
        }
        SettingsCard {
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

// MARK: - Goose

private struct GoosePage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared

    var body: some View {
        SettingsCard(L("Motion")) {
            SliderRow(title: L("Movement Speed"), value: $settings.movementSpeed, range: 0.25...3, step: 0.05, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Animation Speed"), value: $settings.animationSpeed, range: 0.25...3, step: 0.05, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Activity Frequency"), subtitle: L("How often the goose decides to do something new."), value: $settings.activityFrequency, range: 0.25...4, step: 0.05, format: Fmt.multiplier)
        }
        SettingsCard(L("Geese")) {
            SettingRow(title: L("Maximum Goose Count")) {
                Stepper(value: $settings.maxGooseCount, in: 1...5) {
                    Text("\(settings.maxGooseCount)").monospacedDigit().frame(width: 24, alignment: .trailing)
                }
            }
            RowDivider()
            SettingRow(title: L("Current geese"), subtitle: L("Companion geese wander, nap and chase the mouse. Notes, windows and music come from Goose 1.")) {
                Text("\(controller.geese.count) / \(settings.maxGooseCount)").monospacedDigit().foregroundStyle(.secondary)
            }
            RowDivider()
            HStack {
                Button { controller.spawnGoose() } label: { Label(L("Spawn New Goose"), systemImage: "plus.circle") }
                    .disabled(controller.geese.count >= settings.maxGooseCount)
                Button(role: .destructive) { controller.removeGoose() } label: { Label(L("Remove Goose"), systemImage: "minus.circle") }
                    .disabled(controller.geese.isEmpty)
                Spacer()
                if controller.geese.count >= settings.maxGooseCount { Text(L("Maximum reached")).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(16)
        }
        .onAppear { controller.refresh() }
    }
}

// MARK: - Chaos

private struct ChaosPage: View {
    @ObservedObject private var settings = GooseSettings.shared

    var body: some View {
        SettingsCard(L("Chaos Level")) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(get: { settings.chaosLevel }, set: { settings.applyChaosLevel($0) })) {
                    ForEach(ChaosLevel.allCases) { Text(L($0.rawValue.capitalized)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 6) {
                    if settings.isChaosCustomized { Text(L("Customized")).font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                    Text(L("Picking a level sets the four sliders below. Moving a slider customizes it.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        SettingsCard {
            SliderRow(title: L("Mouse Theft Probability"), value: $settings.mouseTheftProbability, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Prank Frequency"), value: $settings.prankFrequency, range: 0.1...4, step: 0.1, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Mouse Chase Duration"), value: $settings.mouseChaseDuration, range: 2...30, step: 1, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Behavior Cooldown"), subtitle: L("Minimum time between autonomous pranks."), value: $settings.behaviorCooldown, range: 0...120, step: 1, format: Fmt.seconds)
        }
        SettingsCard {
            ToggleRow(title: L("Random Behavior"), subtitle: L("Let the goose pick random actions on its own. Off = it only reacts to you."), isOn: $settings.randomBehavior)
        }
    }
}

// MARK: - Behaviors

private struct BehaviorsPage: View {
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
        if settings.allPranksDisabled {
            SettingsCard {
                SettingRow(title: L("All pranks are currently disabled by the master switch.")) {
                    Button(L("Re-enable")) { settings.allPranksDisabled = false }
                }
            }
        }
        SettingsCard(L("Available")) {
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
            SliderRow(title: L("Footprint Opacity"), value: $settings.footprintOpacity, range: 0.1...1.0, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Footprint Lifetime"), value: $settings.footprintLifetime, range: 2...30, step: 0.5, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Sticky Note Lifetime"), value: $settings.stickyNoteLifetime, range: 5...120, step: 1, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Window Push Amplitude"), value: $settings.windowNudgeAmplitude, range: 10...120, step: 5, format: { "\(Int($0))px" })
            RowDivider()
            SettingRow(title: L("Fake Error Custom Text")) {
                TextField(L("Leave empty for AI / random parody text"), text: $settings.fakeErrorCustomText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            RowDivider()
            SettingRow(title: L("Virtual mess items") + ": \(controller.desktopMessCount)") {
                Button(L("Clear Desktop Mess")) { controller.clearDesktopMess() }
            }
        }
    }
}

// MARK: - Sounds

private struct SoundsPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared

    var body: some View {
        SettingsCard {
            HStack(spacing: 8) {
                Image(systemName: controller.audioAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(controller.audioAvailable ? .green : .orange)
                Text(controller.audioAvailable ? L("Audio files loaded.") : L("No goose audio files were found, so nothing will play. Set GOOSE_AUDIO_PATH to a folder containing your own Honk/Pat/Bite files."))
                    .font(.callout)
                Spacer()
            }
            .padding(16)
        }
        SettingsCard(L("Volume")) {
            SliderRow(title: L("Master Volume"), value: $settings.masterVolume, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Honk Volume"), value: $settings.honkVolume, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            ToggleRow(title: L("Sound Effects"), subtitle: L("Footsteps and bites."), isOn: $settings.soundEffects)
            RowDivider()
            ToggleRow(title: L("Mute Goose"), subtitle: nil, isOn: $settings.muteGoose)
        }
        SettingsCard(L("Honks")) {
            ToggleRow(title: L("Random Honking"), isOn: $settings.randomHonking)
            RowDivider()
            SliderRow(title: L("Sound Frequency"), value: $settings.soundFrequency, range: 0.25...4, step: 0.05, format: Fmt.multiplier)
        }
    }
}

// MARK: - Personality

private struct PersonalityPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var stats = GooseStats.shared

    var body: some View {
        SettingsCard(L("Traits")) {
            SliderRow(title: L("Naughty"), value: $settings.naughty, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Aggressive"), value: $settings.aggressive, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Lazy"), value: $settings.laziness, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Curious"), value: $settings.curious, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Affectionate"), value: $settings.affectionate, range: 0...1, step: 0.05, format: Fmt.percent)
            Text(L("Naughty = more pranks. Aggressive = steals more. Lazy = naps more. Curious = more photos and web. Affectionate = more hearts."))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
        }
        SettingsCard(L("Learning")) {
            ToggleRow(title: L("Personality Evolution"), subtitle: L("Traits drift slowly based on how you treat the goose."), isOn: $settings.personalityEvolution)
            RowDivider()
            ToggleRow(title: L("Interaction Memory"), subtitle: L("Remember pats, pokes and closed windows between launches."), isOn: $settings.interactionMemory)
            RowDivider()
            SettingRow(title: "\(L("Pats")): \(stats.patCount)   \(L("Pokes")): \(stats.pokeCount)   \(L("Windows closed")): \(stats.windowsClosedCount)") {
                Button(L("Clear Memory")) { stats.clearMemory() }
            }
        }
    }
}

// MARK: - AI

private struct AIPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared

    var body: some View {
        SettingsCard {
            ToggleRow(title: L("Enable AI"), subtitle: L("Off = the goose uses only its built-in deterministic behavior and text."), isOn: $settings.aiEnabled)
        }
        SettingsCard {
            SettingRow(title: L("AI Provider")) {
                Picker("", selection: $settings.aiProvider) {
                    Text(L("Automatic")).tag(AIProviderChoice.auto)
                    Text(L("Apple On-Device")).tag(AIProviderChoice.appleOnDevice)
                    Text(L("OpenAI (external)")).tag(AIProviderChoice.openAI)
                }
                .labelsHidden().frame(width: 190)
            }
            RowDivider()
            SettingRow(title: L("AI Model"), subtitle: L("OpenAI model name. Only used when external AI is opted in.")) {
                TextField("gpt-5-mini", text: $settings.aiModel).textFieldStyle(.roundedBorder).frame(width: 190)
            }
            RowDivider()
            SettingRow(title: L("AI Personality")) {
                Picker("", selection: $settings.aiPersonality) {
                    Text(L("Sarcastic")).tag(AIPersonalityStyle.sarcastic)
                    Text(L("Friendly")).tag(AIPersonalityStyle.friendly)
                    Text(L("Chaotic")).tag(AIPersonalityStyle.chaotic)
                    Text(L("Deadpan")).tag(AIPersonalityStyle.deadpan)
                }
                .labelsHidden().frame(width: 190)
            }
            RowDivider()
            ToggleRow(title: L("AI Prank Text Generation"), subtitle: L("Let the AI write sticky-note text. Off = built-in notes."), isOn: $settings.aiPrankText)
            RowDivider()
            SliderRow(title: L("AI Request Frequency"), subtitle: L("Minimum seconds between AI requests."), value: $settings.aiRequestInterval, range: 0...120, step: 1, format: Fmt.seconds)
        }
        .disabled(!settings.aiEnabled)
        .opacity(settings.aiEnabled ? 1 : 0.55)
        SettingsCard(L("Provider status")) {
            SettingRow(title: L("Apple on-device")) { Text(controller.llm.appleStatusText).foregroundStyle(.secondary) }
            RowDivider()
            SettingRow(title: L("OpenAI")) { Text(controller.llm.openAIStatusText).foregroundStyle(.secondary) }
            if !settings.externalAIOptIn {
                Text(L("External AI is off. Enable it in Privacy to use OpenAI.")).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacyPage: View {
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
        SettingsCard(L("Local processing")) {
            ToggleRow(title: L("Screen Recognition"), subtitle: L("Capture the screen and run OCR on this Mac to give the goose context. Nothing leaves your Mac."), isOn: $settings.screenRecognition)
            RowDivider()
            Text("\(L("OCR Privacy")): \(L("OCR text is processed in memory on this Mac and is never stored. It is never included in external AI requests: only the app name (optional) and idle time can be sent."))")
                .font(.caption).foregroundStyle(.secondary).padding(16)
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
            Text(L("The goose can also load web pages (when Window Pranks and web pages are allowed) and, only when you press the button, check GitHub for updates."))
                .font(.caption).foregroundStyle(.secondary).padding(16)
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

// MARK: - About

private struct AboutPage: View {
    @State private var updateMessage: String?
    @State private var checking = false

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    private static let repo = URL(string: "https://github.com/PKrutaa/super-goose-desktop")!

    var body: some View {
        SettingsCard {
            SettingRow(title: L("Application Version")) { Text(version).foregroundStyle(.secondary) }
            RowDivider()
            SettingRow(title: L("Build Version")) { Text(build).foregroundStyle(.secondary) }
            RowDivider()
            SettingRow(title: L("GitHub Repository")) { Link("PKrutaa/super-goose-desktop", destination: Self.repo) }
            RowDivider()
            SettingRow(title: L("License")) { Text(L("MIT License")).foregroundStyle(.secondary) }
        }
        SettingsCard(L("Credits")) {
            Text(L("Sprites by romainflcht/py-goose. Original Desktop Goose by Sam Chiet. Mac port inspiration by Jesús A. Álvarez."))
                .font(.callout).padding(16)
        }
        SettingsCard {
            SettingRow(title: L("Check for Updates"), subtitle: updateMessage ?? L("Update checks only run when you press the button.")) {
                Button(checking ? L("Checking…") : L("Check for Updates")) { Task { await check() } }.disabled(checking)
            }
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        guard let url = URL(string: "https://api.github.com/repos/PKrutaa/super-goose-desktop/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                updateMessage = L("No published releases found.")
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                updateMessage = L("No published releases found.")
                return
            }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if latest.compare(version, options: .numeric) == .orderedDescending {
                updateMessage = "\(L("A newer version is available:")) \(tag)"
            } else {
                updateMessage = L("You are up to date.")
            }
        } catch {
            updateMessage = "\(L("Update check failed:")) \(error.localizedDescription)"
        }
    }
}
