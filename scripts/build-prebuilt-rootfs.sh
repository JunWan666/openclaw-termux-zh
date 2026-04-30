#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSET_DIR="$ROOT_DIR/flutter_app/assets/bootstrap"
CACHE_DIR="${OPENCLAW_ROOTFS_CACHE:-$ROOT_DIR/.tmp/rootfs-cache}"
WORK_BASE="${OPENCLAW_ROOTFS_WORKDIR:-$ROOT_DIR/.tmp/prebuilt-rootfs}"

CODENAME="${CODENAME:-noble}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.3}"
ARCH="arm64"
MIRROR=""
USE_DOCKER=0
NO_DOCKER=0
PACKAGES=(ca-certificates git python3 make g++ curl wget)

usage() {
  cat <<USAGE
Build an OpenClaw prebuilt Ubuntu rootfs archive.

Usage:
  scripts/build-prebuilt-rootfs.sh [arm64|armhf|amd64]
  scripts/build-prebuilt-rootfs.sh --arch arm64 [--mirror URL]
  scripts/build-prebuilt-rootfs.sh --docker --arch arm64

Output:
  flutter_app/assets/bootstrap/openclaw-rootfs-${CODENAME}-<arch>.tar.gz

Notes:
  - Run from Linux or WSL.
  - Use --docker on Windows/WSL when host sudo is not available.
  - Cross-arch builds need qemu-user-static installed.
  - The APK will still fall back to standard Ubuntu base + apt if this archive
    is missing, corrupt, or does not contain the required base packages.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="${2:-}"
      shift 2
      ;;
    --mirror)
      MIRROR="${2:-}"
      shift 2
      ;;
    --docker)
      USE_DOCKER=1
      shift
      ;;
    --no-docker)
      NO_DOCKER=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    arm64|armhf|amd64)
      ARCH="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$ARCH" in
  arm64)
    ROOTFS_ARCH="arm64"
    QEMU_BIN="qemu-aarch64-static"
    DEFAULT_MIRROR="http://ports.ubuntu.com/ubuntu-ports"
    ;;
  armhf)
    ROOTFS_ARCH="armhf"
    QEMU_BIN="qemu-arm-static"
    DEFAULT_MIRROR="http://ports.ubuntu.com/ubuntu-ports"
    ;;
  amd64)
    ROOTFS_ARCH="amd64"
    QEMU_BIN="qemu-x86_64-static"
    DEFAULT_MIRROR="http://archive.ubuntu.com/ubuntu"
    ;;
  *)
    echo "Unsupported arch: $ARCH" >&2
    exit 2
    ;;
esac

MIRROR="${MIRROR:-$DEFAULT_MIRROR}"
BASE_NAME="ubuntu-base-${UBUNTU_VERSION}-base-${ROOTFS_ARCH}.tar.gz"
BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/$BASE_NAME"
OUTPUT_NAME="openclaw-rootfs-${CODENAME}-${ROOTFS_ARCH}.tar.gz"
WORK_DIR="$WORK_BASE/$ROOTFS_ARCH"
ROOTFS_DIR="$WORK_DIR/rootfs"
BASE_TARBALL="$CACHE_DIR/$BASE_NAME"
OUTPUT_PATH="$ASSET_DIR/$OUTPUT_NAME"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [[ "$USE_DOCKER" == "1" && "$NO_DOCKER" != "1" ]]; then
  need_command docker
  mirror_args=()
  if [[ -n "$MIRROR" ]]; then
    mirror_args=(--mirror "$MIRROR")
  fi
  case "$ROOTFS_ARCH" in
    arm64)
      echo "==> Registering Docker binfmt for arm64"
      docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null
      ;;
    armhf)
      echo "==> Registering Docker binfmt for arm"
      docker run --privileged --rm tonistiigi/binfmt --install arm >/dev/null
      ;;
  esac
  echo "==> Starting privileged Ubuntu builder container"
  docker run --rm --privileged \
    -v "$ROOT_DIR:/work" \
    -w /work \
    -e CODENAME="$CODENAME" \
    -e UBUNTU_VERSION="$UBUNTU_VERSION" \
    -e OPENCLAW_ROOTFS_CACHE=/tmp/openclaw-rootfs-cache \
    -e OPENCLAW_ROOTFS_WORKDIR=/tmp/openclaw-prebuilt-rootfs \
    ubuntu:24.04 \
    bash -lc "apt-get update && apt-get install -y --no-install-recommends ca-certificates curl qemu-user-static mount sudo && bash scripts/build-prebuilt-rootfs.sh --no-docker --arch '$ROOTFS_ARCH' ${mirror_args[*]}"
  exit 0
