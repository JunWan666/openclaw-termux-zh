# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v2.0.3`
- Release notes: [release/v2.0.3/Release.zh.md](../release/v2.0.3/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v2.0.3

- Keeps OpenClaw `2026.3.23` as the default Stable release, exposes npm latest as Experimental, and hides versions older than `2026.3.13` from the picker.
- Adds Gateway v3/v4 negotiation, complete Node.js `engines` validation, protected upgrade transactions, and interrupted-upgrade rollback.
- Detects fresh, complete, repairable, interrupted-upgrade, and manual-recovery environments without deleting the RootFS or user data during automatic repairs.
- OpenClaw `2026.3.13` and newer now receive a minimal non-interactive configuration and proceed directly to the dashboard for API setup.
- Reorders and refreshes AI providers: DeepSeek, NVIDIA Free, and Zhipu appear near the top, while OpenRouter and xAI are removed.
- Adds API-key shortcuts, model catalog fetching, and connection tests for supported providers.
- Custom OpenAI-compatible providers can automatically fetch `/models` after Base URL and API Key entry, while still allowing manual model IDs.
- Preserves custom Provider Base URLs exactly instead of silently appending `/v1`.
- Allows Gateway cold start to be cancelled and cleans up matching leftover PRoot/OpenClaw processes.
- The full Flutter test suite now contains 119 passing tests across version policy, protocol negotiation, environment recovery, upgrade protection, and provider configuration.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v2.0.3-universal.apk` | Best default choice | 46.78 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-universal.apk) |
| `OpenClaw-v2.0.3-arm64-v8a.apk` | Most modern Android phones | 27.96 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-arm64-v8a.apk) |
| `OpenClaw-v2.0.3-armeabi-v7a.apk` | Older 32-bit ARM devices | 27.70 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-armeabi-v7a.apk) |
| `OpenClaw-v2.0.3-x86_64.apk` | Emulator or x86_64 device | 28.19 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3-x86_64.apk) |
| `OpenClaw-v2.0.3.aab` | Store distribution | 67.03 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.3/OpenClaw-v2.0.3.aab) |

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
python scripts/build_release.py --version 2.0.3 --build-number 78
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
