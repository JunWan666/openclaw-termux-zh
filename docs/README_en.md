# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v2.0.2`
- Release notes: [release/v2.0.2/Release.zh.md](../release/v2.0.2/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v2.0.2

- Merges the setup stability fixes, the previous terminal-performance work, and current unpublished changes into this v2.0.2 package. Android build number is now `77`.
- Large RootFS / Node.js runtime archives are no longer bundled in the APK, bringing the universal APK down to about 45.96 MB and split APKs to about 27 MB.
- Bootstrap resource settings now live on a separate page, with GitHub `basic-resource` defaults plus separate URL/local-file fields for prebuilt RootFS, Ubuntu base RootFS, and Node.js.
- The first-run setup wizard now uses a small-icon header, a step timeline, and a tighter settings area, with localized bootstrap-resource and sample-config copy.
- Buffered terminal output refreshes across configure, onboarding, package install, Weixin install, and the regular terminal, reducing UI jank during verbose OpenClaw output.
- Reduced terminal scrollback from 10000 to 3000 lines to lower memory and rendering pressure.
- Interactive terminals now default to a lighter PRoot fast mode without the heavier SysV IPC compatibility flag.
- DNS preparation is centralized through `ProotDnsService.ensureReady()` instead of repeated per-screen fallback writes.
- Keeps armv7 Node.js compatibility, domestic DNS / Ubuntu mirror fallbacks, apt/dpkg directory preparation, and clearer PRoot failure summaries.
- Bundled sample configs now point to a test-friendly OpenAI-compatible provider so new users can verify the flow quickly.
- The local model page now explicitly warns that the current path is PRoot + llama.cpp + GGUF CPU, not Google AI Edge native GPU.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v2.0.2-universal.apk` | Best default choice | 45.96 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-universal.apk) |
| `OpenClaw-v2.0.2-arm64-v8a.apk` | Most modern Android phones | 27.66 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-arm64-v8a.apk) |
| `OpenClaw-v2.0.2-armeabi-v7a.apk` | Older 32-bit ARM devices | 27.40 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-armeabi-v7a.apk) |
| `OpenClaw-v2.0.2-x86_64.apk` | Emulator or x86_64 device | 27.87 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2-x86_64.apk) |
| `OpenClaw-v2.0.2.aab` | Store distribution | 52.74 MB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v2.0.2/OpenClaw-v2.0.2.aab) |

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
python scripts/build_release.py --version 2.0.2 --build-number 77
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
