import '../constants.dart';
import '../l10n/app_localizations.dart';

class InstallStatusMessageFormatter {
  static String localize(AppLocalizations l10n, String? message) {
    if (message == null || message.isEmpty) {
      return '';
    }

    final rootfsDownload =
        RegExp(r'^Downloading: ([0-9.]+) MB / ([0-9.]+) MB(?: \| (.+))?$')
            .firstMatch(message);
    if (rootfsDownload != null) {
      return _appendDetails(
        l10n.t('setupWizardStatusDownloadingProgress', {
          'current': rootfsDownload.group(1),
          'total': rootfsDownload.group(2),
        }),
        localizeDetail(l10n, rootfsDownload.group(3)),
      );
    }

    final nodeDownload = RegExp(
      r'^Downloading Node\.js: ([0-9.]+) MB / ([0-9.]+) MB(?: \| (.+))?$',
    ).firstMatch(message);
    if (nodeDownload != null) {
      return _appendDetails(
        l10n.t('setupWizardStatusDownloadingNodeProgress', {
          'current': nodeDownload.group(1),
          'total': nodeDownload.group(2),
        }),
        localizeDetail(l10n, nodeDownload.group(3)),
      );
    }

    final openClawDownload = RegExp(
      r'^Downloading OpenClaw: ([0-9.]+) MB / ([0-9.]+) MB(?: \| (.+))?$',
    ).firstMatch(message);
    if (openClawDownload != null) {
      final current = openClawDownload.group(1);
      final total = openClawDownload.group(2);
      final details = openClawDownload.group(3);
      return _appendDetails(
        '${l10n.t('setupWizardStatusInstallingOpenClaw')} $current MB / $total MB',
        localizeDetail(l10n, details),
      );
    }

    final nodeVersionMatch = RegExp(
      r'^(?:Downloading|Using bundled) Node\.js (.+?)(?:\.{3}| package\.\.\.)$',
    ).firstMatch(message);
    if (nodeVersionMatch != null) {
      return l10n.t('setupWizardStatusDownloadingNode', {
        'version': nodeVersionMatch.group(1),
      });
    }

    final bundledNodeFallback = RegExp(
      r'^Bundled Node\.js (.+) failed, downloading online\.\.\.$',
    ).firstMatch(message);
    if (bundledNodeFallback != null) {
      return l10n.t('setupWizardStatusDownloadingNode', {
        'version': bundledNodeFallback.group(1) ?? AppConstants.nodeVersion,
      });
    }

    switch (message) {
      case 'Setup complete':
        return l10n.t('setupWizardStatusSetupComplete');
      case 'Setup required':
        return l10n.t('setupWizardStatusSetupRequired');
      case 'Setting up directories...':
        return l10n.t('setupWizardStatusSettingUpDirs');
      case 'Downloading Ubuntu rootfs...':
      case 'Using bundled Ubuntu rootfs package...':
      case 'Bundled rootfs failed, downloading online...':
        return l10n.t('setupWizardStatusDownloadingUbuntuRootfs');
      case 'Extracting rootfs (this takes a while)...':
        return l10n.t('setupWizardStatusExtractingRootfs');
      case 'Rootfs extracted':
        return l10n.t('setupWizardStatusRootfsExtracted');
      case 'Fixing rootfs permissions...':
        return l10n.t('setupWizardStatusFixingPermissions');
      case 'Updating package lists...':
        return l10n.t('setupWizardStatusUpdatingPackageLists');
      case 'Installing base packages...':
        return l10n.t('setupWizardStatusInstallingBasePackages');
      case 'Preparing OpenClaw package...':
        return _phrase(
          l10n,
          en: 'Preparing OpenClaw package...',
          zhHans: '正在准备 OpenClaw 安装包...',
          zhHant: '正在準備 OpenClaw 安裝包...',
          ja: 'OpenClaw パッケージを準備中...',
        );
      case 'Downloading OpenClaw package...':
        return _phrase(
          l10n,
          en: 'Downloading OpenClaw package...',
          zhHans: '正在下载 OpenClaw 安装包...',
          zhHant: '正在下載 OpenClaw 安裝包...',
          ja: 'OpenClaw パッケージをダウンロード中...',
        );
      case 'Using cached OpenClaw package...':
        return _phrase(
          l10n,
          en: 'Using cached OpenClaw package...',
          zhHans: '正在使用本地 OpenClaw 安装包缓存...',
          zhHant: '正在使用本地 OpenClaw 安裝包快取...',
          ja: 'ローカルの OpenClaw パッケージキャッシュを使用中...',
        );
      case 'Extracting Node.js...':
        return l10n.t('setupWizardStatusExtractingNode');
      case 'Verifying Node.js...':
        return l10n.t('setupWizardStatusVerifyingNode');
      case 'Node.js installed':
        return l10n.t('setupWizardStatusNodeInstalled');
      case 'Checking Node.js requirement...':
      case 'Node.js requirement satisfied':
      case 'Installing OpenClaw dependencies...':
      case 'Installing OpenClaw (this may take a few minutes)...':
        return l10n.t('setupWizardStatusInstallingOpenClaw');
      case 'Creating bin wrappers...':
        return l10n.t('setupWizardStatusCreatingBinWrappers');
      case 'Verifying OpenClaw...':
        return l10n.t('setupWizardStatusVerifyingOpenClaw');
      case 'OpenClaw installed':
        return l10n.t('setupWizardStatusOpenClawInstalled');
      case 'Bionic Bypass configured':
        return l10n.t('setupWizardStatusBypassConfigured');
      case 'Setup complete! Ready to start the gateway.':
        return l10n.t('setupWizardStatusReady');
      case 'Preparing installation...':
        return l10n.t('gatewayApplyingVersion');
      case 'Stopping gateway...':
        return l10n.t('gatewayStopping');
      case 'Restarting gateway...':
        return l10n.t('messagePlatformDetailGatewayRestarting');
      case 'Refreshing installed version...':
        return '${l10n.t('logsRefresh')}...';
      default:
        return message;
    }
  }

