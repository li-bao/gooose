import AppKit
import ImageIO

struct DecodedGIFFrames: Sendable {
    let frames: [CGImage]
    let delays: [TimeInterval]
    let pixelSize: CGSize

    var isAnimated: Bool { frames.count > 1 }
}

enum MemeImageDecoder {
    static func decode(url: URL) -> DecodedGIFFrames? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [CGImage] = []
        var delays: [TimeInterval] = []
        frames.reserveCapacity(count)
        delays.reserveCapacity(count)

        for i in 0..<count {
            guard let cgImg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(cgImg)
            delays.append(frameDelay(source: source, index: i))
        }
        guard let first = frames.first else { return nil }
        return DecodedGIFFrames(
            frames: frames,
            delays: delays,
            pixelSize: CGSize(width: first.width, height: first.height)
        )
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        let defaultDelay: TimeInterval = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaultDelay
        }
        let raw = (gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gifDict[kCGImagePropertyGIFDelayTime] as? Double)
            ?? defaultDelay
        return raw < 0.02 ? defaultDelay : raw
    }
}

@MainActor
final class MemeWindowRegistry {
    static let shared = MemeWindowRegistry()
    private var active: [MemeWindow] = []

    var count: Int {
        active.removeAll { !$0.isVisible }
        return active.count
    }

    func register(_ window: MemeWindow, maxVisible: Int) {
        active.removeAll { !$0.isVisible }
        while active.count >= max(1, maxVisible) {
            let oldest = active.removeFirst()
            oldest.close()
        }
        active.append(window)
    }

    func unregister(_ window: MemeWindow) {
        active.removeAll { $0 === window }
    }

    func closeAll() {
        let copy = active
        active.removeAll()
        for w in copy { w.close() }
    }
}

/// Borderless interactive macOS window rendering static images (PNG/JPG/JPEG)
/// and animated GIFs while preserving aspect ratio.
@MainActor
final class MemeWindow: NSWindow {
    let memeItem: MemeItem
    let targetSize: CGSize

    private let imageView = NSImageView()
    private let decoded: DecodedGIFFrames
    private var frameIndex = 0
    private var animTimer: Timer?
    private var lifetimeTimer: Timer?

    init?(item: MemeItem, maxDimension: CGFloat = 340) {
        guard let decoded = MemeImageDecoder.decode(url: item.url) else { return nil }
        self.memeItem = item
        self.decoded = decoded

        let w = max(1, decoded.pixelSize.width)
        let h = max(1, decoded.pixelSize.height)
        let scale = min(1.0, maxDimension / max(w, h))
        let contentW = max(160, (w * scale).rounded())
        let contentH = max(130, (h * scale).rounded() + 26)
        self.targetSize = CGSize(width: contentW, height: contentH)

        super.init(
            contentRect: NSRect(origin: CGPoint(x: -2000, y: -2000), size: targetSize),
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

        buildUI(size: targetSize)
        showFrame(0)
        startGIFAnimationIfNeeded()
    }

    private func buildUI(size: CGSize) {
        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let headerHeight: CGFloat = 26
        let header = NSView(frame: NSRect(x: 0, y: size.height - headerHeight, width: size.width, height: headerHeight))

        let titleLabel = NSTextField(labelWithString: memeItem.filename)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.frame = NSRect(x: 10, y: 4, width: size.width - 42, height: 18)
        header.addSubview(titleLabel)

        let closeBtn = NSButton(frame: NSRect(x: size.width - 26, y: 3, width: 20, height: 20))
        closeBtn.bezelStyle = .circular
        closeBtn.title = "×"
        closeBtn.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        header.addSubview(closeBtn)

        imageView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - headerHeight)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]

        container.addSubview(imageView)
        container.addSubview(header)
        contentView = container
    }

    private func showFrame(_ index: Int) {
        guard index < decoded.frames.count else { return }
        let cg = decoded.frames[index]
        imageView.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func startGIFAnimationIfNeeded() {
        guard decoded.isAnimated else { return }
        scheduleNextFrame()
    }

    private func scheduleNextFrame() {
        let delay = decoded.delays[frameIndex % decoded.delays.count]
        animTimer?.invalidate()
        animTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible else { return }
                self.frameIndex = (self.frameIndex + 1) % self.decoded.frames.count
                self.showFrame(self.frameIndex)
                self.scheduleNextFrame()
            }
        }
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

    @objc private func closeClicked() {
        close()
    }

    override func close() {
        animTimer?.invalidate()
        animTimer = nil
        lifetimeTimer?.invalidate()
        lifetimeTimer = nil
        MemeWindowRegistry.shared.unregister(self)
        super.close()
    }
}
