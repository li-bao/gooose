# Building From Source

## Prerequisites
- Apple Silicon Mac (`arm64`)
- macOS 26.1 or later
- Xcode 26.1+ (with `SwiftUIMacros` — ensure `xcode-select -p` points to Xcode.app, or set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)

## Compile & Test
```bash
cd Goose
swift package resolve
swift build -c release --arch arm64
swift test
```

## Optional Sprite & Audio Assets
- **Sprites**: Place compatible frames in `Goose/Sources/Goose/Resources/Sprites/Goose/` (see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)).
- **Audio**: Set `GOOSE_AUDIO_PATH` to a directory containing `Honk1-4.mp3`, `Pat1-3.wav`, and `BITE.mp3`.
