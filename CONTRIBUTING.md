# Contributing to Super Goose Desktop

Contributions are welcome!

## Development Requirements
- Apple Silicon Mac (`arm64`)
- macOS 26.1 or later
- Xcode 26.1+ / Swift 6.2+

## Workflow
1. Fork or branch from `main`.
2. Make changes in `Goose/Sources/Goose/`.
3. Keep `@MainActor` isolation intact for SpriteKit nodes, AppKit windows, `GooseManager`, and `PermissionManager`.
4. Build and run tests from `Goose/`:
   ```bash
   swift package resolve
   swift build -c release --arch arm64
   swift test
   ```
5. Never commit API keys, signing certificates, `.app` bundles, `.dmg` images, or unlicensed third-party assets.
6. Ensure `git diff --check` is clean before opening a Pull Request.
