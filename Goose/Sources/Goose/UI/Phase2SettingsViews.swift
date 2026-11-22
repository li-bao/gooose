import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 1. Meme Library Page

struct MemeLibraryPage: View {
    @ObservedObject private var store = MemeLibraryStore.shared
    @ObservedObject private var content = UserContentManager.shared
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var isGridView = true
    @State private var isDropTargeted = false
    @State private var editingMeta: MemeMetadata?
    @State private var previewMeta: MemeMetadata?
    @State private var showAddCategory = false
    @State private var newCategoryName = ""

    private var filtered: [MemeMetadata] {
        store.filteredMemes(search: searchText, category: selectedCategory)
    }

    var body: some View {
        SettingsCard(L("Personal Meme Library")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Import PNG, JPG, JPEG, WEBP, or animated GIF memes. Files stay strictly local on your Mac."))
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(L("Import Memes…")) { importMemesPanel() }
                    Button(L("Add Category…")) {
                        newCategoryName = ""
                        showAddCategory = true
                    }
                    Button(L("Open Folder")) { content.openUserContentInFinder() }
                    Button(L("Deliver Random")) { controller.deliverMemeNow() }
                        .disabled(store.items.isEmpty)
                    Spacer()
                    Picker("", selection: $isGridView) {
                        Image(systemName: "square.grid.2x2").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 72)
                }

                HStack(spacing: 8) {
                    TextField(L("Search memes or tags…"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $selectedCategory) {
                        Text(L("All")).tag("All")
                        ForEach(store.allCategories, id: \.self) { cat in
                            Text(L(cat)).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                dropZone

                if let err = store.lastError ?? content.lastErrorMessage {
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

        SettingsCard("\(L("Collection")) (\(filtered.count))") {
            if filtered.isEmpty {
                Text(L("No memes match the current filter."))
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else if isGridView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { meta in
                        MemeGridCard(
                            meta: meta,
                            fileItem: store.memeItem(for: meta),
                            onPreview: { previewMeta = meta },
                            onEdit: { editingMeta = meta },
                            onDeliver: {
                                if let file = store.memeItem(for: meta) {
                                    store.recordUsage(for: meta.id)
                                    controller.deliverMeme(file)
                                }
                            },
                            onDelete: { store.deleteMeme(meta) }
                        )
                    }
                }
                .padding(16)
            } else {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, meta in
                    if idx > 0 { RowDivider() }
                    MemeListRow(
                        meta: meta,
                        fileItem: store.memeItem(for: meta),
                        canMoveUp: idx > 0,
                        canMoveDown: idx < filtered.count - 1,
                        onMoveUp: { moveItem(meta, offset: -1) },
                        onMoveDown: { moveItem(meta, offset: 1) },
                        onPreview: { previewMeta = meta },
                        onEdit: { editingMeta = meta },
                        onDeliver: {
                            if let file = store.memeItem(for: meta) {
                                store.recordUsage(for: meta.id)
                                controller.deliverMeme(file)
                            }
                        },
                        onDelete: { store.deleteMeme(meta) }
                    )
                }
            }
        }
        .sheet(item: $editingMeta) { meta in
            MemeEditSheet(meta: meta, categories: store.allCategories) { updated, newFilename in
                if let newFilename, newFilename != (meta.filename as NSString).deletingPathExtension {
                    store.renameMeme(meta, to: newFilename)
                }
                store.updateMetadata(updated)
            }
        }
        .sheet(item: $previewMeta) { meta in
            MemePreviewSheet(meta: meta, fileItem: store.memeItem(for: meta))
        }
        .sheet(isPresented: $showAddCategory) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("New Meme Category")).font(.headline)
                TextField(L("Category Name"), text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Spacer()
                    Button(L("Cancel")) { showAddCategory = false }
                    Button(L("Add")) {
                        store.addCustomCategory(newCategoryName)
                        selectedCategory = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        showAddCategory = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            Text(L("Drop PNG, JPG, JPEG, WEBP, or GIF files here"))
                .font(.callout).foregroundStyle(.secondary)
                .padding(.vertical, 16)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleMemeFileDrop(providers) { urls in
                let cat = selectedCategory == "All" ? "Random Memes" : selectedCategory
                _ = store.importMemes(from: urls, category: cat)
            }
        }
    }

    private func moveItem(_ meta: MemeMetadata, offset: Int) {
        guard let idx = store.items.firstIndex(where: { $0.id == meta.id }) else { return }
        let dest = idx + offset
        guard dest >= 0, dest < store.items.count else { return }
        store.reorder(fromOffsets: IndexSet(integer: idx), toOffset: offset > 0 ? dest + 1 : dest)
    }

    private func importMemesPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        if panel.runModal() == .OK {
            let cat = selectedCategory == "All" ? "Random Memes" : selectedCategory
            _ = store.importMemes(from: panel.urls, category: cat)
        }
    }
}

private struct MemeGridCard: View {
    let meta: MemeMetadata
    let fileItem: MemeItem?
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onDeliver: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncThumbView(url: fileItem?.url)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture(perform: onPreview)

                if fileItem?.isAnimatedGIF == true {
                    Text("GIF")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }

            Text(meta.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(meta.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if meta.manualOnly {
                    Text(L("Manual"))
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
                if !meta.enabled {
                    Text(L("Off"))
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
            }

            HStack(spacing: 6) {
                Button(action: onDeliver) { Image(systemName: "paperplane") }
                    .buttonStyle(.borderless)
                    .help(L("Deliver Now"))
                Button(action: onEdit) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless)
                    .help(L("Edit"))
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MemeListRow: View {
    let meta: MemeMetadata
    let fileItem: MemeItem?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onDeliver: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncThumbView(url: fileItem?.url)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture(perform: onPreview)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(meta.displayName).font(.body.weight(.medium))
                    Text(meta.category)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                    if meta.manualOnly {
                        Text(L("Manual Only"))
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.18), in: Capsule())
                    }
                }
                Text("\(L("Weight")): \(String(format: "%.1fx", meta.weight)) · \(L("Used")): \(meta.usageCount)×")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onMoveUp) { Image(systemName: "arrow.up") }.disabled(!canMoveUp)
            Button(action: onMoveDown) { Image(systemName: "arrow.down") }.disabled(!canMoveDown)
            Button(L("Deliver")) { onDeliver() }
            Button(L("Edit")) { onEdit() }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

private struct MemeEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MemeMetadata
    @State private var renameBase: String
    @State private var tagsText: String
    let categories: [String]
    let onSave: (MemeMetadata, String?) -> Void

    init(meta: MemeMetadata, categories: [String], onSave: @escaping (MemeMetadata, String?) -> Void) {
        self._draft = State(initialValue: meta)
        self._renameBase = State(initialValue: (meta.filename as NSString).deletingPathExtension)
        self._tagsText = State(initialValue: meta.tags.joined(separator: ", "))
        self.categories = categories
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Edit Meme")).font(.headline)
            TextField(L("Display Name"), text: $draft.displayName).textFieldStyle(.roundedBorder)
            TextField(L("Filename"), text: $renameBase).textFieldStyle(.roundedBorder)
            Picker(L("Category"), selection: $draft.category) {
                ForEach(categories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            TextField(L("Tags (comma separated)"), text: $tagsText).textFieldStyle(.roundedBorder)
            Toggle(L("Enabled for Goose"), isOn: $draft.enabled)
            Toggle(L("Manual Trigger Only (never auto-spawn)"), isOn: $draft.manualOnly)
            HStack {
                Text(L("Appearance Weight"))
                Slider(value: $draft.weight, in: 0.1...5.0, step: 0.1)
                Text(String(format: "%.1fx", draft.weight)).monospacedDigit().frame(width: 40)
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }
                Button(L("Save")) {
                    draft.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    onSave(draft, renameBase)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct MemePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meta: MemeMetadata
    let fileItem: MemeItem?

    var body: some View {
        VStack(spacing: 12) {
            Text(meta.displayName).font(.headline)
            if let url = fileItem?.url {
                AnimatedMemeNSView(url: url)
                    .frame(width: 360, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text(L("File missing from disk.")).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(meta.category) · \(L("Used")) \(meta.usageCount)×").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Close")) { dismiss() }
            }
        }
        .padding(20)
    }
}

private struct AnimatedMemeNSView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.animates = true
        iv.image = NSImage(contentsOf: url)
        return iv
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(contentsOf: url)
    }
}

private struct AsyncThumbView: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await Task.detached(priority: .utility) {
                NSImage(contentsOf: url)
            }.value
        }
    }
}

