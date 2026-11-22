import AppKit
import SwiftUI

/// Hosts a SwiftUI view in a regular titled window, re-used across opens.
@MainActor
final class SwiftUIWindowController {
    private var window: NSWindow?
    private let titleProvider: () -> String
    private let autosaveName: String
    private let size: NSSize
    private let makeView: () -> AnyView

    init<V: View>(autosaveName: String, size: NSSize, title: @escaping () -> String, @ViewBuilder content: @escaping () -> V) {
        self.autosaveName = autosaveName
        self.size = size
        self.titleProvider = title
        self.makeView = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.contentViewController = NSHostingController(rootView: makeView())
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.level = .normal
            w.collectionBehavior = [.moveToActiveSpace]
            w.setContentSize(size)
            w.center()
            w.setFrameAutosaveName(autosaveName)
            window = w
        }
        window?.title = titleProvider()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

@MainActor
enum Windows {
    static let settings = SwiftUIWindowController(
        autosaveName: "SuperGooseSettings", size: NSSize(width: 860, height: 600),
        title: { L("Settings") }
    ) { SettingsView() }

    static let controlCenter = SwiftUIWindowController(
        autosaveName: "SuperGooseControlCenter", size: NSSize(width: 600, height: 700),
        title: { L("Goose Control Center") }
    ) { ControlCenterView() }

    static let permissionCenter = SwiftUIWindowController(
        autosaveName: "SuperGoosePermissionCenter", size: NSSize(width: 680, height: 740),
        title: { L("Permission Center") }
    ) { PermissionCenterView() }
}
