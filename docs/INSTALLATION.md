# Installation Guide

## DMG Installation (Apple Silicon)
1. Download or build `Super-Goose-Desktop-Apple-Silicon.dmg`.
2. Double-click the DMG and drag `Super Goose Desktop.app` into `Applications`.
3. Eject the disk image.

## First Launch (Ad-Hoc Signed Builds)
Ad-hoc signed builds (`codesign --sign -`) are **not Apple-notarized**. On first launch:
- **Option A**: Right-click (Control-click) `/Applications/Super Goose Desktop.app` → **Open** → confirm **Open**.
- **Option B**: Open **System Settings → Privacy & Security** → click **Open Anyway**.
- **Option C**: Remove quarantine attribute:
  ```bash
  xattr -cr "/Applications/Super Goose Desktop.app"
  ```

## Always Run From `/Applications`
Keep only one copy at `/Applications/Super Goose Desktop.app` so macOS TCC permissions remain attributed to a single stable bundle path rather than `Downloads` or App Translocation temporary mounts.
