import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures the main display via ScreenCaptureKit. Always verifies
/// `CGPreflightScreenCaptureAccess()` before calling ScreenCaptureKit,
/// distinguishes initialization/permission/restart/blank-frame errors, and
/// never returns a pure black screenshot as a successful capture.
@MainActor
final class ScreenCapturer {
    /// Target width for captured images. We let ScreenCaptureKit downscale via
    /// the GPU instead of doing a CPU-side `CGContext` redraw downstream.
    private static let captureWidth = 1024

    private var cachedDisplay: SCDisplay?

    func resetDisplayCache() {
        cachedDisplay = nil
    }

    /// Returns a snapshot of the main display already downscaled to ~1024px
    /// wide, or `nil` if capture failed.
    func captureMainDisplay() async throws -> CGImage? {
        switch await captureMainDisplayResult() {
        case .success(let image):
            return image
        case .failure:
            return nil
        }
    }

    func captureMainDisplayResult(bypassRestartGuard: Bool = false) async -> ScreenCaptureResult {
        guard CGPreflightScreenCaptureAccess() else {
            cachedDisplay = nil
            let failure = ScreenCaptureFailure.permissionNotGranted
            PermissionManager.shared.recordScreenCaptureOutcome(.failure(failure))
            return .failure(failure)
        }

        if !bypassRestartGuard,
           case .restartRequired(let reason) = PermissionManager.shared.screenRecordingState {
            return .failure(.restartRequired(reason))
        }

        let display: SCDisplay
        switch await resolveDisplay() {
        case .success(let d):
            display = d
        case .failure(let failure):
            PermissionManager.shared.recordScreenCaptureOutcome(.failure(failure))
            return .failure(failure)
        }

        let scale = CGFloat(Self.captureWidth) / CGFloat(display.width)
        let targetHeight = max(1, Int(CGFloat(display.height) * scale))

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Self.captureWidth
        config.height = targetHeight
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            if Self.isBlackOrBlankImage(image) {
                cachedDisplay = nil
                let failure = ScreenCaptureFailure.blackOrBlankImage
                PerceptionLog.warn("ScreenCapturer: captured image was pure black/blank; rejecting as invalid capture")
                PermissionManager.shared.recordScreenCaptureOutcome(.failure(failure))
                return .failure(failure)
            }
            let result = ScreenCaptureResult.success(image)
            PermissionManager.shared.recordScreenCaptureOutcome(result)
            return result
        } catch {
            cachedDisplay = nil
            let nsErr = error as NSError
            let failure: ScreenCaptureFailure
            if Self.isLikelyTCCDeclinedError(nsErr) && CGPreflightScreenCaptureAccess() {
                failure = .restartRequired("ScreenCaptureKit declined capture even though preflight is granted (\(nsErr.localizedDescription)). Quit and reopen Super Goose Desktop.")
            } else {
                failure = .captureFailed(nsErr.localizedDescription)
            }
            PerceptionLog.warn("ScreenCapturer: SCScreenshotManager.captureImage failed (\(nsErr.localizedDescription))")
            PermissionManager.shared.recordScreenCaptureOutcome(.failure(failure))
            return .failure(failure)
        }
    }

    private func resolveDisplay() async -> Result<SCDisplay, ScreenCaptureFailure> {
        if let cached = cachedDisplay {
            return .success(cached)
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            let nsErr = error as NSError
            PerceptionLog.warn("ScreenCapturer: SCShareableContent.current failed (\(nsErr.localizedDescription))")
            if Self.isLikelyTCCDeclinedError(nsErr) && CGPreflightScreenCaptureAccess() {
                return .failure(.restartRequired("ScreenCaptureKit cannot enumerate displays until Super Goose Desktop is restarted (\(nsErr.localizedDescription))."))
            }
            return .failure(.sckInitFailed(nsErr.localizedDescription))
        }

        guard let display = content.displays.first else {
            PerceptionLog.warn("ScreenCapturer: no displays returned by SCShareableContent")
            return .failure(.noDisplayAvailable)
        }

        cachedDisplay = display
        return .success(display)
    }

    private static func isLikelyTCCDeclinedError(_ error: NSError) -> Bool {
        if error.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && error.code == -3801 {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("declined") || desc.contains("tcc") || desc.contains("not authorized")
    }

    /// Downsamples `image` into a 16x16 RGBA8 buffer to verify it is not a
    /// solid black / empty frame returned during stale or restricted capture.
    static func isBlackOrBlankImage(_ image: CGImage) -> Bool {
        guard image.width > 0, image.height > 0 else { return true }
        let sampleSize = 16
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        for i in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[i] > 2 || pixels[i + 1] > 2 || pixels[i + 2] > 2 {
                return false
            }
        }
        return true
    }
}
