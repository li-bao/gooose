# Release & DMG Packaging

Use the scripts in `scripts/` to build, sign, package, and verify a distributable DMG:

```bash
chmod +x scripts/*.sh
./scripts/build-app.sh
./scripts/build-dmg.sh
./scripts/verify-release.sh
```

## Signing Identity
- By default, `scripts/build-app.sh` uses `SIGNING_IDENTITY="-"` (ad-hoc signing).
- For stable TCC identity across builds or external notarized distribution, set `SIGNING_IDENTITY`:
  ```bash
  SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
  ```
- Output artifacts are placed in `dist/` (excluded from Git via `.gitignore`) and verified with `dist/SHA256.txt`.
