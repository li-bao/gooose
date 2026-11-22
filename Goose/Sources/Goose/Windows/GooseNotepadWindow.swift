import AppKit
import QuartzCore

typealias GooseMemoEditorWindow = GooseNotepadWindow

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

/// Native interactive macOS Goose Memo Editor window dragged onto the desktop
/// from the screen edge. Supports editable text (Cut/Copy/Paste/Undo/Select All),
/// resizing, native titlebar controls, and optional PNG/JPG/JPEG/WEBP/animated GIF
/// meme content in the same container.
@MainActor
final class GooseNotepadWindow: NSWindow {
    let noteTitle: String
    let noteBody: String
    let memeItem: MemeItem?
    let targetSize: CGSize

    private let copyButton = NSButton()
    private let textView = NSTextView()
    private let imageView = NSImageView()
    private var decodedGIF: DecodedGIFFrames?
    private var gifFrameIndex = 0
    private var gifTimer: Timer?
    private var lifetimeTimer: Timer?
    private var previewTask: Task<Void, Never>?
    private var isClosed = false

    private(set) var isInteractive: Bool = true

    override var canBecomeKey: Bool { isInteractive }
    override var canBecomeMain: Bool { isInteractive }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Allow smooth edge-drag entry/exit without AppKit snapping the titled window away from the edge.
        if !isInteractive {
            return frameRect
        }
        return super.constrainFrameRect(frameRect, to: screen)
    }

    /// Exposes the underlying `NSTextView` for automated tests and callers.
    var editorTextView: NSTextView { textView }

    init(
        title: String,
        body: String,
        memeItem: MemeItem? = nil,
        size: CGSize? = nil
    ) {
        self.noteTitle = title
        self.noteBody = body
        self.memeItem = memeItem

        let decoded: DecodedGIFFrames? = memeItem.flatMap { MemeImageDecoder.decode(url: $0.url) }
        self.decodedGIF = decoded

        let resolvedSize: CGSize = {
            if let size { return size }
            if let decoded {
                let w = max(1, decoded.pixelSize.width)
                let h = max(1, decoded.pixelSize.height)
                let scale = min(1.0, 320.0 / max(w, h))
                let contentW = max(280, (w * scale).rounded())
                let extraCaptionH: CGFloat = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 64 : 112
                let contentH = max(220, (h * scale).rounded() + extraCaptionH)
                return CGSize(width: contentW, height: contentH)
            }
            return CGSize(width: 310, height: 225)
        }()
        self.targetSize = resolvedSize

        super.init(
            contentRect: NSRect(origin: CGPoint(x: -2000, y: -2000), size: resolvedSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "🪿 \(title)"
        minSize = CGSize(width: 240, height: 170)
        maxSize = CGSize(width: 720, height: 640)
        hasShadow = true
        level = GooseSettings.shared.memoAlwaysOnTop ? .floating : .normal
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        buildUI(size: resolvedSize, hasMeme: decoded != nil)
        if let decoded, !decoded.frames.isEmpty {
            showGIFFrame(0)
        }
    }

    private func buildUI(size: CGSize, hasMeme: Bool) {
        let root = PaperBackgroundView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true

        let toolbarH: CGFloat = 30
        let toolbar = NSView(frame: NSRect(x: 0, y: size.height - toolbarH, width: size.width, height: toolbarH))
        toolbar.autoresizingMask = [.width, .minYMargin]

        let badge = NSTextField(labelWithString: hasMeme ? L("Goose Memo · Meme") : L("Goose Memo Editor"))
        badge.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.frame = NSRect(x: 12, y: 6, width: size.width - 90, height: 18)
        badge.autoresizingMask = [.width]
        toolbar.addSubview(badge)

        copyButton.frame = NSRect(x: size.width - 66, y: 4, width: 54, height: 22)
        copyButton.autoresizingMask = [.minXMargin]
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.title = L("Copy")
        copyButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        toolbar.addSubview(copyButton)

        root.addSubview(toolbar)

        if hasMeme {
            let captionH: CGFloat = noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 54 : 84
            let imageFrame = NSRect(
                x: 10,
                y: captionH + 10,
                width: size.width - 20,
                height: max(80, size.height - toolbarH - captionH - 14)
            )
            imageView.frame = imageFrame
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 8
            imageView.layer?.masksToBounds = true
            root.addSubview(imageView)

            let scroll = makeScrollableTextView(
                frame: NSRect(x: 10, y: 8, width: size.width - 20, height: captionH - 4),
                placeholderText: noteBody
            )
            scroll.autoresizingMask = [.width, .maxYMargin]
            root.addSubview(scroll)
        } else {
            let scroll = makeScrollableTextView(
                frame: NSRect(x: 10, y: 10, width: size.width - 20, height: size.height - toolbarH - 14),
                placeholderText: noteBody
            )
            scroll.autoresizingMask = [.width, .height]
            root.addSubview(scroll)
        }

        contentView = root
    }

    private func makeScrollableTextView(frame: NSRect, placeholderText: String) -> NSScrollView {
        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        textView.frame = NSRect(origin: .zero, size: scroll.contentSize)
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.string = placeholderText
        textView.textContainerInset = NSSize(width: 4, height: 6)
        scroll.documentView = textView
        return scroll
    }

    override func orderFrontRegardless() {
        level = GooseSettings.shared.memoAlwaysOnTop ? .floating : .normal
        super.orderFrontRegardless()
        startGIFIfNeeded()
    }

    func setInteractive(_ interactive: Bool) {
        isInteractive = interactive
        ignoresMouseEvents = !interactive
        isMovableByWindowBackground = interactive
        textView.isEditable = interactive
        textView.isSelectable = true
    }

    func applyDragVisual(tiltRadians: CGFloat, scale: CGFloat = 1.0) {
        guard let layer = contentView?.layer else { return }
        let bounds = contentView?.bounds ?? .zero
        let cx = bounds.width * 0.5
        let cy = bounds.height * 0.5
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, cx, cy, 0)
        t = CATransform3DRotate(t, tiltRadians, 0, 0, 1)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        layer.transform = t
    }

    func resetDragVisual() {
        contentView?.layer?.transform = CATransform3DIdentity
    }

    // MARK: - GIF Playback

    private func showGIFFrame(_ index: Int) {
        guard let decoded = decodedGIF, index < decoded.frames.count else { return }
        let cg = decoded.frames[index]
        imageView.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func startGIFIfNeeded() {
        guard let decoded = decodedGIF, decoded.isAnimated, !isClosed, gifTimer == nil else { return }
        scheduleNextGIFFrame()
    }

    private func scheduleNextGIFFrame() {
        guard let decoded = decodedGIF, !decoded.delays.isEmpty else { return }
        let delay = decoded.delays[gifFrameIndex % decoded.delays.count]
        gifTimer?.invalidate()
        gifTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed, let decoded = self.decodedGIF else { return }
                if !self.isVisible {
                    self.gifTimer = nil
                    return
                }
                self.gifFrameIndex = (self.gifFrameIndex + 1) % decoded.frames.count
                self.showGIFFrame(self.gifFrameIndex)
                self.scheduleNextGIFFrame()
            }
        }
    }

    // MARK: - Auto-Dismiss & Exit Animations

    func scheduleAutoDismiss(after seconds: TimeInterval) {
        lifetimeTimer?.invalidate()
        guard seconds > 0 else { return }
        lifetimeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                self.dismissWithAnimation()
            }
        }
    }

    func dismissWithAnimation(style: MemoExitStyle? = nil) {
        guard !isClosed else { return }
        let cfg = AnimationStudioStore.shared.settings
        let resolved = style ?? cfg.resolvedExitStyle()
        let duration = max(0.25, cfg.exitDuration / max(0.3, cfg.fadeSpeed))
        let screen = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let current = frame

        var targetFrame = current
        switch resolved {
        case .dragAwayLeft, .gooseTakesItAway:
            targetFrame.origin.x = screen.minX - current.width - 40
        case .dragAwayRight:
            targetFrame.origin.x = screen.maxX + 40
        case .slideDown:
            targetFrame.origin.y = screen.minY - current.height - 40
        case .fadeOut, .randomExit:
            break
        }

        _ = AudioPackManager.shared.playEventSound(.memeExit)
        setInteractive(false)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.close()
            }
        })
    }

    /// Safe non-intrusive preview for Animation Studio & Taunt Library.
    /// Does not touch system cursor or acquire global resource locks.
    @discardableResult
    static func showPreview(title: String, body: String, memeItem: MemeItem? = nil) -> GooseNotepadWindow {
        let win = GooseNotepadWindow(title: title, body: body, memeItem: memeItem)
        let cfg = AnimationStudioStore.shared.settings
        let entry = cfg.resolvedEntryStyle()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let sz = win.frame.size

        let targetOrigin = NSPoint(
            x: screen.midX - sz.width * 0.5,
            y: screen.midY - sz.height * 0.5
        )
        var startOrigin = targetOrigin
        switch entry {
        case .dragFromLeft, .gooseCarry, .randomEdge:
            startOrigin.x = screen.minX - sz.width + 12
        case .dragFromRight:
            startOrigin.x = screen.maxX - 12
        case .dragFromTop:
            startOrigin.y = screen.maxY - 12
        case .dragFromBottom:
            startOrigin.y = screen.minY - sz.height + 12
        }

        win.setInteractive(false)
        win.setFrameOrigin(startOrigin)
        win.orderFrontRegardless()

        let duration = max(0.8, cfg.entryDuration / max(0.5, cfg.movementSpeed))
        win.previewTask = Task { @MainActor [weak win] in
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = duration
                    ctx.allowsImplicitAnimation = true
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    win?.animator().setFrameOrigin(targetOrigin)
                }, completionHandler: {
                    cont.resume()
                })
            }
            win?.setInteractive(true)
            try? await Task.sleep(for: .seconds(1.8))
            if let win, !win.isClosed, !Task.isCancelled {
                win.dismissWithAnimation(style: cfg.resolvedExitStyle())
            }
        }
        return win
    }

    @objc private func copyClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        copyButton.title = "✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.title = L("Copy")
        }
    }

    override func close() {
        isClosed = true
        previewTask?.cancel()
        previewTask = nil
        gifTimer?.invalidate()
        gifTimer = nil
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
            layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.13, alpha: 0.98).cgColor
        } else {
            layer?.backgroundColor = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.89, alpha: 0.99).cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }
}