fi

need_command curl
need_command tar
need_command mountpoint
if [[ "$(id -u)" != "0" ]]; then
  need_command sudo
fi

run_root() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

HOST_ARCH="$(uname -m)"
NEEDS_QEMU=1
case "$ROOTFS_ARCH:$HOST_ARCH" in
  arm64:aarch64|amd64:x86_64|armhf:armv7l|armhf:armv8l)
    NEEDS_QEMU=0
    ;;
esac

if [[ "$NEEDS_QEMU" == "1" ]]; then
  need_command "$QEMU_BIN"
fi

mounted_paths=()

mount_rootfs_path() {
  local source="$1"
  local target="$2"
  local mode="$3"
  run_root mkdir -p "$target"
  if mountpoint -q "$target"; then
    return
  fi
  if [[ "$mode" == "proc" ]]; then
    run_root mount -t proc proc "$target"
  else
    run_root mount --rbind "$source" "$target"
  fi
  mounted_paths+=("$target")
}

unmount_rootfs_paths() {
  local index
  for ((index=${#mounted_paths[@]} - 1; index >= 0; index--)); do
    run_root umount -l "${mounted_paths[$index]}" >/dev/null 2>&1 || true
  done
  mounted_paths=()
}

cleanup() {
  unmount_rootfs_paths
}
trap cleanup EXIT

chroot_run() {
  local env_args=(
    HOME=/root
    TERM=xterm-256color
    DEBIAN_FRONTEND=noninteractive
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  )
  if [[ "$NEEDS_QEMU" == "1" ]]; then
    run_root chroot "$ROOTFS_DIR" "/usr/bin/$QEMU_BIN" /usr/bin/env -i "${env_args[@]}" "$@"
  else
    run_root chroot "$ROOTFS_DIR" /usr/bin/env -i "${env_args[@]}" "$@"
  fi
}

echo "==> Building prebuilt rootfs: $OUTPUT_NAME"
echo "    Ubuntu base: $BASE_URL"
echo "    Mirror:      $MIRROR"

mkdir -p "$CACHE_DIR" "$ASSET_DIR" "$WORK_DIR"
if [[ ! -s "$BASE_TARBALL" ]]; then
  echo "==> Downloading Ubuntu base rootfs"
  curl -fL --retry 3 --connect-timeout 20 -o "$BASE_TARBALL.tmp" "$BASE_URL"
  mv "$BASE_TARBALL.tmp" "$BASE_TARBALL"
else
  echo "==> Reusing cached Ubuntu base rootfs"
fi

echo "==> Extracting workspace"
run_root rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"
run_root tar -xzf "$BASE_TARBALL" -C "$ROOTFS_DIR"

if [[ "$NEEDS_QEMU" == "1" ]]; then
  echo "==> Installing qemu helper for cross-arch chroot"
  run_root cp "$(command -v "$QEMU_BIN")" "$ROOTFS_DIR/usr/bin/$QEMU_BIN"
  run_root chmod 755 "$ROOTFS_DIR/usr/bin/$QEMU_BIN"
fi

echo "==> Preparing apt/dpkg config"
run_root mkdir -p \
  "$ROOTFS_DIR/etc/apt/apt.conf.d" \
  "$ROOTFS_DIR/etc/dpkg/dpkg.cfg.d" \
  "$ROOTFS_DIR/etc/apt/sources.list.d" \
  "$ROOTFS_DIR/usr/sbin" \
  "$ROOTFS_DIR/etc/ssl/certs" \
  "$ROOTFS_DIR/var/lib/apt/lists/partial" \
  "$ROOTFS_DIR/var/cache/apt/archives/partial" \
  "$ROOTFS_DIR/var/lib/dpkg/updates" \
  "$ROOTFS_DIR/var/lib/dpkg/triggers"

run_root rm -f "$ROOTFS_DIR/etc/apt/sources.list.d/ubuntu.sources"
run_root tee "$ROOTFS_DIR/etc/apt/sources.list" >/dev/null <<EOF
deb $MIRROR $CODENAME main restricted universe multiverse
deb $MIRROR ${CODENAME}-updates main restricted universe multiverse
deb $MIRROR ${CODENAME}-backports main restricted universe multiverse
deb $MIRROR ${CODENAME}-security main restricted universe multiverse
EOF

run_root tee "$ROOTFS_DIR/etc/apt/apt.conf.d/01-openclaw-proot" >/dev/null <<'EOF'
APT::Sandbox::User "root";
Acquire::Languages "none";
Acquire::Retries "3";
Acquire::http::Timeout "20";
Acquire::https::Timeout "20";
Dpkg::Use-Pty "0";
Dpkg::Options { "--force-confnew"; "--force-overwrite"; };
EOF

run_root tee "$ROOTFS_DIR/etc/dpkg/dpkg.cfg.d/01-openclaw-proot" >/dev/null <<'EOF'
force-unsafe-io
no-debsig
force-overwrite
force-depends
EOF

run_root tee "$ROOTFS_DIR/usr/sbin/policy-rc.d" >/dev/null <<'EOF'
#!/bin/sh
exit 101
EOF
run_root chmod 755 "$ROOTFS_DIR/usr/sbin/policy-rc.d"

run_root tee "$ROOTFS_DIR/etc/resolv.conf" >/dev/null <<'EOF'
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 8.8.8.8
EOF

run_root ln -sf /usr/share/zoneinfo/Asia/Shanghai "$ROOTFS_DIR/etc/localtime" || true
echo "Asia/Shanghai" | run_root tee "$ROOTFS_DIR/etc/timezone" >/dev/null

mount_rootfs_path proc "$ROOTFS_DIR/proc" proc
mount_rootfs_path /dev "$ROOTFS_DIR/dev" bind
mount_rootfs_path /sys "$ROOTFS_DIR/sys" bind

echo "==> Installing base packages: ${PACKAGES[*]}"
chroot_run apt-get update
chroot_run apt-get install -y --no-install-recommends "${PACKAGES[@]}"

echo "==> Cleaning rootfs"
chroot_run apt-get clean
unmount_rootfs_paths

if [[ "$NEEDS_QEMU" == "1" ]]; then
  run_root rm -f "$ROOTFS_DIR/usr/bin/$QEMU_BIN"
fi

run_root rm -rf \
  "$ROOTFS_DIR/var/lib/apt/lists/"* \
  "$ROOTFS_DIR/var/cache/apt/archives/"*.deb \
  "$ROOTFS_DIR/tmp/"* \
  "$ROOTFS_DIR/var/tmp/"*

run_root tee "$ROOTFS_DIR/etc/openclaw-prebuilt-rootfs" >/dev/null <<EOF
format=openclaw-prebuilt-rootfs
codename=$CODENAME
arch=$ROOTFS_ARCH
packages=${PACKAGES[*]}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "==> Packing $OUTPUT_PATH"
TMP_OUTPUT="$WORK_DIR/$OUTPUT_NAME"
run_root tar --numeric-owner -C "$ROOTFS_DIR" -czf "$TMP_OUTPUT" .
run_root chown "$(id -u):$(id -g)" "$TMP_OUTPUT"
mv "$TMP_OUTPUT" "$OUTPUT_PATH"

echo "==> Done: $OUTPUT_PATH"
