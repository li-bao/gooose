import AppKit
import CoreGraphics
import Foundation

/// Tracks all connected displays, converts between scene-local, Cocoa global,
/// and Quartz (CG) coordinates, and notifies the overlay when displays are
/// attached, detached, or reconfigured so geese are never stranded off-screen.
@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    private(set) var unionFrame: CGRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
    /// Each physical screen's frame translated into scene-local coordinates (relative to `unionFrame.origin`).
    private(set) var screenFrames: [CGRect] = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    /// Each physical screen's `visibleFrame` (excluding Dock/menu bar) in scene-local coordinates.
    private(set) var visibleScreenFrames: [CGRect] = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    private var primaryScreenHeight: CGFloat = 900
    private var customTestScreens: [CGRect]?
    private var screenObserver: NSObjectProtocol?

    var onScreensChanged: (() -> Void)?

    private init() {
        refreshScreens()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreens()
                self?.onScreensChanged?()
            }
        }
    }

    func refreshScreens() {
        let globalFrames: [CGRect]
        let globalVisibleFrames: [CGRect]
        if let testScreens = customTestScreens, !testScreens.isEmpty {
            globalFrames = testScreens
            globalVisibleFrames = testScreens
            primaryScreenHeight = testScreens[0].maxY
        } else {
            let screens = NSScreen.screens
            guard !screens.isEmpty else {
                unionFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
                screenFrames = [unionFrame]
                visibleScreenFrames = [unionFrame]
                primaryScreenHeight = 900
                return
            }
            globalFrames = screens.map(\.frame)
            globalVisibleFrames = screens.map(\.visibleFrame)
            primaryScreenHeight = screens[0].frame.height
        }

        let union = globalFrames.dropFirst().reduce(globalFrames[0]) { $0.union($1) }
        unionFrame = union
        screenFrames = globalFrames.map { frame in
            CGRect(
                x: frame.minX - union.minX,
                y: frame.minY - union.minY,
                width: frame.width,
                height: frame.height
            )
        }
        visibleScreenFrames = globalVisibleFrames.map { frame in
            CGRect(
                x: frame.minX - union.minX,
                y: frame.minY - union.minY,
                width: frame.width,
                height: frame.height
            )
        }
    }

    func visibleFrame(forScreenIndex idx: Int, fallbackSize: CGSize) -> CGRect {
        if visibleScreenFrames.indices.contains(idx) {
            return visibleScreenFrames[idx]
        }
        if screenFrames.indices.contains(idx) {
            return screenFrames[idx]
        }
        return CGRect(origin: .zero, size: fallbackSize)
    }

    func setCustomScreensForTesting(_ globalFrames: [CGRect]?) {
        customTestScreens = globalFrames
        refreshScreens()
        onScreensChanged?()
    }

    func isPointVisible(_ scenePoint: CGPoint, margin: CGFloat = 0) -> Bool {
        screenFrames.contains { frame in
            frame.insetBy(dx: margin, dy: margin).contains(scenePoint)
        }
    }

    func screenIndex(for scenePoint: CGPoint) -> Int? {
        screenFrames.firstIndex { $0.contains(scenePoint) }
    }

    func clampToNearestVisibleDisplay(_ scenePoint: CGPoint, margin: CGFloat = 45) -> CGPoint {
        guard !screenFrames.isEmpty else { return scenePoint }
        if isPointVisible(scenePoint, margin: margin) { return scenePoint }

        var bestPoint = scenePoint
        var bestDist = CGFloat.greatestFiniteMagnitude
        for frame in screenFrames {
            let insetX = min(margin, frame.width * 0.25)
            let insetY = min(margin, frame.height * 0.25)
            let safe = frame.insetBy(dx: insetX, dy: insetY)
            let clamped = CGPoint(
                x: min(max(safe.minX, scenePoint.x), safe.maxX),
                y: min(max(safe.minY, scenePoint.y), safe.maxY)
            )
            let d = hypot(clamped.x - scenePoint.x, clamped.y - scenePoint.y)
            if d < bestDist {
                bestDist = d
                bestPoint = clamped
            }
        }
        return bestPoint
    }

    func randomVisiblePoint(margin: CGFloat = 80, preferredScreenIndex: Int? = nil) -> CGPoint {
        let frame: CGRect
        if let idx = preferredScreenIndex, screenFrames.indices.contains(idx) {
            frame = screenFrames[idx]
        } else {
            frame = screenFrames.randomElement() ?? CGRect(origin: .zero, size: unionFrame.size)
        }
        let mx = min(margin, frame.width * 0.3)
        let my = min(margin, frame.height * 0.3)
        return CGPoint(
            x: CGFloat.random(in: (frame.minX + mx)...max(frame.minX + mx + 1, frame.maxX - mx)),
            y: CGFloat.random(in: (frame.minY + my)...max(frame.minY + my + 1, frame.maxY - my))
        )
    }

    func globalToScene(_ cocoaPoint: CGPoint) -> CGPoint {
        CGPoint(x: cocoaPoint.x - unionFrame.minX, y: cocoaPoint.y - unionFrame.minY)
    }

    func sceneToGlobal(_ scenePoint: CGPoint) -> CGPoint {
        CGPoint(x: scenePoint.x + unionFrame.minX, y: scenePoint.y + unionFrame.minY)
    }

    /// Converts scene-local coordinates to Quartz (top-left origin on primary display)
    /// coordinates expected by `CGWarpMouseCursorPosition`.
    func sceneToCG(_ scenePoint: CGPoint) -> CGPoint {
        let global = sceneToGlobal(scenePoint)
        return CGPoint(x: global.x, y: primaryScreenHeight - global.y)
    }
}
