class AppConstants {
  static const String appName = 'OpenClaw';
  static const String version = '1.9.8';
  static const String packageName = 'com.junwan666.openclawzh';

  /// Matches ANSI escape sequences (e.g. color codes in terminal output).
  static final ansiEscape = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');

  static const String authorName = 'JunWan';
  static const String authorEmail = 'susuya0712@gmail.com';
  static const String githubUrl =
      'https://github.com/JunWan666/openclaw-termux-zh';
  static const String license = 'MIT';

  static const String githubApiLatestRelease =
      'https://api.github.com/repos/JunWan666/openclaw-termux-zh/releases/latest';

  // NextGenX
  static const String orgName = 'NextGenX';
  static const String orgEmail = 'susuya0712@gmail.com';
  static const String instagramUrl =
      'https://www.instagram.com/nexgenxplorer_nxg';
  static const String youtubeUrl =
      'https://youtube.com/@nexgenxplorer?si=UG-wBC8UIyeT4bbw';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/dev?id=8262374975871504599';

  static const String gatewayHost = '127.0.0.1';
  static const int gatewayPort = 18789;
  static const String gatewayUrl = 'http://$gatewayHost:$gatewayPort';

  static const String ubuntuRootfsUrl =
      'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-';
  static const String ubuntuCodename = 'noble';
  static const String bundledBootstrapAssetDir = 'assets/bootstrap';
  static const String rootfsArm64 = '${ubuntuRootfsUrl}arm64.tar.gz';
  static const String rootfsArmhf = '${ubuntuRootfsUrl}armhf.tar.gz';
  static const String rootfsAmd64 = '${ubuntuRootfsUrl}amd64.tar.gz';

  // Node.js binary tarball 閳?downloaded directly by Flutter, extracted by Java.
  // Bypasses curl/gpg/NodeSource which fail inside proot.
  static const String nodeVersion = '24.14.1';
  static const String openClawEstimatedSize = '~95 MB';
  static const String nodeBaseUrl =
      'https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-linux-';

  static String getNodeTarballUrl(String arch) {
    return getNodeTarballUrlForVersion(arch, nodeVersion);
  }

  static String getNodeTarballUrlForVersion(String arch, String version) {
    final nodeBaseUrl =
        'https://nodejs.org/dist/v$version/node-v$version-linux-';

    switch (arch) {
      case 'aarch64':
        return '${nodeBaseUrl}arm64.tar.xz';
      case 'arm':
        return '${nodeBaseUrl}armv7l.tar.xz';
      case 'x86_64':
        return '${nodeBaseUrl}x64.tar.xz';
      default:
        return '${nodeBaseUrl}arm64.tar.xz';
    }
  }

  static String bundledBootstrapAssetPathForUrl(String url) {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return '$bundledBootstrapAssetDir/$fileName';
  }

  static bool isUbuntuPortsArch(String arch) {
    switch (arch) {
      case 'aarch64':
      case 'arm':
        return true;
      default:
        return false;
    }
  }

  static List<String> ubuntuMirrorCandidates(String arch) {
    final isPorts = isUbuntuPortsArch(arch);
    final paths = isPorts
        ? <String>[
            'http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports',
            'http://mirrors.ustc.edu.cn/ubuntu-ports',
            'http://mirrors.aliyun.com/ubuntu-ports',
            'http://ports.ubuntu.com/ubuntu-ports',
          ]
        : <String>[
            'http://mirrors.tuna.tsinghua.edu.cn/ubuntu',
            'http://mirrors.ustc.edu.cn/ubuntu',
            'http://mirrors.aliyun.com/ubuntu',
            'http://archive.ubuntu.com/ubuntu',
          ];
    return paths;
  }

  static String buildUbuntuSourcesList(String baseUrl) {
    final suites = <String>[
      ubuntuCodename,
      '$ubuntuCodename-updates',
      '$ubuntuCodename-backports',
      '$ubuntuCodename-security',
    ];
    final buffer = StringBuffer();
    for (final suite in suites) {
      buffer.writeln(
        'deb $baseUrl $suite main restricted universe multiverse',
      );
    }
    return buffer.toString();
  }

  static const int healthCheckIntervalMs = 5000;
  static const int maxAutoRestarts = 5;

  // Node constants
  static const int wsReconnectBaseMs = 350;
  static const double wsReconnectMultiplier = 1.7;
  static const int wsReconnectCapMs = 8000;
  static const String nodeRole = 'node';
  static const int pairingTimeoutMs = 300000;

  static const String channelName = 'com.junwan666.openclawzh/native';
  static const String eventChannelName =
      'com.junwan666.openclawzh/gateway_logs';
  static const String setupLogEventChannelName =
      'com.junwan666.openclawzh/setup_logs';

  static String getRootfsUrl(String arch) {
    switch (arch) {
      case 'aarch64':
        return rootfsArm64;
      case 'arm':
        return rootfsArmhf;
      case 'x86_64':
        return rootfsAmd64;
      default:
        return rootfsArm64;
    }
  }
}


