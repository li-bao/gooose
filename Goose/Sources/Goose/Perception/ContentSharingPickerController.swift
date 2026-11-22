import Combine
import Foundation
@preconcurrency import ScreenCaptureKit

/// Official macOS `SCContentSharingPicker.shared` integration for Mode B
/// ("System Content Picker"). Only captures from the display or window
/// explicitly selected by the user, and releases the source when stopped.
@MainActor
final class ContentSharingPickerController: NSObject, ObservableObject, SCContentSharingPickerObserver {
    static let shared = ContentSharingPickerController()

    @Published private(set) var activeFilter: SCContentFilter?
    @Published private(set) var isSharingActive = false
    @Published private(set) var selectedSourceLabel = "None selected"
    @Published private(set) var lastPickerError: String?

    private var didRegisterObserver = false

    private override init() {
        super.init()
    }

    private func registerObserverIfNeeded() {
        guard !didRegisterObserver else { return }
        didRegisterObserver = true
        SCContentSharingPicker.shared.add(self)
    }

    func presentPicker() {
        registerObserverIfNeeded()
        lastPickerError = nil
        var config = SCContentSharingPickerConfiguration()
        config.allowsChangingSelectedContent = true
        config.allowedPickerModes = [.singleDisplay, .singleWindow]
        SCContentSharingPicker.shared.defaultConfiguration = config
        SCContentSharingPicker.shared.isActive = true
        SCContentSharingPicker.shared.present()
    }

    func stopSharing() {
        activeFilter = nil
        isSharingActive = false
        selectedSourceLabel = "Stopped"
        SCContentSharingPicker.shared.isActive = false
        PermissionManager.shared.refreshScreenObservationStatus()
    }

    // MARK: - SCContentSharingPickerObserver

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSharingActive = (self.activeFilter != nil)
            if self.activeFilter == nil {
                self.selectedSourceLabel = "Stopped"
            }
            PermissionManager.shared.refreshScreenObservationStatus()
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activeFilter = filter
            self.isSharingActive = true
            self.selectedSourceLabel = "User-approved source"
            self.lastPickerError = nil
            PermissionManager.shared.refreshScreenObservationStatus()
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastPickerError = error.localizedDescription
            self.isSharingActive = false
            self.activeFilter = nil
            PermissionManager.shared.refreshScreenObservationStatus()
        }
    }
}