// MARK: - 2. Taunt Library Page

struct TauntLibraryPage: View {
    @ObservedObject private var store = TauntLibraryStore.shared
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var controller = GooseController.shared

    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var editingEntry: TauntEntry?
    @State private var showNewSheet = false
    @State private var newContent = ""
    @State private var newCategory = "Sarcasm"
    @State private var newWeight = 1.0
    @State private var showAddCategory = false
    @State private var newCategoryName = ""

    private var filtered: [TauntEntry] {
        store.filteredTaunts(search: searchText, category: selectedCategory)
    }

    var body: some View {
        SettingsCard(L("Custom Taunt Library")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Create, weight, and organize custom taunts. Goose drags these out inside an interactive Memo Editor window."))
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(L("Add Taunt…")) {
                        newContent = ""
                        newCategory = selectedCategory == "All" ? "Sarcasm" : selectedCategory
                        newWeight = 1.0
                        showNewSheet = true
                    }
                    Button(L("Add Category…")) {
                        newCategoryName = ""
                        showAddCategory = true
                    }
                    Button(L("Deliver Random Memo")) { controller.deliverNotepadNow() }
                    Spacer()
                    Text("\(filtered.count) " + L("items")).font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField(L("Search taunts…"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $selectedCategory) {
                        Text(L("All")).tag("All")
                        ForEach(store.allCategories, id: \.self) { cat in
                            Text(L(cat)).tag(cat)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                if selectedCategory != "All" {
                    Toggle(
                        L("Enable Category") + ": \(selectedCategory)",
                        isOn: Binding(
                            get: { store.isCategoryEnabled(selectedCategory) },
                            set: { _ in store.toggleCategoryDisabled(selectedCategory) }
                        )
                    )
                }
            }
            .padding(16)
        }

        SettingsCard(L("Memo Delivery Settings")) {
            ToggleRow(title: L("Enable Notepad Deliveries"), isOn: $settings.notepadDeliveriesEnabled)
            RowDivider()
            SliderRow(title: L("Notepad Lifetime (0 = Stay)"), value: $settings.notepadLifetime, range: 0...180, step: 5, format: { $0 == 0 ? L("Forever") : Fmt.seconds($0) })
            RowDivider()
            SettingRow(title: L("Max Visible Notepads")) {
                Stepper(value: $settings.maxVisibleNotepads, in: 1...8) {
                    Text("\(settings.maxVisibleNotepads)").monospacedDigit().frame(width: 24, alignment: .trailing)
                }
            }
        }

        SettingsCard(L("Taunts")) {
            if filtered.isEmpty {
                Text(L("No taunts match your filter.")).foregroundStyle(.secondary).padding(16)
            } else {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                    if idx > 0 { RowDivider() }
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { entry.enabled },
                            set: { val in
                                var copy = entry
                                copy.enabled = val
                                store.updateTaunt(copy)
                            }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.content).font(.body)
                            HStack(spacing: 8) {
                                Text(entry.category)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.secondary.opacity(0.15), in: Capsule())
                                Text("\(L("Weight")): \(String(format: "%.1fx", entry.weight)) · \(L("Used")): \(entry.usageCount)×")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(L("Preview")) {
                            _ = GooseNotepadWindow.showPreview(title: "\(entry.category).txt", body: entry.content)
                        }
                        Button(L("Deliver")) {
                            store.recordUsage(for: entry.id)
                            controller.deliverTaunt(entry.content, title: "\(entry.category).txt")
                        }
                        Button(action: { _ = store.duplicateTaunt(entry) }) { Image(systemName: "doc.on.doc") }
                            .help(L("Duplicate"))
                        Button(action: { editingEntry = entry }) { Image(systemName: "pencil") }
                        Button(role: .destructive) { store.deleteTaunt(entry) } label: { Image(systemName: "trash") }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
        .sheet(isPresented: $showNewSheet) {
            TauntEditorSheet(
                title: L("New Taunt"),
                content: $newContent,
                category: $newCategory,
                weight: $newWeight,
                categories: store.allCategories
            ) {
                _ = store.addTaunt(content: newContent, category: newCategory, weight: newWeight)
                showNewSheet = false
            } onCancel: {
                showNewSheet = false
            }
        }
        .sheet(item: $editingEntry) { entry in
            TauntEditExistingSheet(entry: entry, categories: store.allCategories) { updated in
                store.updateTaunt(updated)
            }
        }
        .sheet(isPresented: $showAddCategory) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("New Taunt Category")).font(.headline)
                TextField(L("Category Name"), text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Spacer()
                    Button(L("Cancel")) { showAddCategory = false }
                    Button(L("Add")) {
                        store.addCategory(newCategoryName)
                        selectedCategory = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        showAddCategory = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
    }
}

private struct TauntEditorSheet: View {
    let title: String
    @Binding var content: String
    @Binding var category: String
    @Binding var weight: Double
    let categories: [String]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Picker(L("Category"), selection: $category) {
                ForEach(categories, id: \.self) { cat in Text(cat).tag(cat) }
            }
            TextEditor(text: $content)
                .font(.body)
                .frame(width: 380, height: 130)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Text(L("Appearance Weight"))
                Slider(value: $weight, in: 0.1...5.0, step: 0.1)
                Text(String(format: "%.1fx", weight)).monospacedDigit().frame(width: 40)
            }
            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel)
                Button(L("Save"), action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}

private struct TauntEditExistingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TauntEntry
    let categories: [String]
    let onSave: (TauntEntry) -> Void

    init(entry: TauntEntry, categories: [String], onSave: @escaping (TauntEntry) -> Void) {
        self._draft = State(initialValue: entry)
        self.categories = categories
        self.onSave = onSave
    }

    var body: some View {
        TauntEditorSheet(
            title: L("Edit Taunt"),
            content: $draft.content,
            category: $draft.category,
            weight: $draft.weight,
            categories: categories,
            onSave: {
                onSave(draft)
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}

// MARK: - 3. Animation Studio Page

struct AnimationStudioPage: View {
    @ObservedObject private var store = AnimationStudioStore.shared

    var body: some View {
        SettingsCard(L("Entry Animation")) {
            SettingRow(title: L("Entry Style")) {
                Picker("", selection: $store.settings.entryStyle) {
                    ForEach(MemoEntryStyle.allCases) { style in
                        Text(L(style.title)).tag(style)
                    }
                }
                .labelsHidden().frame(width: 190)
            }
            RowDivider()
            SliderRow(title: L("Entry Duration"), value: $store.settings.entryDuration, range: 1.5...3.0, step: 0.1, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Movement Speed"), value: $store.settings.movementSpeed, range: 0.5...2.0, step: 0.05, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Paper Rotation"), value: $store.settings.rotationDegrees, range: 0...8, step: 0.5, format: { String(format: "%.1f°", $0) })
            RowDivider()
            SliderRow(title: L("Landing Bounce"), value: $store.settings.bounceIntensity, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Goose Drag Offset"), value: $store.settings.dragOffset, range: 0...40, step: 2, format: { "\(Int($0))px" })
            RowDivider()
            SettingRow(title: L("Ease Curve")) {
                Picker("", selection: $store.settings.easeCurve) {
                    ForEach(MemoEaseCurve.allCases) { curve in
                        Text(L(curve.title)).tag(curve)
                    }
                }
                .labelsHidden().frame(width: 190)
            }
        }

        SettingsCard(L("Exit Animation")) {
            SettingRow(title: L("Exit Style")) {
                Picker("", selection: $store.settings.exitStyle) {
                    ForEach(MemoExitStyle.allCases) { style in
                        Text(L(style.title)).tag(style)
                    }
                }
                .labelsHidden().frame(width: 190)
            }
            RowDivider()
            SliderRow(title: L("Exit Duration"), value: $store.settings.exitDuration, range: 0.3...2.0, step: 0.05, format: Fmt.seconds)
            RowDivider()
            SliderRow(title: L("Fade Speed"), value: $store.settings.fadeSpeed, range: 0.5...2.0, step: 0.1, format: Fmt.multiplier)
            RowDivider()
            SliderRow(title: L("Exit Rotation"), value: $store.settings.exitRotationDegrees, range: 0...10, step: 0.5, format: { String(format: "%.1f°", $0) })
            RowDivider()
            ToggleRow(title: L("Randomize Exit Style"), isOn: $store.settings.randomizeExit)
        }

        SettingsCard(L("Preview")) {
            HStack(spacing: 10) {
                Button(L("Preview Entry & Exit Animation")) {
                    let taunt = TauntLibraryStore.shared.pickWeightedTaunt()?.content ?? "Previewing Goose Memo Editor animation! 🪿"
                    _ = GooseNotepadWindow.showPreview(title: "Animation Preview", body: taunt)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button(L("Reset Defaults")) { store.resetDefaults() }
            }
            .padding(16)
        }
    }
}

// MARK: - 4. Audio Packs & Quiet Hours Page

struct AudioPacksPage: View {
    @ObservedObject private var packManager = AudioPackManager.shared
    @ObservedObject private var settings = GooseSettings.shared
    @State private var selectedEvent: AudioPackEvent = .gooseHonk
    @State private var showNewPack = false
    @State private var newPackName = ""

    private let weekdayNames = [(1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat")]

    var body: some View {
        SettingsCard(L("Master Audio & Honk Cooldown")) {
            ToggleRow(title: L("Master Sound"), isOn: $settings.masterSoundEnabled)
            RowDivider()
            ToggleRow(title: L("Mute Goose"), isOn: $settings.muteGoose)
            RowDivider()
            SliderRow(title: L("Master Volume"), value: $settings.masterVolume, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            SliderRow(title: L("Honk Volume"), value: $settings.honkVolume, range: 0...1, step: 0.05, format: Fmt.percent)
            RowDivider()
            ToggleRow(title: L("Sound Effects"), isOn: $settings.soundEffects)
            RowDivider()
            ToggleRow(title: L("Enable Honking"), isOn: Binding(
                get: { settings.isEnabled(.honking) && settings.gooseSoundsEnabled },
                set: { on in
                    settings.setEnabled(.honking, on)
                    settings.gooseSoundsEnabled = on
                }
            ))
            RowDivider()
            ToggleRow(title: L("Random Honking"), isOn: $settings.randomHonking)
            RowDivider()
            SettingRow(title: L("Random Honk Frequency")) {
                Picker("", selection: $settings.randomHonkFrequency) {
                    Text(L("Off")).tag(RandomHonkFrequency.off)
                    Text(L("Low")).tag(RandomHonkFrequency.low)
                    Text(L("Medium")).tag(RandomHonkFrequency.medium)
                    Text(L("High")).tag(RandomHonkFrequency.high)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            }
            RowDivider()
            SliderRow(title: L("Honk Cooldown"), value: $settings.honkCooldown, range: 5...90, step: 5, format: Fmt.seconds)
        }

        SettingsCard(L("Custom Audio Packs")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker(L("Active Pack"), selection: $packManager.activePackID) {
                        ForEach(packManager.packs) { pack in
                            Text(pack.name).tag(pack.id)
                        }
                    }
                    .frame(width: 240)
                    Button(L("New Pack…")) {
                        newPackName = ""
                        showNewPack = true
                    }
                    if let active = packManager.activePack, !active.isBuiltIn {
                        Button(role: .destructive) {
                            packManager.deletePack(active.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Picker(L("Event"), selection: $selectedEvent) {
                        ForEach(AudioPackEvent.allCases) { ev in
                            Text(L(ev.title)).tag(ev)
                        }
                    }
                    .frame(width: 220)
                    Button(L("Import Sound (WAV/MP3/M4A/AIFF)…")) { importSoundPanel() }
                    Button(L("Test Duck")) { _ = SoundEffectEngine.shared.playDuck(.happyQuack, cooldown: 0) }
                    Button(L("Test Honk")) { _ = SoundEffectEngine.shared.playGoose(.classicHonk, cooldown: 0) }
                }

                if let err = packManager.lastError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)

            if let active = packManager.activePack {
                if active.sounds.isEmpty {
                    RowDivider()
                    Text(L("No custom sounds in this pack yet. Procedural DSP synthesis is active as fallback."))
                        .font(.caption).foregroundStyle(.secondary).padding(16)
                } else {
                    ForEach(active.sounds) { sound in
                        RowDivider()
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { sound.enabled },
                                set: { val in
                                    var copy = sound
                                    copy.enabled = val
                                    packManager.updateSound(copy, inPackID: active.id)
                                }
                            ))
                            .labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sound.name).font(.body.weight(.medium))
                                Text("\(sound.event.title) · \(sound.filename)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Slider(
                                value: Binding(
                                    get: { sound.volume },
                                    set: { val in
                                        var copy = sound
                                        copy.volume = val
                                        packManager.updateSound(copy, inPackID: active.id)
                                    }
                                ),
                                in: 0...1
                            )
                            .frame(width: 90)
                            Button(action: { _ = packManager.previewSound(sound) }) { Image(systemName: "play.fill") }
                            Button(role: .destructive) {
                                packManager.deleteSound(sound, fromPackID: active.id)
                            } label: { Image(systemName: "trash") }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewPack) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("New Audio Pack")).font(.headline)
                TextField(L("Pack Name"), text: $newPackName).textFieldStyle(.roundedBorder).frame(width: 260)
                HStack {
                    Spacer()
                    Button(L("Cancel")) { showNewPack = false }
                    Button(L("Create")) {
                        _ = packManager.createPack(name: newPackName)
                        showNewPack = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }

        SettingsCard(L("Quiet Hours")) {
            ToggleRow(title: L("Enable Quiet Hours"), isOn: $packManager.quietHours.enabled)
            RowDivider()
            SettingRow(title: L("Start Time")) {
                HStack(spacing: 4) {
                    Picker("", selection: $packManager.quietHours.startHour) {
                        ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d", h)).tag(h) }
                    }.labelsHidden().frame(width: 65)
                    Text(":")
                    Picker("", selection: $packManager.quietHours.startMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { m in Text(String(format: "%02d", m)).tag(m) }
                    }.labelsHidden().frame(width: 65)
                }
            }
            RowDivider()
            SettingRow(title: L("End Time")) {
                HStack(spacing: 4) {
                    Picker("", selection: $packManager.quietHours.endHour) {
                        ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d", h)).tag(h) }
                    }.labelsHidden().frame(width: 65)
                    Text(":")
                    Picker("", selection: $packManager.quietHours.endMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { m in Text(String(format: "%02d", m)).tag(m) }
                    }.labelsHidden().frame(width: 65)
                }
            }
            RowDivider()
            SettingRow(title: L("Active Days")) {
                HStack(spacing: 4) {
                    ForEach(weekdayNames, id: \.0) { day, label in
                        let on = packManager.quietHours.weekdays.contains(day)
                        Button(L(label)) {
                            if on {
                                packManager.quietHours.weekdays.remove(day)
                            } else {
                                packManager.quietHours.weekdays.insert(day)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(on ? .accentColor : .secondary.opacity(0.3))
                        .controlSize(.small)
                    }
                }
            }
            RowDivider()
            SettingRow(title: L("Quiet Mode Behavior")) {
                Picker("", selection: $packManager.quietHours.mode) {
                    ForEach(QuietHoursMode.allCases) { mode in
                        Text(L(mode.title)).tag(mode)
                    }
                }
                .labelsHidden().frame(width: 220)
            }
        }
    }

    private func importSoundPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.wav, .mp3, .mpeg4Audio, .aiff]
        if panel.runModal() == .OK {
            _ = packManager.importSounds(from: panel.urls, for: selectedEvent)
        }
    }
}

// MARK: - 5. Prank Presets Page

struct PrankPresetsPage: View {
    @ObservedObject private var manager = PrankPresetManager.shared
    @State private var showNewPreset = false
    @State private var newPresetName = ""

    var body: some View {
        SettingsCard(L("Built-in Prank Presets")) {
            ForEach(Array(manager.builtInPresets.enumerated()), id: \.element.id) { idx, preset in
                if idx > 0 { RowDivider() }
                presetRow(preset)
            }
        }

        SettingsCard(L("Custom Presets")) {
            HStack {
                Button(L("Save Current Settings as Preset…")) {
                    newPresetName = ""
                    showNewPreset = true
                }
                Spacer()
            }
            .padding(16)

            if manager.customPresets.isEmpty {
                RowDivider()
                Text(L("No custom presets yet. Duplicate a built-in preset or save your current settings."))
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            } else {
                ForEach(manager.customPresets) { preset in
                    RowDivider()
                    presetRow(preset)
                }
            }
        }
        .sheet(isPresented: $showNewPreset) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("New Prank Preset")).font(.headline)
                TextField(L("Preset Name"), text: $newPresetName).textFieldStyle(.roundedBorder).frame(width: 260)
                HStack {
                    Spacer()
                    Button(L("Cancel")) { showNewPreset = false }
                    Button(L("Save")) {
                        _ = manager.createCustomPreset(name: newPresetName)
                        showNewPreset = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private func presetRow(_ preset: PrankPreset) -> some View {
        let isActive = manager.activePresetID == preset.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L(preset.name)).font(.body.weight(.semibold))
                    if isActive {
                        Text(L("Active"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
                Text(L(preset.summary)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Apply")) { manager.applyPreset(preset) }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .green : .accentColor)
            Button(action: { _ = manager.duplicatePreset(preset) }) { Image(systemName: "doc.on.doc") }
                .help(L("Duplicate"))
            if !preset.isBuiltIn {
                Button(role: .destructive) { manager.deleteCustomPreset(preset) } label: { Image(systemName: "trash") }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - 6. Live Emotion & Energy Card (embedded in Emotion & Behavior tab)

struct EmotionEnergyStatusCard: View {
    @ObservedObject private var controller = GooseController.shared

    var body: some View {
        SettingsCard(L("Goose Emotion & Energy")) {
            if controller.geese.isEmpty {
                Text(L("No active geese.")).foregroundStyle(.secondary).padding(16)
            } else {
                ForEach(Array(controller.geese.enumerated()), id: \.element.id) { idx, g in
                    if idx > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Image(systemName: g.emotion.badgeSymbol)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(g.name) — \(L(g.emotion.title))").font(.body.weight(.medium))
                            Text(g.activity).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProgressView(value: Double(g.energyPercent), total: 100.0)
                            .frame(width: 90)
                        Text("\(g.energyPercent)%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
    }
}

private func handleMemeFileDrop(_ providers: [NSItemProvider], onURLs: @escaping ([URL]) -> Void) -> Bool {
    final class URLCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func append(_ url: URL) {
            lock.lock(); defer { lock.unlock() }
            urls.append(url)
        }
        func snapshot() -> [URL] {
            lock.lock(); defer { lock.unlock() }
            return urls
        }
    }
    let collector = URLCollector()
    let group = DispatchGroup()
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                collector.append(url)
            }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        let collected = collector.snapshot()
        if !collected.isEmpty {
            onURLs(collected)
        }
    }
    return !providers.isEmpty
}
