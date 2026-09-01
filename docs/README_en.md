# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v3.0.1` (base build 82; ARM64 APK versionCode 2082)
- Release notes: [release/v3.0.1/Release.zh.md](../release/v3.0.1/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v3.0.1

- Bundles Ubuntu 24.04.3, Node.js 24.18.1, npm 11.16.0, and OpenClaw 2026.3.23 in the ARM64 APK.
- Guides first-run users to configure the official DeepSeek API without bundling a usable third-party API key.
- Migrates legacy 7749API IDs, endpoints, and model references to the new `open7749` configuration while preserving user keys.
- Makes QQ Bot and Weixin plugin detection and installation explicit user actions, with a dedicated QQ terminal installer.
- Fixes llama.cpp runtime selection when the latest stable release does not contain Ubuntu binaries.
- Moves local runtime installation and logs to the front of the local-model workflow.
- The full Flutter test suite contains 142 passing tests; the Node suite contains 11 passing tests.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v3.0.1-arm64-v8a-full.apk` | Android 10+ ARM64 devices | 331.91 MiB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v3.0.1/OpenClaw-v3.0.1-arm64-v8a-full.apk) |

## Quick Start

### Option A: APK

1. v3.0.0 users can install v3.0.1 directly; 2.x users must export a backup and uninstall the old signed app first.
2. Complete the local bundled-runtime initialization.
3. Import the old backup if needed, then start the Gateway.

### Option B: Build From Source

```bash
git clone https://github.com/JunWan666/openclaw-termux-zh.git
cd openclaw-termux-zh
git lfs pull
python scripts/build_release.py --version 3.0.1 --build-number 82 --non-interactive
```

The release script produces only the ARM64 full APK because the bundled RootFS is ARM64-specific.

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
