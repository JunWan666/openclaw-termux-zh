import 'dart:io';
import 'package:flutter/services.dart';
import '../constants.dart';
import 'native_bridge.dart';
import 'proot_dns_service.dart';

enum TerminalProotMode {
  fast,
  compatibility,
}

/// Provides proot shell configuration for interactive terminal screens.
class TerminalService {
  static const _channel = MethodChannel(AppConstants.channelName);

  static const _fakeKernelRelease = '6.17.0-PRoot-Distro';
  static const _fakeKernelVersion =
      '#1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000';

  /// Get paths and host-side proot environment variables.
  /// Host env should ONLY contain proot-specific vars; guest env is
  /// set via `env -i` inside the command, matching proot-distro.
  ///
  /// Also ensures directories and resolv.conf exist; Android may clear
  /// them during an app update (#40). Every screen that uses proot calls
  /// this method, so it's the single place to guarantee the files exist.
  static Future<Map<String, String>> getProotShellConfig() async {
    await ProotDnsService.ensureReady();

    final filesDir = await _channel.invokeMethod<String>('getFilesDir') ?? '';
    final nativeLibDir =
        await _channel.invokeMethod<String>('getNativeLibDir') ?? '';
    var arch = 'aarch64';
    try {
      arch = await NativeBridge.getArch();
    } catch (_) {}

    final rootfsDir = '$filesDir/rootfs/ubuntu';
    final tmpDir = '$filesDir/tmp';
    final configDir = '$filesDir/config';
    final homeDir = '$filesDir/home';
    final nativeRuntimeDir = '$filesDir/native';
    final prootPath = await NativeBridge.getProotPath();
    final libDir = '$filesDir/lib';
    final prootLoaderPath = _preferExistingPath([
      '$nativeLibDir/libprootloader.so',
      '$nativeRuntimeDir/libprootloader.so',
    ]);
    final prootLoader32Path = _preferExistingPath([
      '$nativeLibDir/libprootloader32.so',
      '$nativeRuntimeDir/libprootloader32.so',
    ]);
    final ldLibraryPath = <String>{libDir, nativeLibDir, nativeRuntimeDir}
        .where((path) => path.isNotEmpty)
        .join(':');

    final storageGranted = await NativeBridge.hasStoragePermission();

    return {
      'executable': prootPath,
      'rootfsDir': rootfsDir,
      'tmpDir': tmpDir,
      'configDir': configDir,
      'homeDir': homeDir,
      'libDir': libDir,
      'nativeLibDir': nativeLibDir,
      'storageGranted': storageGranted.toString(),
      'arch': arch,
      // Host-side proot env; ONLY proot-specific vars.
      // Do NOT set PROOT_NO_SECCOMP (proot-distro doesn't set it).
      // Do NOT set HOME/TERM/LANG here (those go in guest env via env -i).
      'PROOT_TMP_DIR': tmpDir,
      'PROOT_LOADER': prootLoaderPath,
      'PROOT_LOADER_32': prootLoader32Path,
      'LD_LIBRARY_PATH': ldLibraryPath,
    };
  }

  static String _preferExistingPath(List<String> candidates) {
    for (final path in candidates) {
      if (path.isNotEmpty && File(path).existsSync()) {
        return path;
      }
    }
    return candidates.firstWhere((path) => path.isNotEmpty, orElse: () => '');
  }

