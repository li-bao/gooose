import AppKit
import Carbon
import Foundation

/// Registers global macOS hotkeys via Carbon `RegisterEventHotKey` (zero
/// polling and no Accessibility permission required).
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private static let signature: OSType = 0x474F4F53 // 'GOOS'
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionByID: [UInt32: HotkeyAction] = [:]
    private var handlerRef: EventHandlerRef?
    private(set) var registeredCount = 0

    private init() {}

    func start() {
        installHandlerIfNeeded()
        reregisterAll()
        GooseSettings.shared.onHotkeysChanged = { [weak self] in
            self?.reregisterAll()
        }
    }

    func stop() {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    func reregisterAll() {
        unregisterAll()
        guard GooseSettings.shared.hotkeysEnabled else { return }

        var nextID: UInt32 = 1
        for action in HotkeyAction.allCases {
            let binding = GooseSettings.shared.binding(for: action)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                actionByID[nextID] = action
                registeredCount += 1
            }
            nextID += 1
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
        registeredCount = 0
    }

    func trigger(_ action: HotkeyAction) {
        let controller = GooseController.shared
        switch action {
        case .pauseResume:
            controller.togglePause()
        case .hideAll:
            controller.hideAll()
        case .showAll:
            if controller.state == .hidden || controller.state == .paused {
                controller.resumeAll()
            }
        case .spawnGoose:
            controller.spawnGoose()
        case .emergencyStop:
            controller.emergencyStop()
        case .openControlCenter:
            Windows.controlCenter.show()
        }
    }

    fileprivate func handleCarbonEvent(_ event: EventRef?) {
        guard let event else { return }
        var hkID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hkID
        )
        guard status == noErr, hkID.signature == Self.signature,
              let action = actionByID[hkID.id] else {
            return
        }
        trigger(action)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installed: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                MainActor.assumeIsolated {
                    GlobalHotkeyManager.shared.handleCarbonEvent(event)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &installed
        )
        if status == noErr {
            handlerRef = installed
        }
    }
}
