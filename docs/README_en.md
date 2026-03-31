# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v1.9.6`
- Release notes: [release/v1.9.6/Release.zh.md](../release/v1.9.6/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v1.9.6

- Added an optional `cpolar` component with install, uninstall, start, stop, status display, web dashboard entry, and live install logs.
- Fixed QQ / WeChat integration initialization on some devices by adding a PRoot native runtime fallback for missing `libproot.so` and related loader binaries.
- Improved dashboard URL handling by stripping accidental `copy`, `copied`, and `GatewayWS` suffixes from token links.
- Added percentage-based progress feedback while switching OpenClaw versions.
- Saving key configuration such as providers or messaging platforms can now auto-restart the gateway when needed so changes apply immediately.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v1.9.6-universal.apk` | Best default choice | 44.01 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-universal.apk) |
| `OpenClaw-v1.9.6-arm64-v8a.apk` | Most modern Android phones | 27.01 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-arm64-v8a.apk) |
| `OpenClaw-v1.9.6-armeabi-v7a.apk` | Older 32-bit ARM devices | 26.64 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-armeabi-v7a.apk) |
| `OpenClaw-v1.9.6-x86_64.apk` | Emulator or x86_64 device | 27.22 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6-x86_64.apk) |
| `OpenClaw-v1.9.6.aab` | Store distribution | 50.82 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v1.9.6/OpenClaw-v1.9.6.aab) |

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
python scripts/build_release.py --version 1.9.6 --build-number 39
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
