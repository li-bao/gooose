import AppKit

@MainActor
final class NotepadWindowRegistry {
    static let shared = NotepadWindowRegistry()
    private var active: [GooseNotepadWindow] = []

    var count: Int {
        active.removeAll { !$0.isVisible }
        return active.count
    }

    func register(_ window: GooseNotepadWindow, maxVisible: Int) {
        active.removeAll { !$0.isVisible }
        while active.count >= max(1, maxVisible) {
            let oldest = active.removeFirst()
            oldest.close()
        }
        active.append(window)
    }

    func unregister(_ window: GooseNotepadWindow) {
        active.removeAll { $0 === window }
    }

    func closeAll() {
        let copy = active
        active.removeAll()
        for w in copy { w.close() }
    }
}

/// Dedicated interactive Desktop Goose Notepad window dragged onto the screen
/// from outside the display bounds by `NotepadDeliveryTask`.
@MainActor
final class GooseNotepadWindow: NSWindow {
    let noteTitle: String
    let noteBody: String
    let targetSize: CGSize

    private let copyButton = NSButton()
    private var lifetimeTimer: Timer?

    init(title: String, body: String, size: CGSize = CGSize(width: 280, height: 195)) {
        self.noteTitle = title
        self.noteBody = body
        self.targetSize = size

        super.init(
            contentRect: NSRect(origin: CGPoint(x: -2000, y: -2000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        buildUI(size: size)
    }

    private func buildUI(size: CGSize) {
        let paperView = PaperBackgroundView(frame: NSRect(origin: .zero, size: size))
        paperView.wantsLayer = true
        paperView.layer?.cornerRadius = 11
        paperView.layer?.masksToBounds = true
        paperView.layer?.borderWidth = 1

        let headerH: CGFloat = 30
        let header = NSView(frame: NSRect(x: 0, y: size.height - headerH, width: size.width, height: headerH))

        let titleField = NSTextField(labelWithString: "🪿 \(noteTitle)")
        titleField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        titleField.textColor = .secondaryLabelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: 10, y: 6, width: size.width - 96, height: 18)
        header.addSubview(titleField)

        copyButton.frame = NSRect(x: size.width - 80, y: 4, width: 50, height: 22)
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.title = L("Copy")
        copyButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        header.addSubview(copyButton)

        let closeButton = NSButton(frame: NSRect(x: size.width - 26, y: 4, width: 20, height: 20))
        closeButton.bezelStyle = .circular
        closeButton.title = "×"
        closeButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        header.addSubview(closeButton)

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: size.width - 20, height: size.height - headerH - 12))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.string = noteBody
        textView.textContainerInset = NSSize(width: 2, height: 4)
        scroll.documentView = textView

        paperView.addSubview(header)
        paperView.addSubview(scroll)
        contentView = paperView
    }

    func scheduleAutoDismiss(after seconds: TimeInterval) {
        lifetimeTimer?.invalidate()
        guard seconds > 0 else { return }
        lifetimeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.close()
            }
        }
    }

    @objc private func copyClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(noteBody, forType: .string)
        copyButton.title = "✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.title = L("Copy")
        }
    }

    @objc private func closeClicked() {
        close()
    }

    override func close() {
        lifetimeTimer?.invalidate()
        lifetimeTimer = nil
        NotepadWindowRegistry.shared.unregister(self)
        super.close()
    }
}

private final class PaperBackgroundView: NSView {
    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.12, alpha: 0.96).cgColor
            layer?.borderColor = NSColor(calibratedWhite: 0.35, alpha: 0.7).cgColor
        } else {
            layer?.backgroundColor = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.87, alpha: 0.98).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.84, green: 0.78, blue: 0.56, alpha: 0.9).cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }
}
