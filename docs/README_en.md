# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v1.9.8`
- Release notes: [release/v1.9.8/Release.zh.md](../release/v1.9.8/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v1.9.8

- Setup now prefers bundled or cached Ubuntu RootFS and Node.js 24 archives first, and only falls back to online downloads when the local copy is missing or invalid.
- The setup wizard and homepage version installer now show stage-aware progress, transfer size, live speed, ETA, and rolling detail logs instead of placeholder progress.
- Ubuntu package installation now probes faster mirrors first, and OpenClaw installation uses cached npm tarballs with clearer download, dependency install, and verification stages.
- Homepage gateway state binding, dashboard URL refresh, and config hot-reload behavior are more reliable, and the Maintenance section is now shown above System Info in Settings.
- Release metadata is synced to formal `v1.9.8`, and the Android application ID is restored to `com.junwan666.openclawzh`.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v1.9.8-universal.apk` | Best default choice | 100.27 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-universal.apk) |
| `OpenClaw-v1.9.8-arm64-v8a.apk` | Most modern Android phones | 83.21 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-arm64-v8a.apk) |
| `OpenClaw-v1.9.8-armeabi-v7a.apk` | Older 32-bit ARM devices | 82.84 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-armeabi-v7a.apk) |
| `OpenClaw-v1.9.8-x86_64.apk` | Emulator or x86_64 device | 83.41 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8-x86_64.apk) |
| `OpenClaw-v1.9.8.aab` | Store distribution | 107.08 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.8/OpenClaw-v1.9.8.aab) |

## Quick Start

### Option A: APK

1. Download the APK that matches your device.
2. Install and open the app.
3. Optionally choose a specific OpenClaw version before setup.
4. Complete onboarding and provider configuration.
5. Start the gateway and open `http://127.0.0.1:18789`.

### Option B: Build From Source

```bash
git clone https://github.com/JunWan666/openclaw-termux-zh.git
cd openclaw-termux-zh/flutter_app
flutter pub get
flutter build apk --release
```

To generate the release directory with APKs and AAB:

```bash
python scripts/build_release.py --version 1.9.8 --build-number 43
```

## Repository Structure

- `flutter_app/`: Flutter Android app
- `lib/`: Node / CLI scripts
- `scripts/`: build and dependency scripts
- `release/`: release artifacts and notes
- `CHANGELOG.md`: version history

## Disclaimer

This repository is a community-maintained Chinese integration variant and is not an official upstream release.

## License

MIT. See [LICENSE](../LICENSE).
