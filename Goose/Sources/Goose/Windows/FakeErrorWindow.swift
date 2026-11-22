import AppKit
import SwiftUI

/// Parody error / crash / notification window clearly badged as a virtual
/// Super Goose prank. Never mimics macOS security/authentication prompts and
/// never asks for passwords or system permissions.
@MainActor
final class FakeErrorWindow {
    enum Style: String, CaseIterable, Sendable {
        case warning
        case crash
        case systemNotification

        var title: String {
            switch self {
            case .warning:            return "Goose Warning (Parody)"
            case .crash:              return "Goose Kernel Panic (Parody)"
            case .systemNotification: return "Goose Center Notice (Parody)"
            }
        }

        var symbol: String {
            switch self {
            case .warning:            return "exclamationmark.triangle.fill"
            case .crash:              return "ladybug.fill"
            case .systemNotification: return "bell.badge.fill"
            }
        }

        var accent: Color {
            switch self {
            case .warning:            return .orange
            case .crash:              return .red
            case .systemNotification: return .blue
            }
        }

        static let sampleMessages: [Style: [String]] = [
            .warning: [
                "Warning: Goose detected unguarded cursor activity.",
                "Alert: Bread supply critically low (0 crumbs remaining).",
                "Notice: Your productivity has been audited and found sus.",
            ],
            .crash: [
                "Goose.brain encountered HONK_OVERFLOW at line 0.",
                "EXC_BAD_HONK: Too many tabs open, goose took over.",
                "Fatal whimsy exception: Honk buffer full (honk x99).",
            ],
            .systemNotification: [
                "Goose Reminder: Time to ignore your tasks and feed the goose.",
                "Super Goose Update: Honk levels increased by 200%.",
                "Focus Report: Goose is watching from the corner of your screen.",
            ],
        ]
    }

    static let prankBadgeText = "🪿 Super Goose Virtual Prank — Not a real macOS alert"

    let window: NSWindow
    let style: Style
    let message: String
    private var dismissTask: Task<Void, Never>?
    private var onClose: (() -> Void)?

    init(style: Style, customMessage: String? = nil, onClose: (() -> Void)? = nil) {
        self.style = style
        self.onClose = onClose

        let trimmed = customMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            self.message = trimmed
        } else {
            self.message = Style.sampleMessages[style]?.randomElement() ?? "Honk."
        }

        let size = style == .systemNotification
            ? NSSize(width: 360, height: 150)
            : NSSize(width: 400, height: 190)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = style.title
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        self.window = w

        let view = FakeErrorContentView(style: style, message: self.message) { [weak self] in
            self?.closeNow()
        }
        w.contentViewController = NSHostingController(rootView: view)
        w.setContentSize(size)
        Self.position(w, style: style)
    }

    func show(autoDismissAfter seconds: TimeInterval = 15) {
        window.orderFront(nil)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.closeNow()
        }
    }

    func closeNow() {
        dismissTask?.cancel()
        dismissTask = nil
        window.close()
        let cb = onClose
        onClose = nil
        cb?()
    }

    private static func position(_ window: NSWindow, style: Style) {
        guard let screen = NSScreen.main?.visibleFrame else {
            window.center()
            return
        }
        let sz = window.frame.size
        if style == .systemNotification {
            let origin = NSPoint(x: screen.maxX - sz.width - 24, y: screen.maxY - sz.height - 24)
            window.setFrameOrigin(origin)
        } else {
            let x = CGFloat.random(in: max(screen.minX + 40, screen.midX - 220)...max(screen.minX + 41, screen.maxX - sz.width - 40))
            let y = CGFloat.random(in: max(screen.minY + 40, screen.midY - 140)...max(screen.minY + 41, screen.maxY - sz.height - 40))
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

private struct FakeErrorContentView: View {
    let style: FakeErrorWindow.Style
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(FakeErrorWindow.prankBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: style.symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(style.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.title).font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button("Honk (Dismiss)") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(style.accent)
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }
}
