# Super Goose Desktop 2.0 — System Architecture

## 1. High-Level Module Overview

Built natively with **Swift 6.2 (`swift-tools-version: 6.2`)**, **AppKit**, **SwiftUI**, **SpriteKit**, **ScreenCaptureKit**, **Vision**, **ApplicationServices**, **ServiceManagement**, **Carbon** (`RegisterEventHotKey`), and **UserNotifications**, targeting **Apple Silicon (`arm64`)** on **macOS 26.1+**.

```
Sources/Goose/
├── main.swift                         # Entry point & CLI flags (--render-preview, --brain-dryrun, --selftest-*)
├── App/
│   ├── AppDelegate.swift              # NSApplicationDelegate, Status Bar Menu, lifecycle, screen-change wiring
│   ├── GooseController.swift          # @MainActor observable facade bridging UI, Menu Bar & GooseManager
│   ├── DisplayManager.swift           # Multi-display union frame, Cocoa/Scene/CG coordinate mapping, relocation
│   ├── OverlayWindow.swift            # Click-through NSWindow (.screenSaver) + SKView pause/FPS control
│   └── NotificationManager.swift      # Bundle-safe UNUserNotificationCenter wrapper & 5 category toggles
├── Engine/
│   ├── GooseManager.swift             # Multi-goose lifecycle owner (hard cap: 5 geese), tick loop
│   ├── GooseInstance.swift            # Per-goose actor state (UUID, personality, simulation, art, energy, cooldowns)
│   ├── GoosePersonality.swift         # Stateful trait model (drift from pats, pokes, idle time, sleep)
│   ├── GooseInteractionSystem.swift   # Peer interactions (flock gather, chase/avoid, walk together, spectate)
│   ├── GooseSimulation.swift          # Kinematic walk/turn/foot/neck physics & task runner
│   ├── FootMark.swift, GameTime.swift, Deck.swift, Easings.swift, SamMath.swift, Vec2Math.swift
├── AI/
│   ├── GlobalActionCoordinator.swift  # Exclusive Mutexes (Mouse Lock & Window Lock), priority preemption & E-stop
│   ├── BehaviorScheduler.swift        # Priority scheduler, sleep protection, cooldowns, fullscreen suppression
│   ├── AgentDirector.swift            # Brain loop scheduling proactive AI decisions & fallback pools
│   ├── GooseBrain.swift               # Decision tree integrating traits, chaos settings & snapshots
│   ├── LLMRouter.swift, FoundationModelClient.swift, OpenAIClient.swift, SettingsAwareLLM.swift
│   ├── ChillingTicker.swift, HonkTicker.swift, GooseAction.swift, GooseSceneEffects.swift, Personality.swift
├── Perception/
│   ├── PerceptionEngine.swift         # Coalesced (5s TTL) frontmost app + Vision OCR snapshot producer
│   ├── AccessibilityProbe.swift       # AXIsProcessTrusted & frontmost external window bounds/title
│   ├── FullscreenMonitor.swift        # Fullscreen game & media/presentation detector + exception list
│   ├── ScreenCapturer.swift, OCRRecognizer.swift, ContextSnapshot.swift
├── Tasks/                             # State machines for 15 behaviors (NabMouse, MouseChase, Wander, Nap, DeepSleep,
│                                      # FakeError, DesktopMess, GooseTheft, WindowPeek, WindowPrank, DragWindow,
│                                      # Browse, Chilling, GooseInteraction, GooseTask)
├── Scene/
│   ├── GooseScene.swift               # SKScene hosting per-goose SKNodes & DesktopMessOverlay
│   ├── GooseArt.swift, GooseRig.swift, DesktopMessOverlay.swift, HeartParticles.swift, HeadphonesNode.swift, ...
├── Input/
│   ├── GlobalHotkeyManager.swift      # Carbon RegisterEventHotKey for 6 global shortcuts
│   └── EscQuitMonitor.swift           # Hold-ESC emergency eviction overlay
├── Audio/
│   ├── AudioPlayer.swift              # Event-tailored AVAudioPlayer (GOOSE_AUDIO_PATH / Bundle)
│   └── SpotifyController.swift        # Regex-guarded osascript controller for local Spotify app
├── UI/
│   ├── SettingsView.swift             # 9-tab NavigationSplitView macOS Settings UI (SwiftUI)
│   ├── ControlCenterView.swift        # Live status, metrics, per-goose view & quick actions
│   ├── SettingsComponents.swift, SwiftUIWindowController.swift
├── Windows/
│   ├── FloatingWindow.swift, FakeErrorWindow.swift, RealBrowserWindow.swift
├── Settings/
│   ├── GooseSettings.swift            # UserDefaults-backed ObservableObject (schemaVersion = 3)
│   └── L10n.swift                     # English & Traditional Chinese (zh-Hant) localization
├── Photos/PhotoLibrary.swift
└── Tools/
    ├── PreviewRenderer.swift          # --render-preview PNG renderer
    └── SelfTest.swift                 # Logic, Persistence, Multi-Goose, Phase 4, Perf & Runtime self-tests
```

---

## 2. Core Concurrency & State Ownership

- **Single `@MainActor` Simulation Invariant**: UI (`SettingsView`, `ControlCenterView`), SpriteKit rendering (`GooseScene`, `GooseArt`), `GooseManager`, `GlobalActionCoordinator`, `BehaviorScheduler`, and `PerceptionEngine` run on `@MainActor`, preventing cross-thread mutable state races on `SKNode` trees or AppKit windows.
- **Resource Arbitration (`GlobalActionCoordinator`)**:
  - `activeMouseHolderCount <= 1` and `activeWindowHolderCount <= 1` at all times.
  - Any cursor warp (`warpMouseGuarded(to:lease:)`) or AX window drag checks a live `ResourceLease` issued by `GlobalActionCoordinator`, automatically expired after `maxMouseLockDuration = 20.0s` / `maxWindowLockDuration = 20.0s` or immediately revoked on goose removal or `emergencyStopAll()`.
- **Multi-Display Coordinate Pipeline (`DisplayManager`)**:
  - Computes `unionFrame` across `NSScreen.screens`.
  - Translates Cocoa bottom-left coordinates to SKScene coordinates (`globalToScene`, `sceneToGlobal`) and Quartz top-left coordinates (`sceneToCG`) for `CGWarpMouseCursorPosition`.
  - Subscribes to `NSApplication.didChangeScreenParametersNotification` so disconnected displays trigger `GooseManager.relocateOffscreenGeese`, clamping stray geese onto the nearest visible screen.

---

## 3. Data Flow Diagram

```
  NSWorkspace / AXProbe / SCStream+Vision ──► PerceptionEngine (5s coalesce)
                                                      │
  NSScreen / FullscreenMonitor ───────────────────────┤
                                                      ▼
                                            BehaviorScheduler
                                      (priority + sleep + fullscreen)
                                                      │
                                                      ▼
  GooseSettings ──► GooseManager ──► GooseInstance ──► Task ──► GlobalActionCoordinator (Mouse/Window Lease)
  (UserDefaults v3)    (1..5)        (Personality)                     │
                                                      │                ▼
                                                      ▼         CGWarpMouseCursorPosition / AXUIElement
                                                 GooseScene
                                           (OverlayWindow / SKView)
```