  /// Build proot arguments for interactive terminals.
  /// Fast mode follows ProcessManager.kt's install mode root identity and
  /// avoids SysV IPC overhead. Compatibility mode keeps the older
  /// proot-distro command_login-style flags for fragile workloads.
  static List<String> buildProotArgs(Map<String, String> config,
      {int columns = 80,
      int rows = 24,
      TerminalProotMode mode = TerminalProotMode.fast}) {
    final procFakes = '${config['configDir']}/proc_fakes';
    final sysFakes = '${config['configDir']}/sys_fakes';
    final rootfsDir = config['rootfsDir']!;

    final identityFlags = mode == TerminalProotMode.compatibility
        ? [
            '--change-id=0:0',
            '--sysvipc',
            '--kernel-release=${_fullKernelRelease(config['arch'])}',
          ]
        : [
            '--root-id',
            '--kernel-release=$_fakeKernelRelease',
          ];

    final args = <String>[
      ...identityFlags,
      '--link2symlink',
      '-L',
      '--kill-on-exit',
      '--rootfs=$rootfsDir',
      '--cwd=/root',
      // Core device binds (matching proot-distro)
      '--bind=/dev',
      '--bind=/dev/urandom:/dev/random',
      '--bind=/proc',
      '--bind=/proc/self/fd:/dev/fd',
      '--bind=/proc/self/fd/0:/dev/stdin',
      '--bind=/proc/self/fd/1:/dev/stdout',
      '--bind=/proc/self/fd/2:/dev/stderr',
      '--bind=/sys',
      // Fake /proc entries
      '--bind=$procFakes/loadavg:/proc/loadavg',
      '--bind=$procFakes/stat:/proc/stat',
      '--bind=$procFakes/uptime:/proc/uptime',
      '--bind=$procFakes/version:/proc/version',
      '--bind=$procFakes/vmstat:/proc/vmstat',
      '--bind=$procFakes/cap_last_cap:/proc/sys/kernel/cap_last_cap',
      '--bind=$procFakes/max_user_watches:/proc/sys/fs/inotify/max_user_watches',
      '--bind=$procFakes/fips_enabled:/proc/sys/crypto/fips_enabled',
      // Shared memory (proot-distro binds rootfs/tmp to /dev/shm)
      '--bind=$rootfsDir/tmp:/dev/shm',
      // SELinux override
      '--bind=$sysFakes/empty:/sys/fs/selinux',
      // App-specific binds
      '--bind=${config['configDir']}/resolv.conf:/etc/resolv.conf',
      '--bind=${config['homeDir']}:/root/home',
    ];

    // Bind-mount shared storage if permission is granted (Termux-style).
    if (config['storageGranted'] == 'true') {
      args.addAll([
        '--bind=/storage:/storage',
        '--bind=/storage/emulated/0:/sdcard',
      ]);
    }

    args.addAll([
      // Clean guest environment via env -i (matching proot-distro).
      // This prevents Android JVM vars (LD_PRELOAD, CLASSPATH, DEX2OAT,
      // ANDROID_ROOT, etc.) from leaking into the proot guest.
      '/usr/bin/env',
      '-i',
      'HOME=/root',
      'USER=root',
      'LANG=C.UTF-8',
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      'TERM=xterm-256color',
      'TMPDIR=/tmp',
      'COLUMNS=$columns',
      'LINES=$rows',
      'NODE_OPTIONS=--require /root/.openclaw/bionic-bypass.js',
      'NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt',
      'UV_USE_IO_URING=0',
      '/bin/bash',
      '-l',
    ]);

    return args;
  }

  static String _fullKernelRelease(String? arch) {
    final machine = switch (arch) {
      'arm' => 'armv7l',
      'aarch64' || 'x86_64' || 'x86' => arch!,
      _ => 'aarch64',
    };
    return '\\Linux\\localhost\\$_fakeKernelRelease'
        '\\$_fakeKernelVersion\\$machine\\localdomain\\-1\\';
  }

  /// Host-side environment map for Pty.start().
  /// Only proot-specific vars; no guest vars (those are in env -i).
  static Map<String, String> buildHostEnv(Map<String, String> config) {
    return {
      'PROOT_TMP_DIR': config['PROOT_TMP_DIR']!,
      'PROOT_LOADER': config['PROOT_LOADER']!,
      'PROOT_LOADER_32': config['PROOT_LOADER_32']!,
      'LD_LIBRARY_PATH': config['LD_LIBRARY_PATH']!,
    };
  }
}