  static String? localizeDetail(AppLocalizations l10n, String? detail) {
    if (detail == null || detail.trim().isEmpty) {
      return null;
    }

    final trimmed = detail.trim();
    switch (trimmed) {
      case 'Using packaged Ubuntu rootfs archive.':
        return _phrase(
          l10n,
          en: 'Using the packaged Ubuntu rootfs archive.',
          zhHans: '优先使用 APK 内置的 Ubuntu rootfs 压缩包。',
          zhHant: '優先使用 APK 內建的 Ubuntu rootfs 壓縮包。',
          ja: 'APK に同梱された Ubuntu rootfs アーカイブを優先して使用します。',
        );
      case 'Using packaged Node.js archive.':
        return _phrase(
          l10n,
          en: 'Using the packaged Node.js archive.',
          zhHans: '优先使用 APK 内置的 Node.js 压缩包。',
          zhHant: '優先使用 APK 內建的 Node.js 壓縮包。',
          ja: 'APK に同梱された Node.js アーカイブを優先して使用します。',
        );
      case 'Using local OpenClaw package cache.':
        return _phrase(
          l10n,
          en: 'Using the local OpenClaw package cache.',
          zhHans: '正在使用本地 OpenClaw 安装包缓存。',
          zhHant: '正在使用本地 OpenClaw 安裝包快取。',
          ja: 'ローカルの OpenClaw パッケージキャッシュを使用しています。',
        );
      case 'Preparing Node.js files...':
        return _phrase(
          l10n,
          en: 'Preparing Node.js files...',
          zhHans: '正在整理 Node.js 文件...',
          zhHant: '正在整理 Node.js 檔案...',
          ja: 'Node.js ファイルを準備中...',
        );
      case 'Running apt-get update...':
        return _phrase(
          l10n,
          en: 'Running apt-get update...',
          zhHans: '正在执行 apt-get update...',
          zhHant: '正在執行 apt-get update...',
          ja: 'apt-get update を実行中...',
        );
      case 'Running apt-get install for base packages...':
        return _phrase(
          l10n,
          en: 'Running apt-get install for base packages...',
          zhHans: '正在执行基础软件包的 apt-get install...',
          zhHant: '正在執行基礎軟體包的 apt-get install...',
          ja: '基本パッケージ向けの apt-get install を実行中...',
        );
      case 'Running npm install for OpenClaw...':
        return _phrase(
          l10n,
          en: 'Running npm install for OpenClaw...',
          zhHans: '下载完成，正在执行 OpenClaw 的 npm 安装...',
          zhHant: '下載完成，正在執行 OpenClaw 的 npm 安裝...',
          ja: 'ダウンロード完了。OpenClaw の npm インストールを実行中...',
        );
      case 'Reading package lists...':
        return _phrase(
          l10n,
          en: 'Reading package lists...',
          zhHans: '正在读取软件包列表...',
          zhHant: '正在讀取軟體包列表...',
          ja: 'パッケージ一覧を読み込み中...',
        );
      case 'Building dependency tree...':
        return _phrase(
          l10n,
          en: 'Building dependency tree...',
          zhHans: '正在构建依赖关系树...',
          zhHant: '正在建立依賴關係樹...',
          ja: '依存関係ツリーを構築中...',
        );
      case 'Reading state information...':
        return _phrase(
          l10n,
          en: 'Reading state information...',
          zhHans: '正在读取状态信息...',
          zhHant: '正在讀取狀態資訊...',
          ja: '状態情報を読み込み中...',
        );
      case 'permissions_fixed':
        return _phrase(
          l10n,
          en: 'Rootfs permissions repaired.',
          zhHans: 'rootfs 权限已修复。',
          zhHant: 'rootfs 權限已修復。',
          ja: 'rootfs の権限修復が完了しました。',
        );
    }

    final settingUpPackage = RegExp(r'^Setting up (.+)$').firstMatch(trimmed);
    if (settingUpPackage != null) {
      return _phrase(
        l10n,
        en: 'Setting up ${settingUpPackage.group(1)}',
        zhHans: '正在配置 ${settingUpPackage.group(1)}',
        zhHant: '正在設定 ${settingUpPackage.group(1)}',
        ja: '${settingUpPackage.group(1)} を設定中',
      );
    }

    final unpackingPackage = RegExp(r'^Unpacking (.+)$').firstMatch(trimmed);
    if (unpackingPackage != null) {
      return _phrase(
        l10n,
        en: 'Unpacking ${unpackingPackage.group(1)}',
        zhHans: '正在解包 ${unpackingPackage.group(1)}',
        zhHant: '正在解壓 ${unpackingPackage.group(1)}',
        ja: '${unpackingPackage.group(1)} を展開中',
      );
    }

    final processingTriggers =
        RegExp(r'^Processing triggers for (.+)$').firstMatch(trimmed);
    if (processingTriggers != null) {
      return _phrase(
        l10n,
        en: 'Processing triggers for ${processingTriggers.group(1)}',
        zhHans: '正在处理 ${processingTriggers.group(1)} 的触发器',
        zhHant: '正在處理 ${processingTriggers.group(1)} 的觸發器',
        ja: '${processingTriggers.group(1)} のトリガーを処理中',
      );
    }

    final downloadProgress =
        RegExp(r'^([0-9.]+) MB / ([0-9.]+) MB \| (.+)$').firstMatch(trimmed);
    if (downloadProgress != null) {
      final current = downloadProgress.group(1);
      final total = downloadProgress.group(2);
      final suffix = _localizeTransferSuffix(l10n, downloadProgress.group(3) ?? '');
      return '$current MB / $total MB | $suffix';
    }

    final withEta = RegExp(r'^(.*)\| ETA (.+)$').firstMatch(trimmed);
    if (withEta != null) {
      final prefix = withEta.group(1)?.trim();
      final eta = withEta.group(2)?.trim();
      if (prefix != null && prefix.isNotEmpty && eta != null && eta.isNotEmpty) {
        return '$prefix | ${_estimatedLabel(l10n)} $eta';
      }
    }

    return trimmed;
  }

