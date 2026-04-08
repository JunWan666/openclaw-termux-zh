# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v1.9.9`
- Release notes: [release/v1.9.9/Release.zh.md](../release/v1.9.9/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v1.9.9

- Maintenance now supports two export modes: a config-only `openclaw.json` backup, or a workspace backup that covers the core `/root/.openclaw` runtime data used for memory and session recovery.
- Import now auto-detects config JSON, legacy snapshot JSON, and tagged workspace ZIP archives, so users can choose a file directly without an extra type selector.
- Workspace restore now stops the gateway first and only restores a validated whitelist of paths, reducing the risk of corrupting the whole rootfs with an unsafe archive.
- The setup completion screen now reuses the same backup import flow, making first-run recovery much easier.
- Release metadata is synced to formal `v1.9.9`, and the Android build number is bumped to `44`.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v1.9.9-universal.apk` | Best default choice | 100.34 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-universal.apk) |
| `OpenClaw-v1.9.9-arm64-v8a.apk` | Most modern Android phones | 83.24 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-arm64-v8a.apk) |
| `OpenClaw-v1.9.9-armeabi-v7a.apk` | Older 32-bit ARM devices | 82.88 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-armeabi-v7a.apk) |
| `OpenClaw-v1.9.9-x86_64.apk` | Emulator or x86_64 device | 83.45 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9-x86_64.apk) |
| `OpenClaw-v1.9.9.aab` | Store distribution | 107.14 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.9/OpenClaw-v1.9.9.aab) |

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
python scripts/build_release.py --version 1.9.9 --build-number 44
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
