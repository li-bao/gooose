import AppKit
import CoreGraphics
import Foundation
import SpriteKit

/// Developer-only verification harness (like `--brain-dryrun`). Never runs
/// unless one of its flags is passed.
///
///   --selftest-persist-write / -read / -reset   restart-persistence test (3 processes)
///   --selftest-logic                            settings / gating logic (headless, isolated defaults)
///   --runtime-selftest                          drives the live app: menu, pause, e-stop, spawn, mouse theft
///                                               (briefly moves the real cursor!)
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    }

    private static func finish() -> Never {
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: Persistence across restarts (separate processes)

    static func persistWrite() -> Never {
        let s = GooseSettings.shared
        s.gooseSize = 1.7
        s.language = .traditionalChinese
        s.setEnabled(.footprints, false)
        s.setEnabled(.mouseTheft, false)
        s.applyChaosLevel(.extreme)
        s.behaviorCooldown = 33
        s.masterVolume = 0.25
        s.aiModel = "gpt-4o-mini"
        s.externalAIOptIn = true
        s.naughty = 0.9
        s.allPranksDisabled = true
        s.maxGooseCount = 4
        print("wrote settings")
        exit(0)
    }

    static func persistRead() -> Never {
        let s = GooseSettings.shared
        check("persist gooseSize", s.gooseSize == 1.7, "\(s.gooseSize)")
        check("persist language", s.language == .traditionalChinese)
        check("persist footprints off", !s.isEnabled(.footprints))
        check("persist mouseTheft off", !s.isEnabled(.mouseTheft))
        check("persist chaos extreme", s.chaosLevel == .extreme)
        check("persist cooldown", s.behaviorCooldown == 33, "\(s.behaviorCooldown)")
        check("persist volume", s.masterVolume == 0.25)
        check("persist aiModel", s.aiModel == "gpt-4o-mini")
        check("persist externalAI opt-in", s.externalAIOptIn)
        check("persist naughty", s.naughty == 0.9)
        check("persist allPranksDisabled", s.allPranksDisabled)
        check("persist maxGooseCount", s.maxGooseCount == 4)
        check("untouched default kept (honking on)", s.isEnabled(.honking))
        finish()
    }

    static func persistReset() -> Never {
        GooseSettings.shared.restoreDefaults()
        let s = GooseSettings.shared
        check("restoreDefaults gooseSize", s.gooseSize == 1)
        check("restoreDefaults behaviors", GooseBehavior.allCases.allSatisfy { s.isEnabled($0) })
        check("restoreDefaults external AI off", !s.externalAIOptIn)
        check("restoreDefaults chaos normal", s.chaosLevel == .normal && !s.isChaosCustomized)
        finish()
    }

    // MARK: Headless logic

    static func logic() async -> Never {
        let suite = "supergoose.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let s = GooseSettings(defaults: defaults)
        check("default: external AI is opt-in (off)", !s.externalAIOptIn)
        check("default: normal chaos matches original (theft 100%)", s.mouseTheftProbability == 1.0 && s.chaosLevel == .normal)
        check("default: all implemented behaviors on", GooseBehavior.allCases.allSatisfy { s.isEnabled($0) })

        // Every behavior switch is reflected immediately and stored.
        for b in GooseBehavior.allCases {
            s.setEnabled(b, false)
            check("toggle \(b.rawValue) off", !s.isEnabled(b) && !s.allows(b))
            let reloaded = GooseSettings(defaults: defaults)
            check("toggle \(b.rawValue) persisted", !reloaded.isEnabled(b))
            s.setEnabled(b, true)
            check("toggle \(b.rawValue) on", s.allows(b))
        }

        s.allPranksDisabled = true
        check("master prank switch blocks prank behaviors", GooseBehavior.allCases.filter(\.isPrank).allSatisfy { !s.allows($0) })
        check("master prank switch leaves footprints/honk/sleep", s.allows(.footprints) && s.allows(.honking) && s.allows(.sleepMode))
        s.allPranksDisabled = false

        s.setEnabled(.mouseChase, false)
        check("theft requires chase", !s.effectiveMouseTheft)
        s.setEnabled(.mouseChase, true)

        for level in ChaosLevel.allCases {
            s.applyChaosLevel(level)
            check("chaos \(level.rawValue) applies preset", !s.isChaosCustomized)
        }
        s.prankFrequency = 2.7
        check("slider change marks customized", s.isChaosCustomized)

        // Migration marker
        check("schema version stored", defaults.integer(forKey: "settings.schemaVersion") == GooseSettings.schemaVersion)

        // Brain respects behavior switches (uses the shared settings).
        let shared = GooseSettings.shared
        shared.aiEnabled = false   // keep brain sampling deterministic and local
        let brain = GooseBrain(llm: GooseController.shared.llm)
        let snap = ContextSnapshot.empty()
        func sample(_ n: Int) async -> Set<String> {
            var seen = Set<String>()
            for _ in 0..<n { if let d = await brain.decide(snapshot: snap, recentActions: []) { seen.insert(d.action.rawValue) } }
            return seen
        }
        let base = await sample(300)
        check("brain default produces notes+sleep+photo", base.contains("note") && base.contains("nap") && base.contains("photo"), "\(base.sorted())")
        shared.setEnabled(.stickyNotes, false)
        check("stickyNotes off → no notes", !(await sample(300)).contains("note"))
        shared.setEnabled(.stickyNotes, true)
        shared.setEnabled(.windowPranks, false)
        let noWin = await sample(300)
        check("windowPranks off → no photo/browse", !noWin.contains("photo") && !noWin.contains("browse"))
        shared.setEnabled(.windowPranks, true)
        shared.setEnabled(.sleepMode, false)
        let noSleep = await sample(300)
        check("sleepMode off → no nap/deepSleep", !noSleep.contains("nap") && !noSleep.contains("deepSleep"))
        shared.setEnabled(.sleepMode, true)
        shared.allowWebBrowsing = false
        check("allowWebBrowsing off → no browse", !(await sample(300)).contains("browse"))
        shared.allowWebBrowsing = true

        // Footprints gate & directional angle + bounded capacity
        GameTime.tick()
        try? await Task.sleep(for: .milliseconds(20))
        GameTime.tick()
        let sim = GooseSimulation()
        sim.direction = 90
        sim.addFootMark(at: CGPoint(x: 1, y: 1))
        check("footprints on → mark added", sim.footMarks.contains { $0.time > 0 })
        check("footprint stores directional angle", sim.footMarks.contains { $0.time > 0 && abs($0.angle - (.pi / 2)) < 0.01 })
        shared.footprintMaxCount = 24
        for i in 0..<40 { sim.addFootMark(at: CGPoint(x: CGFloat(i), y: 2)) }
        check("footprint ring buffer bounded to maxCount", sim.footMarks.count == 24)
        shared.footprintMaxCount = 64
        let sim2 = GooseSimulation()
        shared.setEnabled(.footprints, false)
        sim2.addFootMark(at: CGPoint(x: 1, y: 1))
        check("footprints off → no mark", !sim2.footMarks.contains { $0.time > 0 })
        shared.setEnabled(.footprints, true)

        // Phase 2: Personality evolution & real behavior gating
        let pers = GoosePersonality(isLead: false)
        let evasiveness0 = pers.evasiveness
        pers.recordCaught()
        check("personality: caught increases evasiveness", pers.evasiveness > evasiveness0)
        let approach0 = pers.approachability
        pers.recordPat()
        check("personality: pat increases approachability", pers.approachability > approach0)
        let prankMult0 = pers.prankMultiplier
        pers.tick(dt: 30, isSleeping: false, isActiveTask: false)
        check("personality: idle time increases boredom & prank desire", pers.boredom > 0 && pers.prankMultiplier > prankMult0)
        let fatigueBefore = pers.fatigue
        pers.tick(dt: 10, isSleeping: true, isActiveTask: false)
        check("personality: sleep recovers fatigue", pers.fatigue < fatigueBefore)

        // Phase 2: BehaviorScheduler priority, sleep protection, cooldowns
        let sched = BehaviorScheduler.shared
        sched.resetCooldowns()
        let schedSim = GooseSimulation()
        sched.request(priority: .ambient, task: NapTask(), behavior: .sleepMode, timeout: 10, on: schedSim)
        check("scheduler: sleeping blocks proactive prank", !sched.request(priority: .prank, task: DesktopMessTask(), behavior: .desktopMess, on: schedSim))
        check("scheduler: reactive wakes/preempts sleep", sched.request(priority: .reactive, task: WanderTask(), on: schedSim))
        sched.emergencyStop(on: [schedSim])
        check("scheduler: emergencyStop restores wander", schedSim.currentTask is WanderTask)

        // Phase 2: DesktopMessOverlay bounded count & zero filesystem side effects
        let messOverlay = DesktopMessOverlay()
        for _ in 0..<30 {
            messOverlay.spawnMessBurst(near: CGPoint(x: 300, y: 300), count: 1, within: CGSize(width: 1200, height: 800))
        }
        check("desktopMess overlay capped <= maxItems", messOverlay.itemCount == DesktopMessOverlay.maxItems)
        messOverlay.clearAll()
        check("desktopMess clearAll empties overlay", messOverlay.itemCount == 0)

        // Phase 2: AI taunt/fake-error fallback with external AI off
        let taunt = await GooseController.shared.llm.generateTaunt(personality: pers, event: "test")
        let fakeErr = await GooseController.shared.llm.generateFakeErrorMessage(personality: pers, style: .warning)
        check("LLM local taunt fallback non-empty", !taunt.isEmpty)
        check("LLM local fakeError fallback non-empty", !fakeErr.isEmpty)

        // Speed multipliers
        let sim3 = GooseSimulation()
        sim3.setSpeed(.run)
        let normalSpeed = sim3.currentSpeed
        sim3.speedMultiplier = 2
        check("movement speed multiplier", abs(sim3.currentSpeed - normalSpeed * 2) < 0.001)
        sim3.animationMultiplier = 2
        check("animation speed multiplier", abs(sim3.stepTime - 0.1) < 0.001)

        // AI gating
        let llm = GooseController.shared.llm
        shared.externalAIOptIn = false
        check("external AI off → OpenAI never active", !llm.activeProviders().contains { $0 === llm.openAI })
        shared.aiEnabled = false
        check("AI disabled → no providers", llm.activeProviders().isEmpty)
        let note = await llm.generateNote(systemPrompt: "x", snapshot: snap)
        check("AI disabled → no note generated", note == nil)
        shared.aiEnabled = true
        check("OpenAI request counter untouched", ExternalAIActivity.shared.requestCount == 0)
        shared.restoreDefaults()

        // L10n
        shared.language = .traditionalChinese
        check("zh-Hant translation", L("Pause All") == "全部暫停")
        shared.language = .english
        check("english passthrough", L("Pause All") == "Pause All")
        shared.restoreDefaults()
        finish()
    }

    // MARK: Phase 3 Multi-Goose Acceptance Tests

    static func startMultiGoose() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            await multiGooseAcceptance()
        }
    }

    private static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / (1024.0 * 1024.0) : -1
    }

    private static func multiGooseAcceptance() async -> Never {
        let c = GooseController.shared
        let s = GooseSettings.shared
        let coord = GlobalActionCoordinator.shared
        guard let scene = c.scene else {
            check("multigoose: scene available", false)
            finish()
        }

        s.restoreDefaults()
        s.language = .english
        s.behaviorCooldown = 0
        s.randomBehavior = false
        BehaviorScheduler.shared.resetCooldowns()
        coord.emergencyStopAll()
        coord.resetMetrics()

        // 1. Spawn 5 geese simultaneously + verify unique IDs & hard cap
        s.maxGooseCount = 5
        while scene.gooseCount < 5 {
            _ = scene.spawnGoose()
        }
        let uniqueIDs = Set(scene.manager.geese.map(\.id))
        check("1) spawned 5 geese with unique UUIDs", scene.gooseCount == 5 && uniqueIDs.count == 5)
        s.maxGooseCount = 9 // even if setting forced higher, hard cap stays 5
        check("1b) hard cap prevents 6th goose", scene.manager.spawnGoose(in: scene, screenSize: scene.size) == nil && scene.gooseCount == 5)
        s.maxGooseCount = 5

        // 2 & 3. All 5 geese simultaneously request Mouse Theft → strictly 1 Mouse Lock holder
        BehaviorScheduler.shared.resetCooldowns()
        var mouseGrants = 0
        for g in scene.manager.geese {
            let task = NabMouseTask(gooseID: g.id, priority: .normalPrank, effects: scene, personality: g.personality)
            if BehaviorScheduler.shared.request(priority: .prank, task: task, behavior: .mouseTheft, timeout: 10, on: g.simulation) {
                mouseGrants += 1
            }
        }
        await wait(0.15)
        check("2) 5 geese request Mouse Theft → only 1 granted", mouseGrants == 1 && coord.activeMouseHolderCount == 1, "grants=\(mouseGrants)")
        let activeMouseTasks = scene.manager.geese.filter { $0.simulation.currentTask is NabMouseTask }.count
        check("3) active Mouse Lock has single holder ID", coord.mouseHolderID != nil && activeMouseTasks == 1 && coord.maxObservedConcurrentMouseHolders == 1)

        // 6. Remove the goose currently holding Mouse Lock mid-theft
        let stolenHolderID = coord.mouseHolderID
        check("6a) mouse holder exists before removal", stolenHolderID != nil)
        if let holderID = stolenHolderID {
            check("6b) remove mouse lock holder", scene.removeGoose(id: holderID))
        }
        check("6c) lock released immediately on goose removal", coord.mouseHolderID == nil && coord.activeMouseHolderCount == 0)
        if let survivor = scene.manager.geese.first {
            BehaviorScheduler.shared.resetCooldowns()
            let reacquired = BehaviorScheduler.shared.request(
                priority: .prank,
                task: NabMouseTask(gooseID: survivor.id, priority: .normalPrank, effects: scene, personality: survivor.personality),
                behavior: .mouseTheft,
                timeout: 8,
                on: survivor.simulation
            )
            check("6d) surviving goose can reacquire Mouse Lock cleanly", reacquired && coord.mouseHolderID == survivor.id)
        }

        // Bring population back to 5 and clear locks before Window Dragging contention test
        while scene.gooseCount < 5 { _ = scene.spawnGoose() }
        c.emergencyStop()
        c.resumeAll()
        BehaviorScheduler.shared.resetCooldowns()

        // 4 & 5. All 5 geese simultaneously request Window Dragging → strictly 1 Window Lock holder
        var windowGrants = 0
        for g in scene.manager.geese {
            let task = DragWindowTask(gooseID: g.id, effects: scene) {
                FloatingWindow.note(title: "test.txt", body: "honk")
            }
            if BehaviorScheduler.shared.request(priority: .prank, task: task, behavior: .windowPranks, timeout: 10, on: g.simulation) {
                windowGrants += 1
            }
        }
        await wait(0.15)
        check("4) 5 geese request Window Dragging → only 1 granted", windowGrants == 1 && coord.activeWindowHolderCount == 1, "grants=\(windowGrants)")
        check("5) active Window Lock has single holder ID", coord.windowHolderID != nil && coord.maxObservedConcurrentWindowHolders == 1)

        // 7. Trigger Emergency Stop while Window Lock is held
        check("7a) Window Lock held before E-stop", coord.activeWindowHolderCount == 1)
        c.emergencyStop()
        await wait(0.15)
        check("7b) Emergency Stop releases Window & Mouse locks immediately", coord.activeWindowHolderCount == 0 && coord.activeMouseHolderCount == 0 && coord.windowHolderID == nil && coord.mouseHolderID == nil)
        c.resumeAll()

        // 8. Continuous spawn & remove cycles (20 cycles)
        for cycle in 0..<20 {
            s.maxGooseCount = 5
            while scene.gooseCount < 5 { _ = scene.spawnGoose() }
            if cycle % 2 == 0 {
                scene.removeAllGeese()
            } else {
                while scene.gooseCount > 1 { _ = scene.removeGoose() }
            }
        }
        while scene.gooseCount < 4 { _ = scene.spawnGoose() }
        check("8) 20 spawn/remove cycles leave 0 leaked locks", coord.activeMouseHolderCount == 0 && coord.activeWindowHolderCount == 0 && scene.gooseCount == 4)

        // 9. Concurrent non-conflicting decorative pranks + social interactions + sleeping goose
        BehaviorScheduler.shared.resetCooldowns()
        let g0 = scene.manager.geese[0]
        let g1 = scene.manager.geese[1]
        let g2 = scene.manager.geese[2]
        let g3 = scene.manager.geese[3]
        _ = BehaviorScheduler.shared.request(priority: .ambient, task: NapTask(effects: scene, personality: g0.personality), behavior: .sleepMode, timeout: 10, on: g0.simulation)
        _ = BehaviorScheduler.shared.request(priority: .prank, task: DesktopMessTask(effects: scene), behavior: .desktopMess, timeout: 10, on: g1.simulation)
        g2.simulation.setTask(GooseInteractionTask(kind: .chasePeer, partner: g3, effects: scene, duration: 5))
        g3.simulation.setTask(GooseInteractionTask(kind: .avoidPeer, partner: g2, effects: scene, duration: 5))
        await wait(0.2)
        check("9) sleeping + decorative prank + peer interaction coexist without lock contention",
              (g0.simulation.currentTask is NapTask) &&
              (g1.simulation.currentTask is DesktopMessTask) &&
              (g2.simulation.currentTask is GooseInteractionTask) &&
              (g3.simulation.currentTask is GooseInteractionTask) &&
              coord.activeMouseHolderCount == 0 &&
              coord.activeWindowHolderCount == 0)

        // 10. Sustained 5-goose run (300 ticks) + shared perception coalescing + RSS check
        s.maxGooseCount = 5
        _ = scene.spawnGoose()
        s.randomBehavior = true
        for _ in 0..<300 {
            scene.manager.tickAll(dt: 1.0 / 60.0, currentTime: Double(GameTime.time), scene: scene)
        }
        let capturesBefore = scene.perception.captureCount
        let coalescedBefore = scene.perception.coalescedHitCount
        s.screenRecognition = false // fast shared snapshot test without screen popup
        let t0 = Task { @MainActor in await scene.perception.captureSnapshot() }
        let t1 = Task { @MainActor in await scene.perception.captureSnapshot() }
        let t2 = Task { @MainActor in await scene.perception.captureSnapshot() }
        let t3 = Task { @MainActor in await scene.perception.captureSnapshot() }
        let t4 = Task { @MainActor in await scene.perception.captureSnapshot() }
        _ = await (t0.value, t1.value, t2.value, t3.value, t4.value)
        let newCaptures = scene.perception.captureCount - capturesBefore
        let newCoalesced = scene.perception.coalescedHitCount - coalescedBefore
        check("10a) shared perception coalesced concurrent requests", newCaptures <= 1 && newCoalesced >= 4, "captures=\(newCaptures), coalesced=\(newCoalesced)")
        check("10b) global lock invariant preserved throughout run", coord.maxObservedConcurrentMouseHolders <= 1 && coord.maxObservedConcurrentWindowHolders <= 1)

        let rssMB = residentMemoryMB()
        check("10c) sustained 5-goose RSS memory healthy (< 300 MB)", rssMB > 0 && rssMB < 300, String(format: "%.1f MB", rssMB))

        c.emergencyStop()
        scene.clearDesktopMess()
        s.restoreDefaults()
        finish()
    }

    // MARK: Phase 4 Integration, Security & Performance

    static func startPhase4() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            await phase4()
        }
    }

    static func startPerf() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            await perfBenchmark()
        }
    }

    private static func phase4() async -> Never {
        let c = GooseController.shared
        let s = GooseSettings.shared
        let dm = DisplayManager.shared
        guard let scene = c.scene else {
            check("phase4: scene available", false)
            finish()
        }
        s.restoreDefaults()
        s.language = .english

        // 1. Multi-display support & unplugged external monitor recovery
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        dm.setCustomScreensForTesting([primary, secondary])
        scene.handleScreenParametersChanged()
        check("multidisplay union includes 2 screens", dm.screenFrames.count == 2 && dm.unionFrame.width == 4480)
        s.maxGooseCount = 3
        while scene.gooseCount < 3 { _ = scene.spawnGoose() }
        // Place Goose 2 on secondary display
        let g2 = scene.manager.geese[1]
        g2.simulation.position = CGPoint(x: 3100, y: 700)
        g2.simulation.targetPos = CGPoint(x: 3200, y: 700)
        check("goose on secondary display is visible", dm.isPointVisible(g2.simulation.position))
        // Simulate unplugging secondary display
        dm.setCustomScreensForTesting([primary])
        scene.handleScreenParametersChanged()
        check("unplugging secondary display relocates off-screen goose safely", dm.isPointVisible(g2.simulation.position) && g2.simulation.position.x <= primary.maxX)
        dm.setCustomScreensForTesting(nil)
        scene.handleScreenParametersChanged()

        // 2. Fullscreen awareness & exception apps
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        s.fullscreenAwareness = true
        s.fullscreenExceptionApps = ""
        let gameMode = FullscreenMonitor.shared.evaluate(appName: "Steam", bundleID: "com.valvesoftware.steam", windowFrame: screenRect)
        check("fullscreen game detected", gameMode == .fullscreenGame)
        FullscreenMonitor.shared.setModeForTesting(.fullscreenGame)
        BehaviorScheduler.shared.resetCooldowns()
        s.behaviorCooldown = 0
        check("fullscreenGame blocks mouseTheft", !BehaviorScheduler.shared.allowsTaskStart(priority: .prank, behavior: .mouseTheft, on: scene.simulation))
        check("fullscreenGame blocks windowPranks", !BehaviorScheduler.shared.allowsTaskStart(priority: .prank, behavior: .windowPranks, on: scene.simulation))
        FullscreenMonitor.shared.setModeForTesting(nil)

        let mediaMode = FullscreenMonitor.shared.evaluate(appName: "Keynote", bundleID: "com.apple.iWork.Keynote", windowFrame: screenRect)
        check("fullscreen presentation detected as mediaOrPresentation", mediaMode == .mediaOrPresentation)
        s.fullscreenExceptionApps = "Keynote, Steam"
        let exemptMode = FullscreenMonitor.shared.evaluate(appName: "Keynote", bundleID: "com.apple.iWork.Keynote", windowFrame: screenRect)
        check("exception app bypasses fullscreen suppression", exemptMode == .normal)
        s.fullscreenExceptionApps = ""

        // 3. Global Hotkeys registration & action dispatch
        let hk = GlobalHotkeyManager.shared
        check("global hotkeys registered all 6 actions", hk.registeredCount == HotkeyAction.allCases.count, "count=\(hk.registeredCount)")
        hk.trigger(.pauseResume)
        check("hotkey pauseResume pauses & freezes rendering", c.state == .paused && c.overlay?.isRenderingPaused == true)
        hk.trigger(.pauseResume)
        check("hotkey pauseResume resumes & unfreezes rendering", c.state == .running && c.overlay?.isRenderingPaused == false)
        hk.trigger(.hideAll)
        check("hotkey hideAll hides overlay", c.state == .hidden && c.overlay?.isRenderingPaused == true)
        hk.trigger(.showAll)
        check("hotkey showAll restores overlay", c.state == .running && c.overlay?.isRenderingPaused == false)
        hk.trigger(.emergencyStop)
        check("hotkey emergencyStop halts pranks", c.state == .stopped)
        c.resumeAll()

        // 4. Notifications gating
        let nm = NotificationManager.shared
        s.notificationsEnabled = false
        check("notifications off blocks all categories", !nm.isCategoryAllowed(.prank) && !nm.isCategoryAllowed(.newGoose))
        s.notificationsEnabled = true
        s.notifyPrank = false
        check("individual notification switch respected", !nm.isCategoryAllowed(.prank) && nm.isCategoryAllowed(.newGoose))
        let countBefore = nm.deliveredCount
        nm.post(category: .newGoose, title: "Test", body: "Honk")
        check("notification delivery increments cleanly without crash", nm.deliveredCount == countBefore + 1)
        s.notificationsEnabled = false

        // 5. Security hardening checks (Spotify URI + WKWebView URL + no external network leak)
        check("SpotifyController accepts valid track URI", SpotifyController.isValidSpotifyURI("spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
        check("SpotifyController rejects AppleScript injection", !SpotifyController.isValidSpotifyURI("spotify:track:abc\" & do shell script \"id"))
        check("RealBrowserWindow allows valid https URL", RealBrowserWindow.isAllowedURL(URL(string: "https://en.wikipedia.org/wiki/Goose")!))
        check("RealBrowserWindow rejects file:// URL", !RealBrowserWindow.isAllowedURL(URL(string: "file:///etc/passwd")!))
        check("RealBrowserWindow rejects http:// URL", !RealBrowserWindow.isAllowedURL(URL(string: "http://example.com")!))
        check("RealBrowserWindow rejects javascript: URL", !RealBrowserWindow.isAllowedURL(URL(string: "javascript:alert(1)")!))
        check("External AI requests remain 0 without opt-in", ExternalAIActivity.shared.requestCount == 0)

        s.restoreDefaults()
        finish()
    }

    private static func cpuTimeMs() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let u = Double(usage.ru_utime.tv_sec) * 1000.0 + Double(usage.ru_utime.tv_usec) / 1000.0
        let sys = Double(usage.ru_stime.tv_sec) * 1000.0 + Double(usage.ru_stime.tv_usec) / 1000.0
        return u + sys
    }

    private static func perfBenchmark() async -> Never {
        let c = GooseController.shared
        let s = GooseSettings.shared
        guard let scene = c.scene else {
            check("perf: scene available", false)
            finish()
        }

        s.restoreDefaults()
        s.language = .english
        s.randomBehavior = false

        for targetCount in [1, 3, 5] {
            s.maxGooseCount = targetCount
            while scene.gooseCount < targetCount { _ = scene.spawnGoose() }
            while scene.gooseCount > targetCount { _ = scene.removeGoose() }

            let tStart = CACurrentMediaTime()
            let cpuStart = cpuTimeMs()
            for i in 0..<300 {
                scene.manager.tickAll(dt: 1.0 / 60.0, currentTime: tStart + Double(i) * (1.0 / 60.0), scene: scene)
            }
            let wallMs = (CACurrentMediaTime() - tStart) * 1000.0
            let cpuDeltaMs = cpuTimeMs() - cpuStart
            let rss = residentMemoryMB()
            let msPerTick = wallMs / 300.0
            print(String(
                format: "PERF geese=%d ticks=300 wall=%.2fms (%.3fms/tick) cpu=%.2fms rss=%.1fMB aiNet=%d activeTasks=%d",
                targetCount, wallMs, msPerTick, cpuDeltaMs, rss,
                ExternalAIActivity.shared.requestCount,
                GlobalActionCoordinator.shared.activeTasks.count
            ))
            check("perf \(targetCount) geese < 16.6ms/tick (60fps budget)", msPerTick < 16.6, String(format: "%.3fms/tick", msPerTick))
            check("perf \(targetCount) geese RSS < 300MB", rss > 0 && rss < 300, String(format: "%.1fMB", rss))
        }

        // Verify background pause idles SKView rendering
        c.pauseAll()
        check("paused idle sets SKView.isPaused = true", c.overlay?.isRenderingPaused == true)
        c.resumeAll()
        check("resumed sets SKView.isPaused = false", c.overlay?.isRenderingPaused == false)

        s.restoreDefaults()
        finish()
    }

    // MARK: Permissions (TCC & diagnostics)

    static func permissions() async -> Never {
        let s = GooseSettings.shared
        s.restoreDefaults()

        // 1. Blank/black image detection
        func makeSolidCGImage(r: UInt8, g: UInt8, b: UInt8) -> CGImage {
            var px = [UInt8](repeating: 0, count: 64 * 64 * 4)
            for i in stride(from: 0, to: px.count, by: 4) {
                px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = 255
            }
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: &px,
                width: 64,
                height: 64,
                bitsPerComponent: 8,
                bytesPerRow: 64 * 4,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return ctx.makeImage()!
        }

        let blackImg = makeSolidCGImage(r: 0, g: 0, b: 0)
        let colorImg = makeSolidCGImage(r: 40, g: 120, b: 200)
        check("black image rejected as blank", ScreenCapturer.isBlackOrBlankImage(blackImg) == true)
        check("non-black image accepted", ScreenCapturer.isBlackOrBlankImage(colorImg) == false)

        // 2. AXError classification never conflates benign window errors with missing TCC
        check("AXError.apiDisabled maps to apiDisabledNeedsRestart",
              AccessibilityProbe.classifyAXError(.apiDisabled, frontmostApp: "Finder") == .apiDisabledNeedsRestart(axError: AXError.apiDisabled.rawValue))
        check("AXError.noValue maps to trustedNoFocusedWindow",
              AccessibilityProbe.classifyAXError(.noValue, frontmostApp: "Finder") == .trustedNoFocusedWindow(frontmostApp: "Finder", axError: AXError.noValue.rawValue))
        check("AXError.attributeUnsupported maps to trustedNoFocusedWindow",
              AccessibilityProbe.classifyAXError(.attributeUnsupported, frontmostApp: "Finder") == .trustedNoFocusedWindow(frontmostApp: "Finder", axError: AXError.attributeUnsupported.rawValue))
        check("AXError.success maps to trustedAndWorking",
              AccessibilityProbe.classifyAXError(.success, frontmostApp: "Finder", windowTitle: "Desktop") == .trustedAndWorking(frontmostApp: "Finder", windowTitle: "Desktop"))

        // 3. PermissionManager never stores grant status in UserDefaults
        let defaultsKeys = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        check("UserDefaults does not cache screenRecordingGranted",
              !defaultsKeys.contains("screenRecordingGranted") && !defaultsKeys.contains("accessibilityGranted"))

        // 4. Permission state transitions & allActivePermissionsReady accuracy
        let pm = PermissionManager.shared
        s.screenRecognition = true
        s.setEnabled(.windowPranks, true)
        pm.setStateForTesting(screen: .notAuthorized, accessibility: .notAuthorized)
        check("not ready when both permissions missing", pm.allActivePermissionsReady == false)
        pm.setStateForTesting(screen: .restartRequired(reason: "Restart needed"), accessibility: .authorized)
        check("not ready when screen recording requires restart", pm.allActivePermissionsReady == false)
        pm.setStateForTesting(screen: .authorized, accessibility: .authorized)
        check("allActivePermissionsReady when both authorized", pm.allActivePermissionsReady == true)

        s.screenRecognition = false
        s.setEnabled(.windowPranks, false)
        s.setEnabled(.windowPeek, false)
        pm.setStateForTesting(screen: .notAuthorized, accessibility: .notAuthorized)
        check("ready when optional permission-gated features disabled", pm.allActivePermissionsReady == true)
        s.restoreDefaults()

        // 5. Real ScreenCapturer & AccessibilityProbe non-crashing behavior
        let capturer = ScreenCapturer()
        let capResult = await capturer.captureMainDisplayResult()
        if CGPreflightScreenCaptureAccess() {
            switch capResult {
            case .success(let img):
                check("live screen capture returned non-black image", !ScreenCapturer.isBlackOrBlankImage(img))
            case .failure(let err):
                check("live screen capture returned typed error instead of crashing", !err.localizedDescription.isEmpty, err.localizedDescription)
            }
        } else {
            if case .failure(.permissionNotGranted) = capResult {
                check("missing screen permission returns .permissionNotGranted", true)
            } else {
                check("missing screen permission returns .permissionNotGranted", false)
            }
        }

        // 6. Diagnostics report & independent simulation fallback
        let report = PermissionDiagnostics.collect(liveAX: AccessibilityProbe.validateLiveAccessibility())
        let formatted = report.formattedText()
        check("diagnostics includes executablePath & arch", !report.executablePath.isEmpty && !report.architecture.isEmpty)
        check("diagnostics text includes bundle ID & recovery section", formatted.contains("Bundle Identifier:") && formatted.contains("tccutil reset ScreenCapture"))

        let sim = GooseSimulation()
        sim.screenSize = CGSize(width: 1200, height: 800)
        sim.position = CGPoint(x: 300, y: 300)
        sim.targetPos = CGPoint(x: 600, y: 300)
        sim.setTask(WanderTask())
        for _ in 0..<10 { sim.tick() }
        check("goose simulation advances without TCC permissions", sim.position.x > 300)

        pm.refreshAll(validateLiveAX: true)
        finish()
    }

    // MARK: Ultimate (Audio, Memes, Notepads, Screen Observation)

    static func ultimate() async -> Never {
        let s = GooseSettings.shared
        s.restoreDefaults()

        // 1. Audio synthesis, mute, and cooldowns
        let engine = SoundEffectEngine.shared
        s.muteGoose = true
        check("muteGoose blocks duck sound", !engine.playDuck(.shortQuack, cooldown: 0))
        check("muteGoose blocks goose sound", !engine.playGoose(.classicHonk, cooldown: 0))
        s.muteGoose = false
        s.masterSoundEnabled = true
        s.duckSoundsEnabled = true
        s.gooseSoundsEnabled = true
        s.footstepsEnabled = true
        check("duck sound plays when unmuted", engine.playDuck(.happyQuack, cooldown: 0))
        check("goose sound plays when unmuted", engine.playGoose(.classicHonk, cooldown: 0))
        check("movement sound plays when unmuted", engine.playMovement(.notepadLand, category: .notepad, cooldown: 0))
        check("cooldown prevents rapid duplicate", !engine.playDuck(.happyQuack, cooldown: 10.0))
        engine.stopAll()

        // 2. UserContentManager: PNG, JPG, animated GIF, UTF-8 Chinese/Emoji, PhrasePacks, deduplication
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("goose-ultimate-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let ucm = UserContentManager(rootURL: tempRoot, watchFilesystem: false)
        check("seeded Example.png exists", ucm.memes.contains { $0.filename == "Example.png" })
        check("seeded phrase pack exists", !ucm.phrasePacks.isEmpty)

        // Create a real 2-frame animated GIF on disk and import it
        let srcDir = tempRoot.appendingPathComponent("ImportSource", isDirectory: true)
        try? FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let gifURL = srcDir.appendingPathComponent("anim.gif")
        if let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, "com.compuserve.gif" as CFString, 2, nil) {
            let gifProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
            CGImageDestinationSetProperties(dest, gifProps)
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary
            for shade in [UInt8(40), UInt8(200)] {
                var px = [UInt8](repeating: shade, count: 16 * 16 * 4)
                let ctx = CGContext(data: &px, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 16 * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                CGImageDestinationAddImage(dest, ctx.makeImage()!, frameProps)
            }
            CGImageDestinationFinalize(dest)
        }
        let gifImport = ucm.importMemes(from: [gifURL])
        check("animated GIF imported", gifImport.imported == 1)
        check("animated GIF detected with 2 frames", ucm.memes.contains { $0.isAnimatedGIF && $0.frameCount == 2 })
        check("original GIF untouched", FileManager.default.fileExists(atPath: gifURL.path))

        let dupImport = ucm.importMemes(from: [gifURL])
        check("duplicate meme rejected", dupImport.imported == 0 && !dupImport.errors.isEmpty)

        if let animItem = ucm.memes.first(where: { $0.isAnimatedGIF }) {
            let decoded = MemeImageDecoder.decode(url: animItem.url)
            check("MemeImageDecoder decodes all GIF frames", decoded?.isAnimated == true && decoded?.frames.count == 2)
            try? ucm.renameMeme(animItem, to: "renamed-anim")
            check("rename meme updates filename", ucm.memes.contains { $0.filename == "renamed-anim.gif" })
            if let renamed = ucm.memes.first(where: { $0.filename == "renamed-anim.gif" }) {
                ucm.deleteMeme(renamed)
                check("delete meme removes item", !ucm.memes.contains { $0.filename == "renamed-anim.gif" })
            }
        }

        // UTF-8 Traditional Chinese & Emoji notepad + PhrasePack parsing
        let zhText = "你真的覺得這樣能成功嗎？🪿\n第二行內容"
        ucm.saveNotepadMessage(filename: "zh-test.txt", content: zhText)
        check("UTF-8 Traditional Chinese notepad loaded intact", ucm.notepadMessages.contains { $0.content == zhText })

        let parsed = UserContentManager.parsePhrasePackLines("# comment\n\nline one\nline one\n你確定嗎？ 🦆\n")
        check("PhrasePack skips # comments, empty lines, and deduplicates", parsed == ["line one", "你確定嗎？ 🦆"])

        // 3. GooseNotepadWindow creation & multi-display clamping
        let npWin = GooseNotepadWindow(title: "zh-test.txt", body: zhText)
        check("GooseNotepadWindow preserves title & body", npWin.noteTitle == "zh-test.txt" && npWin.noteBody == zhText)
        npWin.close()

        let clamped = MemeDeliveryTask.clampWindowOrigin(CGPoint(x: -5000, y: -5000), windowSize: CGSize(width: 280, height: 195), onlyClampAtFinal: true)
        check("off-screen origin clamped back onto visible screen", clamped.x > -5000 && clamped.y > -5000)

        // 4. Smart Screen Observation Modes
        let pm = PermissionManager.shared
        pm.setScreenObservationMode(.disabled)
        check("Mode C (.disabled) sets status .disabled", pm.screenObservationStatus == .disabled)
        let capDisabled = await ScreenCapturer().captureMainDisplayResult()
        if case .failure(.permissionNotGranted) = capDisabled {
            check("Mode C (.disabled) blocks screen capture", true)
        } else {
            check("Mode C (.disabled) blocks screen capture", false)
        }

        pm.setScreenObservationMode(.systemContentPicker)
        ContentSharingPickerController.shared.stopSharing()
        check("Mode B (.systemContentPicker) stopped when no source chosen", pm.screenObservationStatus == .stopped)

        s.restoreDefaults()
        finish()
    }

    // MARK: Runtime (live app)

    static func startRuntime() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            await runtime()
        }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func waitUntil(_ timeout: Double, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            await wait(0.05)
        }
        return cond()
    }

    private static func pressMenu(_ menu: NSMenu, _ title: String) -> Bool {
        guard let idx = menu.items.firstIndex(where: { $0.title == title }) else { return false }
        menu.performActionForItem(at: idx)
        return true
    }

    private static func runtime() async {
        let c = GooseController.shared
        let s = GooseSettings.shared
        guard let scene = c.scene, let delegate = NSApp.delegate as? AppDelegate, let menu = delegate.statusMenu else {
            check("runtime: scene/menu available", false)
            finish()
        }
        let sim = scene.simulation
        s.restoreDefaults()
        s.language = .english

        // Menu structure
        menu.delegate?.menuNeedsUpdate?(menu)
        let expected = ["Open Control Center", "Permission Center…", "Open Settings…", "Pause", "Disable Mouse Theft", "Disable All Pranks",
                        "Hide Goose", "Spawn Goose", "Emergency Stop", "Quit"]
        let titles = menu.items.map(\.title)
        for e in expected { check("menu has '\(e)'", titles.contains(e)) }
        check("menu Settings has ⌘,", menu.items.first { $0.title == "Open Settings…" }?.keyEquivalent == ",")
        check("baseline: running, 1 goose", c.state == .running && scene.gooseCount == 1)

        // Pause / Resume
        check("menu Pause", pressMenu(menu, "Pause"))
        check("state paused", c.state == .paused)
        let p0 = sim.position
        await wait(0.6)
        check("paused goose does not move", sim.position == p0)
        menu.delegate?.menuNeedsUpdate?(menu)
        check("menu now offers Resume", menu.items.map(\.title).contains("Resume"))
        check("menu Resume", pressMenu(menu, "Resume"))
        check("state running", c.state == .running)
        sim.targetPos = CGPoint(x: p0.x + 300, y: p0.y)
        let moved = await waitUntil(4) { CGPoint.distance(sim.position, p0) > 5 }
        check("resumed goose moves again", moved)

        // Hide / Show
        check("menu Hide Goose", pressMenu(menu, "Hide Goose"))
        check("state hidden + overlay hidden", c.state == .hidden && c.overlay?.isVisible == false)
        menu.delegate?.menuNeedsUpdate?(menu)
        check("menu Show Goose", pressMenu(menu, "Show Goose"))
        check("state running + overlay visible", c.state == .running && c.overlay?.isVisible == true)

        // Mouse theft / pranks toggles via menu
        check("menu Disable Mouse Theft", pressMenu(menu, "Disable Mouse Theft"))
        check("mouseTheft off", !s.isEnabled(.mouseTheft))
        menu.delegate?.menuNeedsUpdate?(menu)
        check("menu Enable Mouse Theft", pressMenu(menu, "Enable Mouse Theft"))
        check("mouseTheft on", s.isEnabled(.mouseTheft))
        check("menu Disable All Pranks", pressMenu(menu, "Disable All Pranks"))
        check("pranks disabled; chase refused", s.allPranksDisabled && !GooseReactions.startMouseChase(on: sim))
        menu.delegate?.menuNeedsUpdate?(menu)
        check("menu Enable All Pranks", pressMenu(menu, "Enable All Pranks"))
        check("pranks enabled", !s.allPranksDisabled)

        // Spawn / remove
        s.maxGooseCount = 1
        check("spawn refused at max", !scene.spawnGoose())
        s.maxGooseCount = 3
        check("menu Spawn Goose", pressMenu(menu, "Spawn Goose"))
        c.refresh()
        check("2 geese after spawn", scene.gooseCount == 2)
        c.spawnGoose(); c.refresh()
        check("3 geese", scene.gooseCount == 3)
        await wait(0.5)
        check("per-goose status reported", c.geese.count == 3 && c.geese.allSatisfy { !$0.activity.isEmpty })
        c.removeGoose(); c.refresh()
        check("remove one → 2", scene.gooseCount == 2)
        s.maxGooseCount = 1
        await wait(0.3)
        check("lowering max prunes extras", scene.gooseCount == 1)

        // Mouse theft regression (moves the real cursor briefly)
        let screenH = NSScreen.main?.frame.height ?? 900
        func startPoint() -> CGPoint {
            let m = NSEvent.mouseLocation
            return CGPoint(x: m.x, y: m.y)
        }
        func place(near m: CGPoint) {
            let sz = sim.screenSize
            let x = m.x + 150 < sz.width - 40 ? m.x + 150 : m.x - 150
            sim.position = CGPoint(x: x, y: m.y)
            sim.targetPos = sim.position
            sim.velocity = .zero2
        }
        let origin = CGPoint(x: 600, y: screenH - 500)  // CG (top-left) coords
        CGWarpMouseCursorPosition(origin)
        await wait(0.3)
        let mouse0 = startPoint()
        let thefts0 = GooseStats.shared.mouseTheftsToday
        place(near: mouse0)
        check("start mouse chase (theft ON)", GooseReactions.startMouseChase(on: sim))
        let stole = await waitUntil(12) { GooseStats.shared.mouseTheftsToday > thefts0 }
        check("goose steals the cursor", stole, stole ? "" : "pos=\(sim.position) beak=\(sim.beakPosition) mouse=\(mouse0) nowMouse=\(startPoint()) task=\(type(of: sim.currentTask)) screen=\(sim.screenSize)")
        let dragged = await waitUntil(4) { CGPoint.distance(startPoint(), mouse0) > 100 }
        check("cursor is carried away by goose", dragged, "moved \(Int(CGPoint.distance(startPoint(), mouse0)))px")

        // Emergency stop while the goose holds the cursor
        if !(sim.currentTask is NabMouseTask) {
            CGWarpMouseCursorPosition(origin); await wait(0.3)
            place(near: startPoint()); GooseReactions.startMouseChase(on: sim)
            _ = await waitUntil(8) { (sim.currentTask as? NabMouseTask)?.isCapturing == true }
        }
        let holding = (sim.currentTask as? NabMouseTask)?.isCapturing == true
        check("goose holding cursor before E-stop", holding)
        check("menu Emergency Stop", pressMenu(menu, "Emergency Stop"))
        check("state stopped; task released", c.state == .stopped && sim.currentTask is WanderTask)
        let heldPos = startPoint()
        await wait(0.6)
        check("cursor no longer dragged after E-stop", CGPoint.distance(startPoint(), heldPos) < 3)
        check("chase refused during E-stop", !GooseReactions.startMouseChase(on: sim))
        check("resume after E-stop", { c.resumeAll(); return c.state == .running }())

        // Theft disabled → goose may chase but cannot take the cursor
        CGWarpMouseCursorPosition(origin); await wait(0.3)
        s.setEnabled(.mouseTheft, false)
        s.mouseChaseDuration = 4
        let m1 = startPoint(); place(near: m1)
        let thefts1 = GooseStats.shared.mouseTheftsToday
        check("chase starts (theft OFF)", GooseReactions.startMouseChase(on: sim))
        await wait(6)
        check("no theft when disabled", GooseStats.shared.mouseTheftsToday == thefts1 && CGPoint.distance(startPoint(), m1) < 5)
        check("chase ended on its own", sim.currentTask is WanderTask)
        s.setEnabled(.mouseTheft, true)

        // Settings applied live to the simulation
        s.movementSpeed = 2; s.gooseSize = 1.5; s.animationSpeed = 1.5
        await wait(0.2)
        check("movementSpeed live", sim.speedMultiplier == 2)
        check("gooseSize live", sim.sizeScale == 1.5)
        check("animationSpeed live", sim.animationMultiplier == 1.5)

        // Windows + ⌘,
        check("menu Open Control Center", pressMenu(menu, "Open Control Center"))
        check("Control Center window visible", Windows.controlCenter.isVisible)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                   context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)
        let handled = key.map { NSApp.mainMenu?.performKeyEquivalent(with: $0) ?? false } ?? false
        check("⌘, opens Settings", handled && Windows.settings.isVisible)

        // Phase 2 Runtime checks for all advanced pranks + scheduler + memory
        s.behaviorCooldown = 0
        BehaviorScheduler.shared.resetCooldowns()

        // 1) MouseChaseTask (circle + flee behavior)
        let chaseTask = MouseChaseTask(effects: scene, personality: scene.leadPersonality)
        check("MouseChaseTask schedules", BehaviorScheduler.shared.request(priority: .prank, task: chaseTask, behavior: .mouseChase, timeout: 4, on: sim))
        await wait(0.3)
        check("MouseChaseTask active", sim.currentTask is MouseChaseTask)
        BehaviorScheduler.shared.cancelAll(on: sim)

        // 2) DesktopMessTask + clearDesktopMess
        let messBefore = scene.desktopMess.itemCount
        sim.position = CGPoint(x: 400, y: 400)
        scene.spawnDesktopMess(at: sim.position, count: 3)
        c.refresh()
        check("DesktopMess spawns visual items", scene.desktopMess.itemCount == messBefore + 3 && c.desktopMessCount == messBefore + 3)
        c.clearDesktopMess()
        check("clearDesktopMess removes all items", scene.desktopMess.itemCount == 0 && c.desktopMessCount == 0)

        // 3) GooseTheftTask (visual icon theft + E-stop cleanup)
        scene.spawnDesktopMess(at: CGPoint(x: 320, y: 320), count: 1)
        check("GooseTheftTask schedules", BehaviorScheduler.shared.request(priority: .prank, task: GooseTheftTask(effects: scene), behavior: .gooseTheft, timeout: 6, on: sim))
        await wait(0.3)
        check("GooseTheftTask active", sim.currentTask is GooseTheftTask)
        c.emergencyStop()
        check("E-stop clears GooseTheft cleanly", sim.currentTask is WanderTask)
        c.resumeAll()

        // 4) FakeErrorTask (parody alert window + badge + E-stop dismissal)
        check("FakeErrorTask schedules", BehaviorScheduler.shared.request(priority: .prank, task: FakeErrorTask(effects: scene, personality: scene.leadPersonality), behavior: .fakeErrors, timeout: 5, on: sim))
        await wait(0.5)
        let hasFakeWindow = NSApp.windows.contains { $0.isVisible && $0.title.contains("(Parody)") }
        check("FakeErrorWindow shown with parody title", hasFakeWindow)
        c.emergencyStop()
        await wait(0.2)
        let stillVisibleAfterEStop = NSApp.windows.contains { $0.isVisible && $0.title.contains("(Parody)") }
        check("E-stop closes FakeErrorWindow", !stillVisibleAfterEStop)
        c.resumeAll()

        // 5) WindowPeekTask
        check("WindowPeekTask schedules", BehaviorScheduler.shared.request(priority: .prank, task: WindowPeekTask(effects: scene), behavior: .windowPeek, timeout: 5, on: sim))
        await wait(0.3)
        check("WindowPeekTask active", sim.currentTask is WindowPeekTask)
        BehaviorScheduler.shared.cancelAll(on: sim)

        // 6) Sleep Mode protects from proactive pranks
        check("NapTask schedules", BehaviorScheduler.shared.request(priority: .ambient, task: NapTask(effects: scene, personality: scene.leadPersonality), behavior: .sleepMode, timeout: 5, on: sim))
        await wait(0.1)
        check("Sleep blocks proactive prank", !BehaviorScheduler.shared.request(priority: .prank, task: FakeErrorTask(effects: scene), behavior: .fakeErrors, on: sim))
        BehaviorScheduler.shared.cancelAll(on: sim)

        // 7) WindowPrankTask graceful gating when AX is or isn't granted
        let axGranted = AccessibilityProbe.hasAccessibilityPermission
        let winPrankStarted = BehaviorScheduler.shared.request(priority: .prank, task: WindowPrankTask(effects: scene), behavior: .windowPranks, timeout: 4, on: sim)
        await wait(0.2)
        if axGranted {
            check("WindowPrankTask schedules with AX", winPrankStarted)
            BehaviorScheduler.shared.cancelAll(on: sim)
        } else {
            check("WindowPrankTask safely falls back to Wander when AX not granted", sim.currentTask is WanderTask)
        }

        // Remove all
        c.removeAllGeese(); c.refresh()
        check("remove all → 0 geese", scene.gooseCount == 0)
        c.spawnGoose(); c.refresh()
        check("spawn after remove-all revives lead", scene.gooseCount == 1)

        // Report memory footprint
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let rssMB = kr == KERN_SUCCESS ? Double(info.resident_size) / (1024.0 * 1024.0) : -1
        check("resident memory reasonable (< 300 MB)", rssMB > 0 && rssMB < 300, String(format: "%.1f MB", rssMB))

        s.restoreDefaults()
        finish()
    }

    // MARK: Phase 1 Audit (20x Notepad Edge Drag, Audio Cooldowns, Multi-Screen, Pause/Stop)

    static func phase1Audit() async -> Never {
        let s = GooseSettings.shared
        let dm = DisplayManager.shared
        let engine = SoundEffectEngine.shared
        s.restoreDefaults()
        engine.resetVocalCooldowns()

        // 1. Audio defaults & persistence
        check("default randomHonkFrequency is .low", s.randomHonkFrequency == .low)
        check("default honkCooldown is 20s", s.honkCooldown == 20.0)
        s.randomHonkFrequency = .medium
        s.honkCooldown = 30.0
        let reloaded = GooseSettings(defaults: .standard)
        check("audio settings persist across reload", reloaded.randomHonkFrequency == .medium && reloaded.honkCooldown == 30.0)
        s.restoreDefaults()

        // 2. Global & per-goose honk cooldowns + sleep + mute rules
        let goose1 = UUID()
        let goose2 = UUID()
        let t0 = Date()
        engine.resetVocalCooldowns()
        check("initial random vocal allowed for goose1", engine.canPlayVocal(gooseID: goose1, isMajorEvent: false, isSleeping: false, now: t0))
        engine.recordVocalPlayed(gooseID: goose1, duration: 0.35, now: t0)

        // Immediately after: blocked for both goose1 and goose2 (global cooldown = 20s)
        let t2 = t0.addingTimeInterval(2.0)
        check("global cooldown blocks goose2 at +2s", !engine.canPlayVocal(gooseID: goose2, isMajorEvent: false, isSleeping: false, now: t2))
        check("per-goose cooldown blocks goose1 at +2s", !engine.canPlayVocal(gooseID: goose1, isMajorEvent: false, isSleeping: false, now: t2))

        // After global cooldown (21s): goose2 allowed, goose1 still blocked by per-goose cooldown (28s)
        let t21 = t0.addingTimeInterval(21.0)
        check("global cooldown elapsed at +21s allows goose2", engine.canPlayVocal(gooseID: goose2, isMajorEvent: false, isSleeping: false, now: t21))
        check("per-goose cooldown still blocks goose1 at +21s", !engine.canPlayVocal(gooseID: goose1, isMajorEvent: false, isSleeping: false, now: t21))

        // Sleeping goose cannot emit random honk even when cooldown elapsed
        let t50 = t0.addingTimeInterval(50.0)
        check("sleeping goose blocked from random vocal", !engine.canPlayVocal(gooseID: goose1, isMajorEvent: false, isSleeping: true, now: t50))

        // Major event bypasses normal random cooldown, but cannot stack within majorEventMinGap (2.5s)
        check("major event allowed at +3s", engine.canPlayVocal(gooseID: goose2, isMajorEvent: true, isSleeping: false, now: t0.addingTimeInterval(3.0)))
        engine.recordVocalPlayed(gooseID: goose2, duration: 0.35, now: t0.addingTimeInterval(3.0))
        check("major event cannot stack at +4s", !engine.canPlayVocal(gooseID: goose1, isMajorEvent: true, isSleeping: false, now: t0.addingTimeInterval(4.0)))

        // Mute blocks all vocals
        s.muteGoose = true
        check("muteGoose blocks all vocals", !engine.canPlayVocal(gooseID: goose1, isMajorEvent: true, isSleeping: false, now: t50))
        s.muteGoose = false
        engine.resetVocalCooldowns()

        // 3. 20 consecutive NotepadDeliveryTask edge-drag animations across single & multi-screen layouts
        final class MockEffects: GooseSceneEffects {
            var soundEvents: [HonkEvent] = []
            func attachDraggedWindow(_ window: FloatingWindow, at point: CGPoint, direction: CGFloat) {}
            func updateDraggedWindowPosition(_ point: CGPoint, direction: CGFloat) {}
            func detachDraggedWindow() {}
            func setHeadphones(visible: Bool) {}
            func setMusicNotes(active: Bool) {}
            func setDancing(active: Bool) {}
            func setSleeping(active: Bool) {}
            func showTaunt(_ text: String, at point: CGPoint) {}
            func showFakeError(style: FakeErrorWindow.Style, customText: String?) {}
            func spawnDesktopMess(at point: CGPoint, count: Int) {}
            func takeVirtualIconForTheft() -> (label: String, position: CGPoint)? { nil }
            func attachStolenVirtualIcon(label: String, at point: CGPoint) {}
            func updateStolenVirtualIcon(at point: CGPoint) {}
            func detachStolenVirtualIcon() {}
            func playSoundEvent(_ event: HonkEvent, gooseID: UUID?, isSleeping: Bool) {
                soundEvents.append(event)
            }
            func spawnHearts(at point: CGPoint, count: Int) {}
        }

        let layouts: [[CGRect]] = [
            [CGRect(x: 0, y: 0, width: 1440, height: 900)],
            [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1920, y: 0, width: 2560, height: 1440)],
            [CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 1440, height: 900)],
        ]

        var all20Smooth = true
        var maxObservedStep: CGFloat = 0
        var totalHonksAcross20 = 0

        for run in 0..<20 {
            let layout = layouts[run % layouts.count]
            dm.setCustomScreensForTesting(layout)
            let targetFrame = dm.screenFrames[run % dm.screenFrames.count]
            let sim = GooseSimulation()
            sim.screenSize = dm.unionFrame.size
            sim.position = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            sim.targetPos = sim.position

            let mockEffects = MockEffects()
            let task = NotepadDeliveryTask(gooseID: goose1, title: "note-\(run).txt", body: "Mock taunt #\(run)", effects: mockEffects)
            GlobalActionCoordinator.shared.emergencyStopAll()
            sim.setTask(task)

            var prevOrigin: CGPoint?
            var sawNonInteractiveDuringDrag = false
            var steps = 0
            while !(sim.currentTask is WanderTask) && steps < 1200 {
                GameTime.stepForTesting(dt: 1.0 / 60.0)
                sim.tick()
                if task.currentStage == .draggingIn, let win = task.activeWindow {
                    if !win.isInteractive {
                        sawNonInteractiveDuringDrag = true
                    }
                    let origin = win.frame.origin
                    if let prev = prevOrigin {
                        let jump = hypot(origin.x - prev.x, origin.y - prev.y)
                        maxObservedStep = max(maxObservedStep, jump)
                        if jump > 45 {
                            all20Smooth = false
                        }
                    }
                    prevOrigin = origin
                }
                steps += 1
            }
            if !(sim.currentTask is WanderTask) || !task.isDeliveryCompleted || !sawNonInteractiveDuringDrag {
                all20Smooth = false
            }
            totalHonksAcross20 += mockEffects.soundEvents.count
            NotepadWindowRegistry.shared.closeAll()
        }
        dm.setCustomScreensForTesting(nil)
        check("20x NotepadDeliveryTask completed smoothly without warps or stuck tasks", all20Smooth, String(format: "maxStep=%.1fpx", maxObservedStep))
        check("each NotepadDeliveryTask emitted at most 1 honk event", totalHonksAcross20 <= 20, "totalHonks=\(totalHonksAcross20)")

        // 4. Mid-drag cancellation safety (Pause / Emergency Stop)
        dm.setCustomScreensForTesting([CGRect(x: 0, y: 0, width: 1440, height: 900)])
        let cancelSim = GooseSimulation()
        cancelSim.screenSize = dm.unionFrame.size
        cancelSim.position = CGPoint(x: 200, y: 450)
        let cancelTask = NotepadDeliveryTask(gooseID: goose1, title: "cancel.txt", body: "Should close", effects: nil)
        GlobalActionCoordinator.shared.emergencyStopAll()
        cancelSim.setTask(cancelTask)
        var guardSteps = 0
        while cancelTask.currentStage == .walkingToEdge && guardSteps < 600 {
            GameTime.stepForTesting(dt: 1.0 / 60.0)
            cancelSim.tick()
            guardSteps += 1
        }
        check("mid-drag reached draggingIn", cancelTask.currentStage == .draggingIn && NotepadWindowRegistry.shared.count == 1)
        cancelSim.setTask(WanderTask())
        check("cancelling mid-drag closes in-flight notepad window", NotepadWindowRegistry.shared.count == 0 && GlobalActionCoordinator.shared.activeWindowHolderCount == 0)
        dm.setCustomScreensForTesting(nil)

        // 5. GameTime pause/resume freezes monotonic clock
        GameTime.setPaused(true)
        let pausedT1 = GameTime.time
        try? await Task.sleep(for: .milliseconds(50))
        GameTime.tick()
        let pausedT2 = GameTime.time
        GameTime.setPaused(false)
        check("GameTime freezes while paused", abs(pausedT2 - pausedT1) < 0.0001)

        // 6. GooseArt SpriteKit body pixel verification
        let skView = SKView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
        skView.allowsTransparency = true
        let skScene = SKScene(size: CGSize(width: 220, height: 220))
        skScene.backgroundColor = .clear
        skScene.anchorPoint = .zero
        skView.presentScene(skScene)
        let testGoose = GooseInstance(numericID: 1, isLead: true, screenSize: CGSize(width: 220, height: 220))
        testGoose.simulation.position = CGPoint(x: 110, y: 110)
        testGoose.art.update(simulation: testGoose.simulation)
        skScene.addChild(testGoose.container)
        var whitePx = 0
        var outlinePx = 0
        var orangePx = 0
        if let tex = skView.texture(from: skScene) {
            let rep = NSBitmapImageRep(cgImage: tex.cgImage())
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 {
                        if c.redComponent > 0.94 && c.greenComponent > 0.94 && c.blueComponent > 0.94 {
                            whitePx += 1
                        } else if c.redComponent > 0.70 && c.greenComponent > 0.70 && c.blueComponent > 0.70 {
                            outlinePx += 1
                        } else if c.redComponent > 0.80 && c.blueComponent < 0.30 {
                            orangePx += 1
                        }
                    }
                }
            }
        }
        check("GooseArt renders visible body, outline & beak pixels", whitePx > 500 && outlinePx > 100 && orangePx > 50, "white=\(whitePx) outline=\(outlinePx) orange=\(orangePx)")

        s.restoreDefaults()
        finish()
    }

    // MARK: Phase 2 Comprehensive Feature Tests

    static func phase2Features() async -> Never {
        let s = GooseSettings.shared
        let dm = DisplayManager.shared
        s.restoreDefaults()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("goose-phase2-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // 1. Meme Library: import PNG & GIF, duplicate rejection, category, search, manualOnly, rename, delete, reload
        let ucm = UserContentManager(rootURL: tempRoot, watchFilesystem: false)
        let memeStoreURL = tempRoot.appendingPathComponent("Settings/meme_library.json")
        let memeStore = MemeLibraryStore(contentManager: ucm, storageURL: memeStoreURL)

        let srcDir = tempRoot.appendingPathComponent("ImportSrc", isDirectory: true)
        try? FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let pngURL = srcDir.appendingPathComponent("test_meme.png")
        if let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32 * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let cg = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: pngURL)
        }
        let importRes = memeStore.importMemes(from: [pngURL], category: "Gaming")
        check("meme library imports PNG into Gaming", importRes.imported == 1 && memeStore.items.contains { $0.filename == "test_meme.png" && $0.category == "Gaming" })
        let dupRes = memeStore.importMemes(from: [pngURL], category: "Gaming")
        check("meme library rejects duplicate file", dupRes.imported == 0 && !dupRes.errors.isEmpty)
        check("meme library search finds Gaming meme", memeStore.filteredMemes(search: "test_meme", category: "Gaming").count == 1)

        if var meta = memeStore.items.first(where: { $0.filename == "test_meme.png" }) {
            meta.manualOnly = true
            memeStore.updateMetadata(meta)
            // Only Example.png is eligible for auto-pick now
            let autoPick = memeStore.pickWeightedMeme(category: "Gaming", includeManualOnly: false)
            check("manualOnly meme excluded from auto-pick", autoPick == nil)
            let manualPick = memeStore.pickWeightedMeme(category: "Gaming", includeManualOnly: true)
            check("manualOnly meme included when manual trigger", manualPick?.1.id == meta.id)
        }
        let reloadedMemeStore = MemeLibraryStore(contentManager: ucm, storageURL: memeStoreURL)
        check("meme library persists metadata across reload", reloadedMemeStore.items.contains { $0.filename == "test_meme.png" && $0.category == "Gaming" && $0.manualOnly })

        // 2. Taunt Library: add, edit, duplicate, disabled category, weighted pick, reload
        let tauntURL = tempRoot.appendingPathComponent("Settings/taunt_library.json")
        let tauntStore = TauntLibraryStore(storageURL: tauntURL, seedIfEmpty: true)
        let added = tauntStore.addTaunt(content: "Custom Phase 2 Taunt!", category: "Gaming", weight: 2.5)
        check("taunt library adds entry", added != nil)
        if let added {
            let dup = tauntStore.duplicateTaunt(added)
            check("taunt library duplicates entry", dup.id != added.id && dup.content == added.content)
            tauntStore.deleteTaunt(dup)
        }
        tauntStore.toggleCategoryDisabled("Gaming")
        check("disabled category excluded from random pick", tauntStore.pickWeightedTaunt()?.category != "Gaming")
        tauntStore.toggleCategoryDisabled("Gaming")
        let reloadedTaunts = TauntLibraryStore(storageURL: tauntURL, seedIfEmpty: false)
        check("taunt library persists across reload", reloadedTaunts.entries.contains { $0.content == "Custom Phase 2 Taunt!" })

        // 3. Memo Editor: editable NSTextView, image+caption support, window level never .screenSaver
        let memo = GooseNotepadWindow(title: "Memo Test", body: "Initial text")
        check("Memo Editor NSTextView is editable", memo.editorTextView.isEditable && memo.editorTextView.isSelectable)
        memo.editorTextView.string = "Edited by user"
        check("Memo Editor text edits persist in view", memo.editorTextView.string == "Edited by user")
        check("Memo Editor never uses screenSaver level", memo.level != .screenSaver)
        memo.close()

        if let exampleMeme = ucm.memes.first {
            let memeMemo = GooseNotepadWindow(title: exampleMeme.filename, body: "Caption!", memeItem: exampleMeme)
            check("Memo Editor supports MemeItem container", memeMemo.memeItem?.filename == exampleMeme.filename && memeMemo.editorTextView.string == "Caption!")
            memeMemo.close()
        }

        // 4. Animation Studio: config persistence + all 6 entry styles across multi-screen
        let animURL = tempRoot.appendingPathComponent("Settings/animation_studio.json")
        let animStore = AnimationStudioStore(storageURL: animURL)
        animStore.settings.entryStyle = .dragFromTop
        animStore.settings.exitStyle = .slideDown
        animStore.settings.entryDuration = 2.4
        let reloadedAnim = AnimationStudioStore(storageURL: animURL)
        check("Animation Studio persists entry/exit settings", reloadedAnim.settings.entryStyle == .dragFromTop && reloadedAnim.settings.exitStyle == .slideDown && reloadedAnim.settings.entryDuration == 2.4)

        dm.setCustomScreensForTesting([CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 1440, height: 900)])
        for style in MemoEntryStyle.allCases {
            AnimationStudioStore.shared.settings.entryStyle = style
            let sim = GooseSimulation()
            sim.screenSize = dm.unionFrame.size
            sim.position = CGPoint(x: 500, y: 400)
            let task = NotepadDeliveryTask(gooseID: UUID(), title: "style-\(style.rawValue)", body: "Test", effects: nil)
            GlobalActionCoordinator.shared.emergencyStopAll()
            sim.setTask(task)
            var steps = 0
            while !(sim.currentTask is WanderTask) && steps < 1200 {
                GameTime.stepForTesting(dt: 1.0 / 60.0)
                sim.tick()
                steps += 1
            }
            check("Memo EntryStyle \(style.rawValue) completes smoothly", task.isDeliveryCompleted && sim.currentTask is WanderTask)
            NotepadWindowRegistry.shared.closeAll()
        }
        AnimationStudioStore.shared.resetDefaults()
        dm.setCustomScreensForTesting(nil)

        // 5. Audio Packs & Quiet Hours: WAV import, pack switching, Quiet Hours filtering
        let audioURL = tempRoot.appendingPathComponent("Settings/audio_packs.json")
        let packMgr = AudioPackManager(contentManager: ucm, storageURL: audioURL)
        let customPack = packMgr.createPack(name: "Test Pack")
        let wavURL = srcDir.appendingPathComponent("test_honk.wav")
        // Minimal valid 44-byte WAV header + 16 samples
        var wavData = Data("RIFF".utf8)
        let dataBytes: UInt32 = 32
        var chunkSize = 36 + dataBytes
        wavData.append(Data(bytes: &chunkSize, count: 4))
        wavData.append(Data("WAVEfmt ".utf8))
        var subchunk1: UInt32 = 16; var audioFmt: UInt16 = 1; var numCh: UInt16 = 1
        var sampleRate: UInt32 = 44100; var byteRate: UInt32 = 88200; var blockAlign: UInt16 = 2; var bits: UInt16 = 16
        wavData.append(Data(bytes: &subchunk1, count: 4))
        wavData.append(Data(bytes: &audioFmt, count: 2))
        wavData.append(Data(bytes: &numCh, count: 2))
        wavData.append(Data(bytes: &sampleRate, count: 4))
        wavData.append(Data(bytes: &byteRate, count: 4))
        wavData.append(Data(bytes: &blockAlign, count: 2))
        wavData.append(Data(bytes: &bits, count: 2))
        wavData.append(Data("data".utf8))
        var dSize = dataBytes
        wavData.append(Data(bytes: &dSize, count: 4))
        wavData.append(Data(repeating: 0, count: Int(dataBytes)))
        try? wavData.write(to: wavURL)

        let audioImport = packMgr.importSounds(from: [wavURL], for: .gooseHonk, intoPackID: customPack.id)
        check("AudioPackManager imports WAV sound", audioImport.imported == 1 && packMgr.activePack?.sounds.count == 1)

        packMgr.quietHours = QuietHoursConfig(
            enabled: true,
            startHour: 0, startMinute: 0,
            endHour: 23, endMinute: 59,
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            mode: .fullMute
        )
        check("Quiet Hours active across all weekdays", packMgr.quietHours.isActive())
        packMgr.quietHours.enabled = false

        // 6. Emotion, Energy & Persistence
        let stateURL = tempRoot.appendingPathComponent("Settings/goose_states.json")
        let stateStore = GooseStatePersistence(storageURL: stateURL)
        stateStore.saveState(numericID: 99, emotion: .mischievous, energy: 72.5, naughty: 0.8, aggressive: 0.3, laziness: 0.2, curious: 0.6, affectionate: 0.5)
        let reloadedStates = GooseStatePersistence(storageURL: stateURL)
        let loaded99 = reloadedStates.state(for: 99)
        check("Goose emotion & energy persist across reload", loaded99?.emotion == .mischievous && loaded99?.energy == 72.5)

        let p = GoosePersonality(numericID: 1, isLead: false)
        let eBefore = p.energy
        p.tick(dt: 10.0, isSleeping: false, isActiveTask: true)
        check("active task consumes goose energy", p.energy < eBefore && p.energy >= 0)
        let eLow = p.energy
        p.tick(dt: 10.0, isSleeping: true, isActiveTask: false)
        check("sleeping recovers goose energy", p.energy > eLow && p.energy <= 100)

        // 7. Prank Presets: Peaceful / Normal / Mischievous / Chaos + Custom Preset
        let presetURL = tempRoot.appendingPathComponent("Settings/prank_presets.json")
        let presetMgr = PrankPresetManager(storageURL: presetURL)
        check("4 built-in presets present", presetMgr.builtInPresets.count == 4)
        if let chaos = presetMgr.builtInPresets.first(where: { $0.builtInKey == BuiltInPresetID.chaos.rawValue }) {
            presetMgr.applyPreset(chaos)
            check("Chaos preset preserves safe honkCooldown floor >= 8s", s.honkCooldown >= 8.0)
        }
        let customPreset = presetMgr.createCustomPreset(name: "My Phase 2 Preset")
        let reloadedPresets = PrankPresetManager(storageURL: presetURL)
        check("custom prank preset persists across reload", reloadedPresets.customPresets.contains { $0.id == customPreset.id && $0.name == "My Phase 2 Preset" })

        s.restoreDefaults()
        finish()
    }
}
