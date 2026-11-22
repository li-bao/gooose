# Third-Party Notices

This repository builds upon and acknowledges the following projects and external assets:

## 1. Upstream Swift macOS Project
- **Project**: `PKrutaa/super-goose-desktop`
- **URL**: https://github.com/PKrutaa/super-goose-desktop
- **License**: MIT License (`Copyright (c) 2026 PKrutaa`)
- **Usage**: Core Swift 6 / SpriteKit application architecture, simulation physics, perception pipeline, and original desktop pet behaviors.

## 2. Original Concept
- **Project**: Desktop Goose by Sam Chiet (`samperson`)
- **URL**: https://samperson.itch.io/desktop-goose
- **Relationship**: Independent Swift reimagining inspired by the original Windows/C# Desktop Goose; no C# source binaries are redistributed.

## 3. Goose Sprites (Not Redistributed in Git)
- **Source**: `romainflcht/py-goose`
- **URL**: https://github.com/romainflcht/py-goose
- **License**: Upstream repository does not declare an OSI-approved open-source license (`license: null`).
- **Handling**: Sprite PNGs are **not** committed or redistributed in this repository. During local setup/builds, developers can supply compatible sprites in `Goose/Sources/Goose/Resources/Sprites/Goose/`.

## 4. Audio Samples (Not Redistributed)
- **Origin**: *Untitled Goose Game* sound samples referenced by `AudioPlayer.swift` (`Honk1-4.mp3`, `Pat1-3.wav`, `BITE.mp3`).
- **Handling**: Audio files are **not** bundled or redistributed in this repository due to copyright restrictions. Users may optionally supply their own audio files via `GOOSE_AUDIO_PATH`.

## 5. System Frameworks
- Built against native Apple macOS SDK frameworks: `AppKit`, `SwiftUI`, `SpriteKit`, `ScreenCaptureKit`, `Vision`, `ApplicationServices`, `Security`, `ServiceManagement`, `Carbon`, `UserNotifications`, `WebKit`, `AVFoundation`, and `FoundationModels`.
