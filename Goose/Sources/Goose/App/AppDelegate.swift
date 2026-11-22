import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var overlayWindow: OverlayWindow?
    private var statusItem: NSStatusItem?
    private var escMonitor: EscQuitMonitor?
    private var cancellables: Set<AnyCancellable> = []

    /// The menu bar menu (exposed for the runtime self-test).
    var statusMenu: NSMenu? { statusItem?.menu }

    private var controller: GooseController { GooseController.shared }
    private var settings: GooseSettings { GooseSettings.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.refreshLaunchAtLoginStatus()
        PermissionManager.shared.startMonitoring()
        setUpMainMenu()
        setUpStatusBarItem()
        setUpOverlayWindow()
        setUpEscMonitor()
        applyLaunchSettings()
        GlobalHotkeyManager.shared.start()

        Task { @MainActor [weak self] in
            await self?.overlayWindow?.gooseScene.perception.resumePendingOCRIfNeeded()
        }

        DisplayManager.shared.onScreensChanged = { [weak self] in
            self?.overlayWindow?.updateForScreens()
        }

        settings.$showMenuBarIcon
            .sink { [weak self] visible in self?.statusItem?.isVisible = visible }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Re-launching from Finder/Spotlight opens Settings, so the app stays
    /// reachable even with the menu bar icon hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Windows.settings.show()
        return true
    }

    private func applyLaunchSettings() {
        if !settings.startGooseOnLaunch { controller.removeAllGeese() }
        if settings.pauseOnLaunch { controller.pauseAll() }
        controller.refresh()
    }

    // MARK: - Menu bar item

    private func setUpStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🪿"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = settings.showMenuBarIcon
        statusItem = item
        rebuild(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        controller.refresh()
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        add(L("Open Control Center"), #selector(openControlCenter), symbol: "gauge.with.dots.needle.33percent")
        add(L("Permission Center…"), #selector(openPermissionCenter), symbol: "shield.lefthalf.filled")
        add(L("Open Settings…"), #selector(openSettings), key: ",", symbol: "gearshape")
        menu.addItem(.separator())
        add(controller.state == .running ? L("Pause") : L("Resume"), #selector(togglePause),
            symbol: controller.state == .running ? "pause.fill" : "play.fill")
        add(settings.muteGoose ? L("Unmute Audio") : L("Mute All Audio"), #selector(toggleMuteAudio),
            symbol: settings.muteGoose ? "speaker.slash.fill" : "speaker.wave.2.fill")
        add(L("Deliver Meme Now"), #selector(deliverMemeNow), symbol: "photo.on.rectangle")
        add(L("Deliver Notepad Now"), #selector(deliverNotepadNow), symbol: "note.text")
        add(settings.isEnabled(.mouseTheft) ? L("Disable Mouse Theft") : L("Enable Mouse Theft"), #selector(toggleMouseTheft), symbol: "cursorarrow.slash")
        add(settings.allPranksDisabled ? L("Enable All Pranks") : L("Disable All Pranks"), #selector(toggleAllPranks), symbol: "theatermasks")
        add(L("Clear Desktop Mess"), #selector(clearDesktopMess), symbol: "sparkles.rectangle.stack")
        add(controller.state == .hidden ? L("Show Goose") : L("Hide Goose"), #selector(toggleHide),
            symbol: controller.state == .hidden ? "eye" : "eye.slash")
        add(L("Spawn Goose"), #selector(spawnGoose), symbol: "plus.circle")
        add(L("Emergency Stop"), #selector(emergencyStop), symbol: "exclamationmark.octagon.fill")
        menu.addItem(.separator())
        add(L("Quit"), #selector(quit), key: "q", symbol: "power")
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(spawnGoose) {
            return controller.geese.count < settings.maxGooseCount
        }
        return true
    }

    // MARK: - Main menu (enables ⌘, and text-field editing shortcuts)

    private func setUpMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: L("Open Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        let ccItem = NSMenuItem(title: L("Open Control Center"), action: #selector(openControlCenter), keyEquivalent: "")
        ccItem.target = self
        appMenu.addItem(ccItem)
        let permItem = NSMenuItem(title: L("Permission Center…"), action: #selector(openPermissionCenter), keyEquivalent: "")
        permItem.target = self
        appMenu.addItem(permItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("Quit Super Goose Desktop"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: - Overlay & ESC

    private func setUpOverlayWindow() {
        let window = OverlayWindow()
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
        controller.overlay = window
    }

    private func setUpEscMonitor() {
        escMonitor = EscQuitMonitor(window: overlayWindow) { [weak self] in
            self?.quit()
        }
        escMonitor?.start()
    }

    // MARK: - Actions

    @objc func openControlCenter() { Windows.controlCenter.show() }
    @objc func openPermissionCenter() { Windows.permissionCenter.show() }
    @objc func openSettings() { Windows.settings.show() }
    @objc private func togglePause() { controller.togglePause() }
    @objc private func toggleMuteAudio() {
        settings.muteGoose.toggle()
        if settings.muteGoose { SoundEffectEngine.shared.stopAll() }
    }
    @objc private func deliverMemeNow() { controller.deliverMemeNow() }
    @objc private func deliverNotepadNow() { controller.deliverNotepadNow() }
    @objc private func toggleMouseTheft() { controller.toggleMouseTheft() }
    @objc private func toggleAllPranks() { controller.toggleAllPranks() }
    @objc private func clearDesktopMess() { controller.clearDesktopMess() }
    @objc private func toggleHide() { controller.toggleHidden() }
    @objc private func spawnGoose() { controller.spawnGoose() }
    @objc private func emergencyStop() { controller.emergencyStop() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
