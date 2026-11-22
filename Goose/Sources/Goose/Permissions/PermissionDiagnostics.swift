import ApplicationServices
import CoreGraphics
import Foundation
import Security

enum PermissionDiagnostics {
    @MainActor
    static func collect(liveAX: AccessibilityValidationResult? = nil) -> PermissionDiagnosticsReport {
        let bundle = Bundle.main
        let bundleURL = bundle.bundleURL
        let bundlePath = bundleURL.path
        let executablePath = bundle.executableURL?.path ?? ProcessInfo.processInfo.arguments.first ?? "unknown"
        let bundleID = bundle.bundleIdentifier ?? "unbundled (none)"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        let isAppBundle = bundleURL.pathExtension == "app"
        let isInApps = bundlePath == "/Applications/Super Goose Desktop.app"
            || bundlePath.hasPrefix("/Applications/")
            || bundlePath.hasPrefix((NSHomeDirectory() as NSString).appendingPathComponent("Applications/"))
        let isTranslocated = bundlePath.contains("/AppTranslocation/")

        let infoDict = bundle.infoDictionary ?? [:]
        let usageDesc = (infoDict["NSScreenCaptureUsageDescription"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsageDesc = !(usageDesc?.isEmpty ?? true)

        let codeInfo = inspectCurrentCodeSignature()
        let duplicates = findDuplicateInstallations(currentBundlePath: bundlePath)

        let screenPreflight = CGPreflightScreenCaptureAccess()
        let axTrusted = AXIsProcessTrusted()
        let axLive = liveAX ?? AccessibilityProbe.validateLiveAccessibility()

        var warnings: [String] = []
        if !isAppBundle {
            warnings.append("Running outside a .app bundle (e.g. swift run / raw CLI binary). macOS TCC attributes permissions to the terminal host app rather than Super Goose Desktop.")
        }
        if isTranslocated {
            warnings.append("Running under macOS App Translocation. Move Super Goose Desktop.app directly into /Applications before granting permissions.")
        }
        if isAppBundle && !isInApps {
            warnings.append("Running from a non-Applications folder (\(bundlePath)). Copy the app to /Applications/Super Goose Desktop.app for stable TCC attribution.")
        }
        if !duplicates.isEmpty {
            warnings.append("Multiple Super Goose Desktop.app copies detected; macOS TCC may track the wrong copy.")
        }
        if isAppBundle && !hasUsageDesc {
            warnings.append("Info.plist is missing NSScreenCaptureUsageDescription.")
        }
        if codeInfo.isAdHoc {
            warnings.append("Ad-hoc signature detected (TeamIdentifier not set). Rebuilding changes the binary CDHash and can cause macOS TCC to treat a new build as a different app.")
        }

        let targetBundleID = bundle.bundleIdentifier ?? "com.pkrutaa.supergoosedesktop"
        let recoveryCommands = [
            "tccutil reset ScreenCapture \(targetBundleID)",
            "tccutil reset Accessibility \(targetBundleID)",
        ]

        return PermissionDiagnosticsReport(
            generatedAt: Date(),
            bundlePath: bundlePath,
            executablePath: executablePath,
            bundleIdentifier: bundleID,
            macOSVersion: osVersion,
            architecture: arch,
            signingIdentity: codeInfo.identity,
            teamIdentifier: codeInfo.teamIdentifier,
            designatedRequirement: codeInfo.designatedRequirement,
            cdHash: codeInfo.cdHash,
            isRunningFromAppBundle: isAppBundle,
            isInstalledInApplications: isInApps,
            isTranslocated: isTranslocated,
            duplicateAppPaths: duplicates,
            hasScreenCaptureUsageDescription: hasUsageDesc,
            screenRecordingPreflight: screenPreflight,
            accessibilityTrusted: axTrusted,
            accessibilityLiveResult: axLive,
            warnings: warnings,
            recoveryCommands: recoveryCommands
        )
    }

    private struct CodeSignatureDetails {
        let identity: String
        let teamIdentifier: String
        let designatedRequirement: String
        let cdHash: String
        let isAdHoc: Bool
    }

    private static func inspectCurrentCodeSignature() -> CodeSignatureDetails {
        var codeRef: SecCode?
        guard SecCodeCopySelf([], &codeRef) == errSecSuccess, let selfCode = codeRef else {
            return CodeSignatureDetails(
                identity: "Unavailable",
                teamIdentifier: "not set",
                designatedRequirement: "Unavailable",
                cdHash: "Unavailable",
                isAdHoc: true
            )
        }

        var staticCodeRef: SecStaticCode?
        SecCodeCopyStaticCode(selfCode, [], &staticCodeRef)

        var infoCF: CFDictionary?
        if let staticCode = staticCodeRef {
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF)
        }
        let info = (infoCF as? [String: Any]) ?? [:]

        let team = (info[kSecCodeInfoTeamIdentifier as String] as? String) ?? "not set"
        let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let hasCerts = !(certs?.isEmpty ?? true)
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let adhocFlag: UInt32 = 0x0002
        let isAdHoc = !hasCerts || ((flags & adhocFlag) != 0)

        var identity = isAdHoc ? "ad-hoc (no certificate)" : "Signed"
        if let firstCert = certs?.first {
            var summary: CFString?
            summary = SecCertificateCopySubjectSummary(firstCert)
            if let s = summary as String? {
                identity = s
            }
        }

        var cdHash = "not available"
        if let unique = info[kSecCodeInfoUnique as String] as? Data {
            cdHash = unique.map { String(format: "%02x", $0) }.joined()
        }

        var reqString = "Unavailable"
        var reqRef: SecRequirement?
        if let staticCode = staticCodeRef,
           SecCodeCopyDesignatedRequirement(staticCode, [], &reqRef) == errSecSuccess,
           let req = reqRef {
            var cfStr: CFString?
            if SecRequirementCopyString(req, [], &cfStr) == errSecSuccess, let s = cfStr as String? {
                reqString = s
            }
        }

        return CodeSignatureDetails(
            identity: identity,
            teamIdentifier: team,
            designatedRequirement: reqString,
            cdHash: cdHash,
            isAdHoc: isAdHoc
        )
    }

    private static func findDuplicateInstallations(currentBundlePath: String) -> [String] {
        let fm = FileManager.default
        let candidates = [
            "/Applications/Super Goose Desktop.app",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Super Goose Desktop.app"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Downloads/goose/dist/Super Goose Desktop.app"),
        ]
        var found: [String] = []
        for path in candidates where path != currentBundlePath && fm.fileExists(atPath: path) {
            found.append(path)
        }
        return found
    }
}
