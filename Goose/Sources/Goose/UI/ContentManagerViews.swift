import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Memes Manager

struct MemesPage: View {
    @ObservedObject private var content = UserContentManager.shared
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared
    @State private var isDropTargeted = false
    @State private var renamingItem: MemeItem?
    @State private var renameText = ""

    var body: some View {
        SettingsCard(L("Custom Memes")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Import PNG, JPG, JPEG, or animated GIF memes. Files are copied locally into UserContent/Memes without modifying your originals."))
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(L("Import Memes…")) { importMemesPanel() }
                    Button(L("Open Memes Folder")) { content.openUserContentInFinder() }
                    Button(L("Deliver Meme Now")) { controller.deliverMemeNow() }
                        .disabled(content.memes.isEmpty)
                    Spacer()
                    Text("\(content.memes.count) " + L("items"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                dropZone

                if let err = content.lastErrorMessage {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)
        }

        SettingsCard(L("Delivery Settings")) {
            ToggleRow(title: L("Enable Meme Deliveries"), isOn: $settings.memesEnabled)
            RowDivider()
            SettingRow(title: L("Max Visible Memes")) {
                Stepper(value: $settings.maxVisibleMemes, in: 1...8) {
                    Text("\(settings.maxVisibleMemes)").monospacedDigit().frame(width: 24, alignment: .trailing)
                }
            }
            RowDivider()
            SliderRow(title: L("Meme Lifetime"), value: $settings.memeLifetime, range: 5...120, step: 5, format: Fmt.seconds)
        }

        SettingsCard(L("Imported Memes")) {
            if content.memes.isEmpty {
                Text(L("No memes imported yet.")).foregroundStyle(.secondary).padding(16)
            } else {
                ForEach(Array(content.memes.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        MemeThumbnail(url: item.url)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.filename).font(.body.weight(.medium))
                                if item.isAnimatedGIF {
                                    Text("GIF · \(item.frameCount)f")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height)) · \(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Rename")) {
                            renamingItem = item
                            renameText = (item.filename as NSString).deletingPathExtension
                        }
                        Button(role: .destructive) {
                            content.deleteMeme(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
        .sheet(item: $renamingItem) { item in
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Rename Meme")).font(.headline)
                TextField(L("Filename"), text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                HStack {
                    Spacer()
                    Button(L("Cancel")) { renamingItem = nil }
                    Button(L("Save")) {
                        try? content.renameMeme(item, to: renameText)
                        renamingItem = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
            Text(L("Drop PNG, JPG, JPEG, or GIF files here"))
                .font(.callout).foregroundStyle(.secondary)
                .padding(.vertical, 18)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers) { urls in
                _ = content.importMemes(from: urls)
            }
        }
    }

    private func importMemesPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        if panel.runModal() == .OK {
            _ = content.importMemes(from: panel.urls)
        }
    }
}

private struct MemeThumbnail: View {
    let url: URL
    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage).resizable().scaledToFill()
        } else {
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Notepad Messages Manager

struct NotepadMessagesPage: View {
    @ObservedObject private var content = UserContentManager.shared
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared
    @State private var showNewSheet = false
    @State private var newFilename = ""
    @State private var newBody = ""

    var body: some View {
        SettingsCard(L("Notepad Delivery")) {
            ToggleRow(title: L("Enable Notepad Deliveries"), subtitle: L("The goose walks to a screen edge and drags an interactive Notepad window onto your desktop."), isOn: $settings.notepadDeliveriesEnabled)
            RowDivider()
            SliderRow(title: L("Minimum Delivery Interval"), value: $settings.notepadMinInterval, range: 5...180, step: 5, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Maximum Delivery Interval"), value: $settings.notepadMaxInterval, range: 15...300, step: 5, format: Fmt.seconds)
            RowDivider()
            SettingRow(title: L("Max Visible Notepads")) {
                Stepper(value: $settings.maxVisibleNotepads, in: 1...8) {
                    Text("\(settings.maxVisibleNotepads)").monospacedDigit().frame(width: 24, alignment: .trailing)
                }
            }
            RowDivider()
            SliderRow(title: L("Notepad Lifetime (0 = Stay)"), value: $settings.notepadLifetime, range: 0...180, step: 5, format: { $0 == 0 ? L("Forever") : Fmt.seconds($0) })
            RowDivider()
            ToggleRow(title: L("Prevent Repeated Messages"), isOn: $settings.preventRepeatedMessages)
            RowDivider()
            SliderRow(title: L("Delivery Animation Speed"), value: $settings.deliveryAnimationSpeed, range: 0.4...2.5, step: 0.05, format: Fmt.multiplier)
        }

        SettingsCard(L("Custom Notepad Messages (.txt)")) {
            HStack(spacing: 8) {
                Button(L("New Message…")) {
                    newFilename = "note-\(content.notepadMessages.count + 1).txt"
                    newBody = ""
                    showNewSheet = true
                }
                Button(L("Import .txt…")) { importTxtPanel() }
                Button(L("Deliver Notepad Now")) { controller.deliverNotepadNow() }
                Button(L("Open Folder")) { content.openUserContentInFinder() }
                Spacer()
            }
            .padding(16)

            ForEach(Array(content.notepadMessages.enumerated()), id: \.element.id) { idx, msg in
                if idx >= 0 { RowDivider() }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(msg.filename).font(.callout.weight(.semibold))
                        Text(msg.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        content.deleteNotepadMessage(msg)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .sheet(isPresented: $showNewSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("New Notepad Message")).font(.headline)
                TextField(L("Filename (.txt)"), text: $newFilename).textFieldStyle(.roundedBorder)
                TextEditor(text: $newBody)
                    .font(.body)
                    .frame(width: 360, height: 140)
                    .border(Color.secondary.opacity(0.3))
                HStack {
                    Spacer()
                    Button(L("Cancel")) { showNewSheet = false }
                    Button(L("Save")) {
                        content.saveNotepadMessage(filename: newFilename, content: newBody)
                        showNewSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
    }

    private func importTxtPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK {
            _ = content.importNotepadMessages(from: panel.urls)
        }
    }
}

// MARK: - Personality Packs Manager

struct PersonalityPacksPage: View {
    @ObservedObject private var content = UserContentManager.shared
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var stats = GooseStats.shared
    @State private var previewPack: PhrasePack?

    var body: some View {
        SettingsCard(L("Personality Style")) {
            SettingRow(title: L("Personality Category")) {
                Picker("", selection: $settings.personalityCategory) {
                    ForEach(GoosePersonalityCategory.allCases) { cat in
                        Text(L(cat.title)).tag(cat)
                    }
                }
                .labelsHidden().frame(width: 210)
            }
            RowDivider()
            SliderRow(title: L("Naughty"), value: $settings.naughty, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Aggressive"), value: $settings.aggressive, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Lazy"), value: $settings.laziness, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Curious"), value: $settings.curious, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Affectionate"), value: $settings.affectionate, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            ToggleRow(title: L("Personality Evolution"), isOn: $settings.personalityEvolution)
            RowDivider()
            ToggleRow(title: L("Interaction Memory"), isOn: $settings.interactionMemory)
            RowDivider()
            SettingRow(title: "\(L("Pats")): \(stats.patCount)   \(L("Pokes")): \(stats.pokeCount)   \(L("Windows closed")): \(stats.windowsClosedCount)") {
                Button(L("Clear Memory")) { stats.clearMemory() }
            }
        }

        SettingsCard(L("Phrase Packs (UserContent/PhrasePacks)")) {
            HStack(spacing: 8) {
                Button(L("Import Phrase Pack…")) { importPackPanel() }
                Button(L("Restore Default Phrases")) { content.restoreDefaultPhrases() }
                Button(L("Open Folder")) { content.openUserContentInFinder() }
                Spacer()
            }
            .padding(16)

            ForEach(Array(content.phrasePacks.enumerated()), id: \.element.id) { _, pack in
                RowDivider()
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { content.isPackEnabled(pack) },
                        set: { content.setPack(pack, enabled: $0) }
                    ))
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.name).font(.body.weight(.medium))
                        Text("\(pack.phrases.count) " + L("phrases"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Preview")) { previewPack = pack }
                    Button(role: .destructive) { content.deletePhrasePack(pack) } label: {
                        Image(systemName: "trash")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .sheet(item: $previewPack) { pack in
            VStack(alignment: .leading, spacing: 12) {
                Text(pack.name).font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pack.phrases, id: \.self) { line in
                            Text("• \(line)").font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 400, height: 240)
                HStack {
                    Spacer()
                    Button(L("Close")) { previewPack = nil }
                }
            }
            .padding(20)
        }
    }

    private func importPackPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK {
            _ = content.importPhrasePacks(from: panel.urls)
        }
    }
}

// MARK: - Smart Screen Observation Page

struct ScreenObservationPage: View {
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var picker = ContentSharingPickerController.shared

    var body: some View {
        SettingsCard(L("Screen Observation Mode")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: Binding(
                    get: { settings.screenObservationMode },
                    set: { permissions.setScreenObservationMode($0) }
                )) {
                    ForEach(ScreenObservationMode.allCases) { mode in
                        Text(L(mode.title)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                HStack(spacing: 8) {
                    StatusDot(on: isActiveIndicatorGreen)
                    Text(L("Status") + ": " + L(permissions.screenObservationStatus.displayTitle))
                        .font(.callout.weight(.medium))
                    Spacer()
                }

                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }

        SettingsCard(L("Actions")) {
            HStack(spacing: 8) {
                Button(L("Enable Screen Observation")) {
                    permissions.setScreenObservationMode(.automaticBackground)
                    permissions.requestScreenRecordingAccess()
                }
                Button(L("Select Screen or Window")) {
                    permissions.setScreenObservationMode(.systemContentPicker)
                    picker.presentPicker()
                }
                if picker.isSharingActive {
                    Button(L("Stop Sharing")) { picker.stopSharing() }
                }
                Button(L("Disable Screen Observation")) {
                    permissions.setScreenObservationMode(.disabled)
                }
                Spacer()
            }
            .padding(16)

            RowDivider()
            ToggleRow(
                title: L("Don't ask automatically again"),
                subtitle: L("Super Goose will never initiate a Screen Recording prompt unless you explicitly press Enable Screen Observation."),
                isOn: $settings.dontAskScreenPermissionAutomatically
            )
            RowDivider()
            SettingRow(title: L("System Settings")) {
                HStack(spacing: 8) {
                    Button(L("Recheck")) { permissions.refreshAll(validateLiveAX: true) }
                    Button(L("Open Screen Recording Settings")) { permissions.openScreenRecordingSettings() }
                }
            }
        }

        SettingsCard(L("macOS Privacy Disclosure")) {
            Text(L("Note: macOS itself controls periodic system security reauthorization reminders when automatic background capture is enabled. Choosing Completely Disabled stops all ScreenCaptureKit capture and OCR while keeping animations, sounds, memes, and notepads fully functional."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(16)
        }
        .onAppear { permissions.refreshScreenObservationStatus() }
    }

    private var isActiveIndicatorGreen: Bool {
        switch permissions.screenObservationStatus {
        case .enabled, .userSelectedScreen: return true
        default: return false
        }
    }

    private var modeExplanation: String {
        switch settings.screenObservationMode {
        case .automaticBackground:
            return L("Mode A: Uses ScreenCaptureKit + local Vision OCR when authorized. Never spams CGRequestScreenCaptureAccess() automatically.")
        case .systemContentPicker:
            return L("Mode B: Uses Apple's official SCContentSharingPicker so only the display or window you select is observed while sharing is active.")
        case .disabled:
            return L("Mode C: Completely disables ScreenCaptureKit, screenshots, and OCR. Zero capture streams or permission requests are triggered.")
        }
    }
}

private func handleFileDrop(_ providers: [NSItemProvider], handler: @escaping @MainActor ([URL]) -> Void) -> Bool {
    final class Collector: @unchecked Sendable {
        let lock = NSLock()
        var urls: [URL] = []
        func append(_ url: URL) {
            lock.lock(); urls.append(url); lock.unlock()
        }
    }
    let collector = Collector()
    let group = DispatchGroup()
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(url)
                } else if let url = item as? URL {
                    collector.append(url)
                }
                group.leave()
            }
        }
    }
    group.notify(queue: .main) {
        let result = collector.urls
        if !result.isEmpty {
            Task { @MainActor in handler(result) }
        }
    }
    return !providers.isEmpty
}
