import AppKit
import Foundation

/// Real native `NSWindow` the goose drags onto the screen. Uses standard
/// macOS chrome (titled, closable, miniaturizable) so it looks and behaves
/// exactly like any other native window — because it is one.
@MainActor
final class FloatingWindow {
    let window: NSWindow

    init(title: String, contentView: NSView, size: CGSize) {
        let contentRect = NSRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        contentView.frame = contentRect
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
    }

    var size: CGSize { window.frame.size }

    func show() {
        window.orderFront(nil)
    }

    /// Positions the window so its center is at the given point in NSScreen
    /// coordinates (y-up, origin at bottom-left of the main display). Our
    /// SpriteKit scene covers the main screen at origin, so scene points map
    /// directly to NSScreen points.
    func setCenter(_ point: CGPoint) {
        let frameSize = window.frame.size
        let origin = NSPoint(
            x: point.x - frameSize.width / 2,
            y: point.y - frameSize.height / 2
        )
        window.setFrameOrigin(origin)
    }

    /// Fades the window out and closes it. Safe to call once; subsequent
    /// calls are no-ops because `close()` invalidates the window.
    func closeWithFade(duration: TimeInterval = 1.0) {
        let target = window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            target.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                target.close()
            }
        })
    }
}

extension FloatingWindow {
    enum NoteStyle: CaseIterable, Sendable {
        case classicYellow
        case mint
        case peach
        case paper
        case darkTerminal

        var background: NSColor {
            switch self {
            case .classicYellow: return NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.68, alpha: 1)
            case .mint:          return NSColor(calibratedRed: 0.80, green: 0.95, blue: 0.85, alpha: 1)
            case .peach:         return NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.78, alpha: 1)
            case .paper:         return NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1)
            case .darkTerminal:  return NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.16, alpha: 1)
            }
        }

        var foreground: NSColor {
            switch self {
            case .darkTerminal: return NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.65, alpha: 1)
            default:            return NSColor(calibratedWhite: 0.12, alpha: 1)
            }
        }
    }

    /// Builds a note window with monospaced text content and visual style.
    static func note(title: String, body: String, style: NoteStyle = NoteStyle.allCases.randomElement() ?? .classicYellow) -> FloatingWindow {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = style.background

        guard let textView = scrollView.documentView as? NSTextView else {
            return FloatingWindow(title: title, contentView: scrollView, size: CGSize(width: 360, height: 220))
        }

        textView.string = body
        textView.font = NSFont(name: "Menlo", size: 13) ?? NSFont.userFixedPitchFont(ofSize: 13)
        textView.textColor = style.foreground
        textView.backgroundColor = style.background
        textView.drawsBackground = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 14, height: 14)

        let fw = FloatingWindow(title: title, contentView: scrollView, size: CGSize(width: 360, height: 220))
        fw.window.backgroundColor = style.background
        return fw
    }

    /// Builds a photo window with an `NSImageView` sized to the image's
    /// aspect ratio (capped to a sensible max).
    static func photo(image: NSImage, title: String) -> FloatingWindow {
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter

        let maxDim: CGFloat = 480
        let minDim: CGFloat = 240
        let imageSize = image.size
        let aspect = imageSize.height > 0 ? imageSize.width / imageSize.height : 1
        let width: CGFloat
        let height: CGFloat
        if aspect >= 1 {
            width = min(maxDim, max(minDim, imageSize.width))
            height = width / aspect
        } else {
            height = min(maxDim, max(minDim, imageSize.height))
            width = height * aspect
        }

        return FloatingWindow(title: title, contentView: imageView, size: CGSize(width: width, height: height))
    }
}
