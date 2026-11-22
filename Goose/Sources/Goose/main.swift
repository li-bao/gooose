import AppKit

if let pathArgIndex = CommandLine.arguments.firstIndex(of: "--render-preview"),
   pathArgIndex + 1 < CommandLine.arguments.count {
    let outputPath = CommandLine.arguments[pathArgIndex + 1]
    let success = PreviewRenderer.renderToPNG(at: outputPath)
    exit(success ? 0 : 1)
}

if CommandLine.arguments.contains("--selftest-persist-write") { SelfTest.persistWrite() }
if CommandLine.arguments.contains("--selftest-persist-read") { SelfTest.persistRead() }
if CommandLine.arguments.contains("--selftest-persist-reset") { SelfTest.persistReset() }
if CommandLine.arguments.contains("--selftest-logic") {
    Task { @MainActor in await SelfTest.logic() }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--diagnose-permissions") {
    Task { @MainActor in
        let report = PermissionDiagnostics.collect(liveAX: AccessibilityProbe.validateLiveAccessibility())
        FileHandle.standardOutput.write(Data((report.formattedText() + "\n").utf8))
        exit(0)
    }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--selftest-permissions") {
    Task { @MainActor in await SelfTest.permissions() }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--selftest-multigoose") { SelfTest.startMultiGoose() }
if CommandLine.arguments.contains("--selftest-phase4") { SelfTest.startPhase4() }
if CommandLine.arguments.contains("--selftest-perf") { SelfTest.startPerf() }
if CommandLine.arguments.contains("--runtime-selftest") { SelfTest.startRuntime() }

if CommandLine.arguments.contains("--brain-dryrun") {
    // Goes through the settings gate: OpenAI is only used if the user opted in.
    let llm = GooseController.shared.llm
    let brain = GooseBrain(llm: llm)
    let snapshots: [ContextSnapshot] = [
        fakeSnapshot(app: "Xcode", time: 120, idle: 5, ocr: ["TODO: rewrite this", "var foo = 42", "let bar: Int"]),
        fakeSnapshot(app: "Slack", time: 30, idle: 1, ocr: ["are we still on for thursday", "@channel quick question"]),
        fakeSnapshot(app: "Safari", time: 900, idle: 4, ocr: ["how to focus", "stack overflow"]),
        fakeSnapshot(app: "Finder", time: 5, idle: 0, ocr: []),
    ]
    Task { @MainActor in
        var recent: [String] = []
        for i in 0..<20 {
            let snap = snapshots[i % snapshots.count]
            if let d = await brain.decide(snapshot: snap, recentActions: recent) {
                let line = "[\(i)] app=\(snap.frontmostAppName ?? "-") tone=\(Personality.tone(forTimeOnApp: snap.elapsedOnApp, idle: snap.idleSeconds)) → \(format(d))\n"
                FileHandle.standardOutput.write(Data(line.utf8))
                recent.append(d.action.rawValue)
                if recent.count > 4 { recent.removeFirst() }
            }
        }
        exit(0)
    }
    RunLoop.main.run()
}

if let queryIndex = CommandLine.arguments.firstIndex(of: "--browser-demo"),
   queryIndex + 1 < CommandLine.arguments.count {
    let query = CommandLine.arguments[queryIndex + 1]
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    guard let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") else {
        exit(1)
    }
    let appShared = NSApplication.shared
    appShared.setActivationPolicy(.accessory)
    Task { @MainActor in
        let win = RealBrowserWindow(url: url)
        await win.slideIn()
        try? await Task.sleep(for: .seconds(Tuning.browseDwellSeconds))
        await win.dismiss()
        exit(0)
    }
    appShared.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

@MainActor
private func fakeSnapshot(app: String, time: TimeInterval, idle: TimeInterval, ocr: [String]) -> ContextSnapshot {
    ContextSnapshot(
        timestamp: Date(),
        frontmostAppName: app,
        frontmostWindowTitle: nil,
        ocrText: ocr.joined(separator: " ").lowercased(),
        ocrTopK: ocr,
        elapsedOnApp: time,
        prevFrontmostAppName: nil,
        idleSeconds: idle,
        textHash: 0
    )
}

private func format(_ d: GooseDecision) -> String {
    switch d.action {
    case .note: return "note(\(d.noteTitle)) — \(d.noteBody.replacingOccurrences(of: "\n", with: " / "))"
    case .browse: return "browse(\(d.browseURL?.absoluteString ?? "?"))"
    default: return d.action.rawValue
    }
}
