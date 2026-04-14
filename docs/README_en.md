# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v2.0.1`
- Release notes: [release/v2.0.1/Release.zh.md](../release/v2.0.1/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v2.0.1

- Fixed custom model names leaking across other providers. Each provider now keeps its own selected or typed model.
- Fixed conversation log loading by reading `.jsonl` session files directly from the app workspace instead of going through an extra proot exec path that could retrigger the missing `resolv.conf` issue.
- Added a dedicated "Local Model & Chat" home shortcut. From there you can install the official `llama.cpp` runtime, browse built-in GGUF recommendations, search public GGUF files online, manage installed models, and jump straight into a local chat page.
- Added built-in Gemma 4 entries and more plain-language device-fit suggestions, so users no longer need to manually hunt for GGUF download links.
- Upgraded the local chat page with stream output, thinking toggles, Markdown rendering, stop generation, collapsible runtime header, memory usage display, API endpoint copy, and the ability to switch between local, saved, or manually entered endpoints.
- Replaced the old backup shortcut flow with a Backup Center that can import, store, switch, restore, and export backups in one place.
- Release metadata is synced back to formal `v2.0.1`, and the Android build number is bumped to `68`.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v2.0.1-universal.apk` | Best default choice | 102.06 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-universal.apk) |
| `OpenClaw-v2.0.1-arm64-v8a.apk` | Most modern Android phones | 83.80 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-arm64-v8a.apk) |
| `OpenClaw-v2.0.1-armeabi-v7a.apk` | Older 32-bit ARM devices | 83.53 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-armeabi-v7a.apk) |
| `OpenClaw-v2.0.1-x86_64.apk` | Emulator or x86_64 device | 84.01 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1-x86_64.apk) |
| `OpenClaw-v2.0.1.aab` | Store distribution | 108.84 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.1/OpenClaw-v2.0.1.aab) |

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
python scripts/build_release.py --version 2.0.1 --build-number 68
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
