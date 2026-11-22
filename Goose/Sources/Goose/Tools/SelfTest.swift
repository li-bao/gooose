import AppKit
import CoreGraphics
import Foundation

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
}
