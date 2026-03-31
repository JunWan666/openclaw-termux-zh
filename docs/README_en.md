# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v1.9.7`
- Release notes: [release/v1.9.7/Release.zh.md](../release/v1.9.7/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v1.9.7

- Added a confirmation dialog before installing the selected OpenClaw version, and skip reinstalling when the selected version is already installed.
- Snapshot exports now include both app and OpenClaw version metadata in the file name, and imports warn before restoring mismatched versions.
- Gateway auth tokens now prefer values from `openclaw.json` or `.env`, improving dashboard URL resolution and Node authentication stability.
- Filtered noisy upstream compatibility logs and rewrote common Android-only warnings into clearer status messages.
- Default Ubuntu timezone is now `Asia/Shanghai`, and cpolar gets an extra `resolv.conf` fallback to reduce startup failures.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v1.9.7-universal.apk` | Best default choice | 44.04 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-universal.apk) |
| `OpenClaw-v1.9.7-arm64-v8a.apk` | Most modern Android phones | 27.02 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-arm64-v8a.apk) |
| `OpenClaw-v1.9.7-armeabi-v7a.apk` | Older 32-bit ARM devices | 26.66 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-armeabi-v7a.apk) |
| `OpenClaw-v1.9.7-x86_64.apk` | Emulator or x86_64 device | 27.23 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7-x86_64.apk) |
| `OpenClaw-v1.9.7.aab` | Store distribution | 50.85 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.7/OpenClaw-v1.9.7.aab) |

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
python scripts/build_release.py --version 1.9.7 --build-number 40
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