  static String _appendDetails(String base, String? details) {
    if (details == null || details.trim().isEmpty) {
      return base;
    }
    return '$base | ${details.trim()}';
  }

  static String _localizeTransferSuffix(AppLocalizations l10n, String details) {
    final withEta = RegExp(r'^(.*)\| ETA (.+)$').firstMatch(details.trim());
    if (withEta == null) {
      return details.trim();
    }

    final prefix = withEta.group(1)?.trim() ?? '';
    final eta = withEta.group(2)?.trim() ?? '';
    if (prefix.isEmpty) {
      return '${_estimatedLabel(l10n)} $eta';
    }
    return '$prefix | ${_estimatedLabel(l10n)} $eta';
  }

  static String _estimatedLabel(AppLocalizations l10n) {
    if (_isZhHant(l10n)) {
      return '預計';
    }
    switch (l10n.locale.languageCode) {
      case 'zh':
        return '预计';
      case 'ja':
        return '残り';
      default:
        return 'ETA';
    }
  }

  static bool _isZhHant(AppLocalizations l10n) {
    final locale = l10n.locale;
    if (locale.languageCode != 'zh') {
      return false;
    }
    final script = locale.scriptCode?.toLowerCase();
    final country = locale.countryCode?.toUpperCase();
    return script == 'hant' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO';
  }

  static String _phrase(
    AppLocalizations l10n, {
    required String en,
    required String zhHans,
    required String zhHant,
    required String ja,
  }) {
    if (_isZhHant(l10n)) {
      return zhHant;
    }

    switch (l10n.locale.languageCode) {
      case 'zh':
        return zhHans;
      case 'ja':
        return ja;
      default:
        return en;
    }
  }
}
