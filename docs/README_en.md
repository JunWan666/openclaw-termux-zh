# OpenClaw Chinese Integration Edition (openclaw-termux-zh)

[简体中文](../README.md) | [English](README_en.md)

> This repository is a Chinese-focused integration build.
>
> Integrated from:
> - Upstream project: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
> - Translation branch by author: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)
>
> This repo keeps upstream core functionality while integrating i18n-related changes and Chinese-first documentation.

---

## Overview

OpenClaw provides an Android-ready AI gateway workflow using Flutter + proot Ubuntu (no root required):

- One-tap Ubuntu rootfs + Node.js + OpenClaw setup
- Built-in terminal, logs, and web dashboard
- Gateway lifecycle management and health checks
- Optional developer packages (Go, Homebrew, OpenSSH)
- Node capability bridge (camera, location, sensors, etc.)

---

## Current Version

- Version: `v1.9.4`
- Release notes: [release/v1.9.4/Release.zh.md](../release/v1.9.4/Release.zh.md)
- Change details: [CHANGELOG.md](../CHANGELOG.md)

---

## Quick Start

### Option A: APK (Recommended)

1. Download an APK from this repository Releases (if published)
2. Install and open the app
3. Optionally choose a specific OpenClaw version, then tap **Begin Setup**
4. Complete onboarding and API key setup
5. Start the gateway

### Option B: Build from source

```bash
git clone https://github.com/JunWan666/openclaw-termux-zh.git
cd openclaw-termux-zh/flutter_app
flutter pub get
flutter build apk --release
```

Note: for runnable proot binaries, prepare `jniLibs` with repository scripts before packaging.

---

## Repository Structure

- `flutter_app/`: Flutter Android app
- `lib/`: Node/CLI scripts
- `scripts/`: build and dependency scripts
- `README.md`: Chinese primary documentation
- `CHANGELOG.md`: version and change records

---

## Upstream Sync Strategy

To keep this fork updated:

1. Sync upstream `main`
2. Resolve conflicts in an integration branch
3. Re-test setup flow (install, rootfs extraction, gateway startup)
4. Update `CHANGELOG.md`

---

## Disclaimer

This repository is a community-maintained Chinese integration variant, not an official upstream release.

---

## License

MIT. See [LICENSE](../LICENSE).
