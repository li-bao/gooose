import Foundation
import XCTest

final class GooseTests: XCTestCase {
    private var gooseBinaryURL: URL {
        let testBundleURL = Bundle(for: GooseTests.self).bundleURL
        let productsDir = testBundleURL.deletingLastPathComponent()
        let direct = productsDir.appendingPathComponent("Goose")
        if FileManager.default.isExecutableFile(atPath: direct.path) {
            return direct
        }
        return productsDir.appendingPathComponent("Goose-tool")
    }

    private func runGoose(args: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let binary = gooseBinaryURL
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), "Goose executable not found at \(binary.path)")

        let process = Process()
        process.executableURL = binary
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    func testCoreLogicSelfTest() throws {
        let result = try runGoose(args: ["--selftest-logic"])
        XCTAssertEqual(result.status, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("ALL PASSED"))
    }

    func testPermissionsSelfTest() throws {
        let result = try runGoose(args: ["--selftest-permissions"])
        XCTAssertEqual(result.status, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("ALL PASSED"))
    }

    func testUltimateFeaturesSelfTest() throws {
        let result = try runGoose(args: ["--selftest-ultimate"])
        XCTAssertEqual(result.status, 0, "stderr: \(result.stderr)\nstdout: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("ALL PASSED"))
    }

    func testDiagnosePermissionsOutputsReport() throws {
        let result = try runGoose(args: ["--diagnose-permissions"])
        XCTAssertEqual(result.status, 0, "stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Bundle Identifier:"))
        XCTAssertTrue(result.stdout.contains("tccutil reset ScreenCapture"))
    }

    func testBrainDryRun() throws {
        let result = try runGoose(args: ["--brain-dryrun"])
        XCTAssertEqual(result.status, 0, "stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("[0]"))
        XCTAssertTrue(result.stdout.contains("[19]"))
    }
}
