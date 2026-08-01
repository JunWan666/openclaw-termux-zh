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
NODE_VERSION="${NODE_VERSION:-24.18.1}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.3.23}"
RUNTIME_REVISION="${RUNTIME_REVISION:-1}"
MINIMUM_FREE_SPACE_BYTES="${MINIMUM_FREE_SPACE_BYTES:-1073741824}"

usage() {
  cat <<USAGE
Build an OpenClaw prebuilt Ubuntu rootfs archive.

Usage:
  scripts/build-prebuilt-rootfs.sh [arm64|armhf|amd64]
  scripts/build-prebuilt-rootfs.sh --arch arm64 [--mirror URL]
  scripts/build-prebuilt-rootfs.sh --docker --arch arm64

Output:
  flutter_app/assets/runtime/openclaw-runtime-${OPENCLAW_VERSION}-<arch>.tar.gz
  flutter_app/assets/runtime/runtime-manifest.json

Notes:
  - Run from Linux or WSL.
  - Use --docker on Windows/WSL when host sudo is not available.
  - Cross-arch builds need qemu-user-static installed.
  - The archive contains Ubuntu, Node.js, npm/Corepack and OpenClaw.
  - The APK can still fall back to the existing online bootstrap path.
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
RUNTIME_OUTPUT_NAME="openclaw-runtime-${OPENCLAW_VERSION}-${ROOTFS_ARCH}.tar.gz"
WORK_DIR="$WORK_BASE/$ROOTFS_ARCH"
ROOTFS_DIR="$WORK_DIR/rootfs"
BASE_TARBALL="$CACHE_DIR/$BASE_NAME"
NODE_ARCHIVE="node-v${NODE_VERSION}-linux-${ROOTFS_ARCH}.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"
NODE_TARBALL="$CACHE_DIR/$NODE_ARCHIVE"
RUNTIME_ASSET_DIR="$ROOT_DIR/flutter_app/assets/runtime"
OUTPUT_PATH="$RUNTIME_ASSET_DIR/$RUNTIME_OUTPUT_NAME"
MANIFEST_PATH="$RUNTIME_ASSET_DIR/runtime-manifest.json"
SHA_PATH="$OUTPUT_PATH.sha256"

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
    bash -lc "apt-get update && apt-get install -y --no-install-recommends ca-certificates curl qemu-user-static mount sudo xz-utils && bash scripts/build-prebuilt-rootfs.sh --no-docker --arch '$ROOTFS_ARCH' ${mirror_args[*]}"
  exit 0
fi

need_command curl
need_command tar
need_command xz
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

if [[ ! -s "$NODE_TARBALL" ]]; then
  echo "==> Downloading Node.js $NODE_VERSION"
  curl -fL --retry 3 --connect-timeout 20 -o "$NODE_TARBALL.tmp" "$NODE_URL"
  mv "$NODE_TARBALL.tmp" "$NODE_TARBALL"
else
  echo "==> Reusing cached Node.js $NODE_VERSION"
fi

echo "==> Installing Node.js $NODE_VERSION"
run_root tar -xJf "$NODE_TARBALL" -C "$ROOTFS_DIR/usr/local" --strip-components=1

echo "==> Installing OpenClaw $OPENCLAW_VERSION"
chroot_run npm install --global --omit=dev --no-audit --no-fund "openclaw@$OPENCLAW_VERSION"
chroot_run corepack enable || true

echo "==> Installing runtime compatibility templates"
run_root mkdir -p "$ROOTFS_DIR/root/.openclaw"
run_root cp "$ROOT_DIR/flutter_app/assets/bionic_bypass.js" \
  "$ROOTFS_DIR/root/.openclaw/bionic-bypass.js"
run_root tee "$ROOTFS_DIR/root/.openclaw/node-wrapper.js" >/dev/null <<'EOF'
require('/root/.openclaw/bionic-bypass.js');
const target = process.argv[2];
if (!target) throw new Error('node-wrapper target is required');
process.argv.splice(1, 1);
require(target);
EOF
run_root chmod 755 \
  "$ROOTFS_DIR/usr/local/bin/node" \
  "$ROOTFS_DIR/usr/local/bin/npm" \
  "$ROOTFS_DIR/usr/local/bin/npx" \
  "$ROOTFS_DIR/usr/local/bin/openclaw" \
  "$ROOTFS_DIR/root/.openclaw/node-wrapper.js"

echo "==> Verifying complete runtime"
chroot_run node --version
chroot_run npm --version
chroot_run openclaw --version

echo "==> Cleaning rootfs"
chroot_run apt-get clean
chroot_run npm cache clean --force || true
unmount_rootfs_paths

if [[ "$NEEDS_QEMU" == "1" ]]; then
  run_root rm -f "$ROOTFS_DIR/usr/bin/$QEMU_BIN"
fi

run_root rm -rf \
  "$ROOTFS_DIR/var/lib/apt/lists/"* \
  "$ROOTFS_DIR/var/cache/apt/archives/"*.deb \
  "$ROOTFS_DIR/root/.npm" \
  "$ROOTFS_DIR/root/.cache" \
  "$ROOTFS_DIR/root/.config/configstore" \
  "$ROOTFS_DIR/root/.ssh" \
  "$ROOTFS_DIR/root/.npmrc" \
  "$ROOTFS_DIR/root/.gitconfig" \
  "$ROOTFS_DIR/root/.bash_history" \
  "$ROOTFS_DIR/root/.node_repl_history" \
  "$ROOTFS_DIR/tmp/"* \
  "$ROOTFS_DIR/var/tmp/"*

# Package installation writes build-machine history into these files. Runtime
# directories are retained, but every generated log is removed before packing.
run_root find "$ROOTFS_DIR/var/log" -type f -delete

echo "==> Auditing rootfs for credentials and build residue"
for forbidden_path in \
  root/.npmrc \
  root/.gitconfig \
  root/.ssh \
  root/.bash_history \
  root/.node_repl_history \
  root/.openclaw/openclaw.json \
  root/.openclaw/.env; do
  if run_root test -e "$ROOTFS_DIR/$forbidden_path"; then
    echo "Forbidden runtime image entry remains: $forbidden_path" >&2
    exit 1
  fi
done

if run_root find "$ROOTFS_DIR/var/log" -type f -print -quit | grep -q .; then
  echo "Runtime image still contains build logs" >&2
  exit 1
fi

run_root tee "$ROOTFS_DIR/etc/openclaw-prebuilt-rootfs" >/dev/null <<EOF
format=openclaw-prebuilt-rootfs
codename=$CODENAME
arch=$ROOTFS_ARCH
packages=${PACKAGES[*]}
node_version=$NODE_VERSION
openclaw_version=$OPENCLAW_VERSION
runtime_revision=$RUNTIME_REVISION
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "==> Packing $OUTPUT_PATH"
mkdir -p "$RUNTIME_ASSET_DIR"
TMP_OUTPUT="$WORK_DIR/$RUNTIME_OUTPUT_NAME"
run_root tar --numeric-owner -C "$ROOTFS_DIR" -czf "$TMP_OUTPUT" .
run_root chown "$(id -u):$(id -g)" "$TMP_OUTPUT"
mv "$TMP_OUTPUT" "$OUTPUT_PATH"

ARCHIVE_SHA256="$(sha256sum "$OUTPUT_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$RUNTIME_OUTPUT_NAME" > "$SHA_PATH"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$MANIFEST_PATH" <<EOF
{
  "schemaVersion": 1,
  "runtimeRevision": $RUNTIME_REVISION,
  "architecture": "arm64-v8a",
  "ubuntuVersion": "$UBUNTU_VERSION",
  "nodeVersion": "$NODE_VERSION",
  "openclawVersion": "$OPENCLAW_VERSION",
  "archive": "$RUNTIME_OUTPUT_NAME",
  "archiveSha256": "$ARCHIVE_SHA256",
  "minimumFreeSpaceBytes": $MINIMUM_FREE_SPACE_BYTES,
  "createdAt": "$CREATED_AT"
}
EOF

echo "==> Done: $OUTPUT_PATH"
echo "==> SHA-256: $ARCHIVE_SHA256"
echo "==> Manifest: $MANIFEST_PATH"
