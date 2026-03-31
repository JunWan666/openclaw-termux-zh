import 'package:flutter/material.dart';

/// Metadata for an optional development tool that can be installed
/// inside the proot Ubuntu environment.
class OptionalPackage {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String installCommand;
  final String uninstallCommand;

  /// Path relative to rootfs dir to check if installed.
  final String checkPath;
  final String estimatedSize;

  /// Pattern printed to stdout when installation finishes successfully.
  final String completionSentinel;

  const OptionalPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.installCommand,
    required this.uninstallCommand,
    required this.checkPath,
    required this.estimatedSize,
    required this.completionSentinel,
  });

  static const goPackage = OptionalPackage(
    id: 'go',
    name: 'Go (Golang)',
    description: 'Go programming language compiler and tools',
    icon: Icons.integration_instructions,
    color: Colors.cyan,
    installCommand: 'set -e; '
        'echo ">>> Installing Go via apt..."; '
        'apt-get update -qq && apt-get install -y golang; '
        'go version; '
        'echo ">>> GO_INSTALL_COMPLETE"',
    uninstallCommand: 'set -e; '
        'echo ">>> Removing Go..."; '
        'apt-get remove -y golang golang-go && apt-get autoremove -y; '
        'echo ">>> GO_UNINSTALL_COMPLETE"',
    checkPath: 'usr/bin/go',
    estimatedSize: '~150 MB',
    completionSentinel: 'GO_INSTALL_COMPLETE',
  );

  static const brewPackage = OptionalPackage(
    id: 'brew',
    name: 'Homebrew',
    description: 'The missing package manager for Linux',
    icon: Icons.science,
    color: Colors.amber,
    installCommand: 'set -e; '
        'echo ">>> Installing Homebrew (this may take a while)..."; '
        'touch /.dockerenv; '
        'apt-get update -qq && apt-get install -y -qq '
        'build-essential procps curl file git; '
        'NONINTERACTIVE=1 /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; '
        r"grep -q 'linuxbrew' /root/.bashrc 2>/dev/null || {"
        ' echo \'eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\' >> /root/.bashrc; '
        '}; '
        'eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; '
        'brew --version; '
        'echo ">>> BREW_INSTALL_COMPLETE"',
    uninstallCommand: 'set -e; '
        'echo ">>> Removing Homebrew..."; '
        'touch /.dockerenv; '
        'NONINTERACTIVE=1 /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" || true; '
        'rm -rf /home/linuxbrew/.linuxbrew; '
        r"sed -i '/linuxbrew/d' /root/.bashrc; "
        'echo ">>> BREW_UNINSTALL_COMPLETE"',
    checkPath: 'home/linuxbrew/.linuxbrew/bin/brew',
    estimatedSize: '~500 MB',
    completionSentinel: 'BREW_INSTALL_COMPLETE',
  );

  static const sshPackage = OptionalPackage(
    id: 'ssh',
    name: 'OpenSSH',
    description: 'SSH client and server for secure remote access',
    icon: Icons.vpn_key,
    color: Colors.teal,
    installCommand: 'set -e; '
        'echo ">>> Installing OpenSSH..."; '
        'apt-get update -qq && apt-get install -y openssh-client openssh-server; '
        'ssh -V; '
        'echo ">>> SSH_INSTALL_COMPLETE"',
    uninstallCommand: 'set -e; '
        'echo ">>> Removing OpenSSH..."; '
        'apt-get remove -y openssh-client openssh-server && apt-get autoremove -y; '
        'echo ">>> SSH_UNINSTALL_COMPLETE"',
    checkPath: 'usr/bin/ssh',
    estimatedSize: '~10 MB',
    completionSentinel: 'SSH_INSTALL_COMPLETE',
  );

  static const cpolarPackage = OptionalPackage(
    id: 'cpolar',
    name: 'cpolar',
    description: 'Tunnel local services to the public internet with cpolar',
    icon: Icons.hub,
    color: Colors.orange,
    installCommand: r'''
set -eu

arch="$(uname -m 2>/dev/null || true)"
case "$arch" in
  aarch64|arm64)
    download_url='https://www.cpolar.com/static/downloads/cpolar-stable-linux-arm64.zip'
    ;;
  armv7l|armv8l|armhf|arm)
    download_url='https://www.cpolar.com/static/downloads/cpolar-stable-linux-arm.zip'
    ;;
  x86_64|amd64)
    download_url='https://www.cpolar.com/static/downloads/cpolar-stable-linux-amd64.zip'
    ;;
  i386|i686|x86)
    download_url='https://www.cpolar.com/static/downloads/cpolar-stable-linux-386.zip'
    ;;
  *)
    echo "Unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

cache_dir='/tmp/cpolar-install'
extract_dir="$cache_dir/extract"
config_dir='/usr/local/etc/cpolar'
log_dir='/var/log/cpolar'
log_file="$log_dir/access.log"
archive_path="$cache_dir/cpolar.zip"
binary_path='/usr/local/bin/cpolar'

echo ">>> Installing cpolar..."
mkdir -p "$cache_dir" "$extract_dir" "$config_dir" "$log_dir" /usr/local/bin /usr/bin
: > "$log_file"

emit_failure_tail() {
  status="$1"
  {
    echo "cpolar installation failed (exit code $status)."
    if [ -f "$log_file" ]; then
      echo '---- cpolar install log tail ----'
      tail -n 80 "$log_file" || true
      echo '---- end log ----'
    fi
  } >&2
}

trap 'status=$?; trap - EXIT; if [ "$status" -ne 0 ]; then emit_failure_tail "$status"; fi; exit "$status"' EXIT

log() {
  printf '[%s] %s\n' "$(date -Iseconds 2>/dev/null || date)" "$1" >> "$log_file"
}

repair_apt_state() {
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /var/lib/dpkg/updates /var/lib/dpkg/triggers
  dpkg --configure -a >> "$log_file" 2>&1 || true
  apt-get install -f -y >> "$log_file" 2>&1 || true
  dpkg --configure -a >> "$log_file" 2>&1 || true
}

log "Starting cpolar install"
log "Step 1/5: repairing apt and dpkg state"
repair_apt_state

log "Step 2/5: ensuring curl and unzip are available"
if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v update-ca-certificates >/dev/null 2>&1; then
  apt-get update -y >> "$log_file" 2>&1
  apt-get install -y --no-install-recommends ca-certificates curl unzip >> "$log_file" 2>&1
fi

log "Step 3/5: downloading cpolar package"
rm -f "$archive_path"
curl --fail --location --retry 3 --connect-timeout 20 "$download_url" -o "$archive_path" >> "$log_file" 2>&1

log "Step 4/5: extracting and installing cpolar binary"
rm -rf "$extract_dir"
mkdir -p "$extract_dir"
unzip -oq "$archive_path" -d "$extract_dir" >> "$log_file" 2>&1
if [ ! -f "$extract_dir/cpolar" ]; then
  echo "cpolar archive extracted, but binary was not found." >&2
  exit 1
fi
install -m 755 "$extract_dir/cpolar" "$binary_path" >> "$log_file" 2>&1
ln -sf "$binary_path" /usr/bin/cpolar >> "$log_file" 2>&1 || true

log "Step 5/5: verifying installed version"
touch "$log_file"
version_line="$("$binary_path" version 2>>"$log_file" | head -n 1 || true)"
if [ -n "$version_line" ]; then
  printf '%s\n' "$version_line"
fi

echo ">>> cpolar installed. Start it from Optional Packages, then open the local Web UI to sign in."
echo ">>> CPOLAR_INSTALL_COMPLETE"
''',
    uninstallCommand: r'''
set -eu

echo ">>> Removing cpolar..."

current_pid="$$"
parent_pid="$PPID"

for proc_dir in /proc/[0-9]*; do
  pid="${proc_dir##*/}"
  [ "$pid" = "$current_pid" ] && continue
  [ "$pid" = "$parent_pid" ] && continue
  [ -r "$proc_dir/comm" ] || continue
  if [ "$(cat "$proc_dir/comm" 2>/dev/null || true)" = "cpolar" ]; then
    kill "$pid" 2>/dev/null || true
  fi
done

sleep 1

for proc_dir in /proc/[0-9]*; do
  pid="${proc_dir##*/}"
  [ "$pid" = "$current_pid" ] && continue
  [ "$pid" = "$parent_pid" ] && continue
  [ -r "$proc_dir/comm" ] || continue
  if [ "$(cat "$proc_dir/comm" 2>/dev/null || true)" = "cpolar" ]; then
    kill -9 "$pid" 2>/dev/null || true
  fi
done

rm -f /usr/local/bin/cpolar
rm -f /usr/bin/cpolar
rm -f /etc/systemd/system/cpolar.service
rm -f /etc/systemd/system/cpolar@.service
rm -rf /etc/systemd/system/cpolar.service.d
rm -rf /etc/systemd/system/cpolar@.service.d
rm -rf /usr/local/etc/cpolar
rm -rf /var/log/cpolar
rm -rf /tmp/cpolar-install

echo ">>> CPOLAR_UNINSTALL_COMPLETE"
''',
    checkPath: 'usr/local/bin/cpolar',
    estimatedSize: '~20 MB',
    completionSentinel: 'CPOLAR_INSTALL_COMPLETE',
  );

  /// All available optional packages.
  static const all = [goPackage, brewPackage, sshPackage, cpolarPackage];

  /// Sentinel for uninstall completion (derived from install sentinel).
  String get uninstallSentinel =>
      completionSentinel.replaceFirst('INSTALL', 'UNINSTALL');
}
