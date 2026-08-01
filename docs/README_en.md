# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build of OpenClaw for Android.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)

## Current Version

- Version: `v3.0.0` (base build 81; ARM64 APK versionCode 2081)
- Release notes: [release/v3.0.0/Release.zh.md](../release/v3.0.0/Release.zh.md)
- Change log: [CHANGELOG.md](../CHANGELOG.md)
- Releases page: <https://github.com/JunWan666/openclaw-termux-zh/releases>

## What's New In v3.0.0

- Bundles Ubuntu 24.04.3, Node.js 24.18.1, npm 11.16.0, and OpenClaw 2026.3.23 in the ARM64 APK.
- Redesigns the welcome, initialization progress, deployment activity, and completion screens.
- Adds the default `7749API (ywd public service)` provider with model catalog retrieval.
- Marks OpenClaw 2026.7.1 as Latest and Recommended while keeping 2026.3.23 locally restorable.
- Adds protected version switching, complete installed-version snapshots, and a persistent 1 GB npm cache.
- Improves Gateway cold starts, Web dashboard loading, configuration migration, and in-app notices.
- The full Flutter test suite contains 139 passing tests.

## Download Artifacts

| File | Target Device | Size | Download |
|---|---|---:|---|
| `OpenClaw-v3.0.0-arm64-v8a-full.apk` | Android 10+ ARM64 devices | 331.90 MiB | [Download](https://github.com/JunWan666/openclaw-termux-zh/releases/download/v3.0.0/OpenClaw-v3.0.0-arm64-v8a-full.apk) |

## Quick Start

### Option A: APK

1. Existing users must export a backup, uninstall the old signed app, and then install v3.0.0.
2. Complete the local bundled-runtime initialization.
3. Import the old backup if needed, then start the Gateway.

### Option B: Build From Source

```bash
git clone https://github.com/JunWan666/openclaw-termux-zh.git
cd openclaw-termux-zh
git lfs pull
python scripts/build_release.py --version 3.0.0 --build-number 81 --non-interactive
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
