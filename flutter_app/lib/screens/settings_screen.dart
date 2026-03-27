import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../providers/node_provider.dart';
import '../services/native_bridge.dart';
import '../services/preferences_service.dart';
import '../services/snapshot_service.dart';
import '../services/update_service.dart';
import 'node_screen.dart';
import 'setup_wizard_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _showOrgSection = false;

  final _prefs = PreferencesService();
  bool _autoStart = false;
  bool _nodeEnabled = false;
  bool _batteryOptimized = true;
  String _arch = '';
  String _prootPath = '';
  Map<String, dynamic> _status = {};
  bool _loading = true;
  bool _goInstalled = false;
  bool _brewInstalled = false;
  bool _sshInstalled = false;
  bool _storageGranted = false;
  bool _persistentGatewayLogs = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _prefs.init();
    _autoStart = _prefs.autoStartGateway;
    _nodeEnabled = _prefs.nodeEnabled;

    try {
      final arch = await NativeBridge.getArch();
      final prootPath = await NativeBridge.getProotPath();
      final status = await NativeBridge.getBootstrapStatus();
      final batteryOptimized = await NativeBridge.isBatteryOptimized();
      final persistentGatewayLogs =
          await NativeBridge.isGatewayLogPersistenceEnabled();
      final storageGranted = await NativeBridge.hasStoragePermission();

      // Check optional package statuses
      final filesDir = await NativeBridge.getFilesDir();
      final rootfs = '$filesDir/rootfs/ubuntu';
      final goInstalled = File('$rootfs/usr/bin/go').existsSync();
      final brewInstalled =
          File('$rootfs/home/linuxbrew/.linuxbrew/bin/brew').existsSync();
      final sshInstalled = File('$rootfs/usr/bin/ssh').existsSync();

      setState(() {
        _batteryOptimized = batteryOptimized;
        _persistentGatewayLogs = persistentGatewayLogs;
        _storageGranted = storageGranted;
        _arch = arch;
        _prootPath = prootPath;
        _status = status;
        _goInstalled = goInstalled;
        _brewInstalled = brewInstalled;
        _sshInstalled = sshInstalled;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final localeProvider = context.watch<LocaleProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('settingsTitle'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader(theme, l10n.t('settingsGeneral')),
                SwitchListTile(
                  title: Text(l10n.t('settingsAutoStart')),
                  subtitle: Text(l10n.t('settingsAutoStartSubtitle')),
                  value: _autoStart,
                  onChanged: (value) {
                    setState(() => _autoStart = value);
                    _prefs.autoStartGateway = value;
                  },
                ),
                SwitchListTile(
                  title: Text(l10n.t('settingsPersistentGatewayLogs')),
                  subtitle:
                      Text(l10n.t('settingsPersistentGatewayLogsSubtitle')),
                  value: _persistentGatewayLogs,
                  onChanged: (value) async {
                    await NativeBridge.setGatewayLogPersistenceEnabled(value);
                    setState(() => _persistentGatewayLogs = value);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: DropdownButtonFormField<String>(
                    initialValue: localeProvider.localeCode,
                    decoration: InputDecoration(labelText: l10n.t('language')),
                    items: [
                      DropdownMenuItem(
                        value: 'system',
                        child: Text(l10n.t('languageSystem')),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(l10n.t('languageEnglish')),
                      ),
                      DropdownMenuItem(
                        value: 'zh',
                        child: Text(l10n.t('languageChinese')),
                      ),
                      DropdownMenuItem(
                        value: 'zh-Hant',
                        child: Text(l10n.t('languageTraditionalChinese')),
                      ),
                      DropdownMenuItem(
                        value: 'ja',
                        child: Text(l10n.t('languageJapanese')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        localeProvider.setLocaleCode(value);
                      }
                    },
                  ),
                ),
                ListTile(
                  title: Text(l10n.t('settingsBatteryOptimization')),
                  subtitle: Text(_batteryOptimized
                      ? l10n.t('settingsBatteryOptimized')
                      : l10n.t('settingsBatteryUnrestricted')),
                  leading: const Icon(Icons.battery_alert),
                  trailing: _batteryOptimized
                      ? const Icon(Icons.warning, color: AppColors.statusAmber)
                      : const Icon(Icons.check_circle,
                          color: AppColors.statusGreen),
                  onTap: () async {
                    await NativeBridge.requestBatteryOptimization();
                    // Refresh status after returning from settings
                    final optimized = await NativeBridge.isBatteryOptimized();
                    setState(() => _batteryOptimized = optimized);
                  },
                ),
                ListTile(
                  title: Text(l10n.t('settingsStorage')),
                  subtitle: Text(_storageGranted
                      ? l10n.t('settingsStorageGranted')
                      : l10n.t('settingsStorageMissing')),
                  leading: const Icon(Icons.sd_storage),
                  trailing: _storageGranted
                      ? const Icon(Icons.check_circle,
                          color: AppColors.statusGreen)
                      : const Icon(Icons.warning, color: AppColors.statusAmber),
                  onTap: () async {
                    final shouldRequest = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(l10n.t('settingsStorageDialogTitle')),
                        content: Text(l10n.t('settingsStorageDialogBody')),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: Text(l10n.t('commonCancel')),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: Text(l10n.t('settingsStorageDialogAction')),
                          ),
                        ],
                      ),
                    );

                    if (shouldRequest != true) {
                      return;
                    }

                    await NativeBridge.requestStoragePermission();
                    // Refresh after returning from permission screen
                    final granted = await NativeBridge.hasStoragePermission();
                    setState(() => _storageGranted = granted);
                  },
                ),
                const Divider(),
                _sectionHeader(theme, l10n.t('settingsNode')),
                SwitchListTile(
                  title: Text(l10n.t('settingsEnableNode')),
                  subtitle: Text(l10n.t('settingsEnableNodeSubtitle')),
                  value: _nodeEnabled,
                  onChanged: (value) {
                    setState(() => _nodeEnabled = value);
                    _prefs.nodeEnabled = value;
                    final nodeProvider = context.read<NodeProvider>();
                    if (value) {
                      nodeProvider.enable();
                    } else {
                      nodeProvider.disable();
                    }
                  },
                ),
                ListTile(
                  title: Text(l10n.t('settingsNodeConfiguration')),
                  subtitle: Text(l10n.t('settingsNodeConfigurationSubtitle')),
                  leading: const Icon(Icons.devices),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NodeScreen()),
                  ),
                ),
                const Divider(),
                _sectionHeader(theme, l10n.t('settingsSystemInfo')),
                ListTile(
                  title: Text(l10n.t('settingsArchitecture')),
                  subtitle: Text(_arch),
                  leading: const Icon(Icons.memory),
                ),
                ListTile(
                  title: Text(l10n.t('settingsProotPath')),
                  subtitle: Text(_prootPath),
                  leading: const Icon(Icons.folder),
                ),
                ListTile(
                  title: Text(l10n.t('settingsRootfs')),
                  subtitle: Text(_status['rootfsExists'] == true
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.storage),
                ),
                ListTile(
                  title: Text(l10n.t('settingsNodeJs')),
                  subtitle: Text(_status['nodeInstalled'] == true
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.code),
                ),
                ListTile(
                  title: Text(l10n.t('settingsOpenClaw')),
                  subtitle: Text(_status['openclawInstalled'] == true
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.cloud),
                ),
                ListTile(
                  title: Text(l10n.t('settingsGo')),
                  subtitle: Text(_goInstalled
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.integration_instructions),
                ),
                ListTile(
                  title: Text(l10n.t('settingsHomebrew')),
                  subtitle: Text(_brewInstalled
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.science),
                ),
                ListTile(
                  title: Text(l10n.t('settingsOpenSsh')),
                  subtitle: Text(_sshInstalled
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.vpn_key),
                ),
                const Divider(),
                _sectionHeader(theme, l10n.t('settingsMaintenance')),
                ListTile(
                  title: Text(l10n.t('settingsExportSnapshot')),
                  subtitle: Text(l10n.t('settingsExportSnapshotSubtitle')),
                  leading: const Icon(Icons.upload_file),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportSnapshot,
                ),
                ListTile(
                  title: Text(l10n.t('settingsImportSnapshot')),
                  subtitle: Text(l10n.t('settingsImportSnapshotSubtitle')),
                  leading: const Icon(Icons.download),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _importSnapshot,
                ),
                ListTile(
                  title: Text(l10n.t('settingsRerunSetup')),
                  subtitle: Text(l10n.t('settingsRerunSetupSubtitle')),
                  leading: const Icon(Icons.build),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const SetupWizardScreen(),
                    ),
                  ),
                ),
                const Divider(),
                _sectionHeader(theme, l10n.t('settingsAbout')),
                ListTile(
                  title: Text(l10n.t('settingsOpenClaw')),
                  subtitle: Text(
                    l10n.t('settingsAboutSubtitle',
                        {'version': AppConstants.version}),
                  ),
                  leading: const Icon(Icons.info_outline),
                  isThreeLine: true,
                ),
                ListTile(
                  title: Text(l10n.t('settingsDeveloper')),
                  subtitle: const Text(AppConstants.authorName),
                  leading: const Icon(Icons.person),
                ),
                ListTile(
                  title: Text(l10n.t('settingsCheckForUpdates')),
                  subtitle: Text(l10n.t('settingsCheckForUpdatesSubtitle')),
                  leading: _checkingUpdate
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update),
                  onTap: _checkingUpdate ? null : _checkForUpdates,
                ),
                ListTile(
                  title: Text(l10n.t('settingsGithub')),
                  subtitle: const Text('JunWan666/openclaw-termux-zh'),
                  leading: const Icon(Icons.code),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse(AppConstants.githubUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  title: Text(l10n.t('settingsContact')),
                  subtitle: const Text(AppConstants.authorEmail),
                  leading: const Icon(Icons.email),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse('mailto:${AppConstants.authorEmail}'),
                  ),
                ),
                ListTile(
                  title: Text(l10n.t('settingsEmail')),
                  subtitle: const Text(AppConstants.authorEmail),
                  leading: const Icon(Icons.email_outlined),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse('mailto:${AppConstants.authorEmail}'),
                  ),
                ),
                ListTile(
                  title: Text(l10n.t('settingsLicense')),
                  subtitle: const Text(AppConstants.license),
                  leading: const Icon(Icons.description),
                ),
                Visibility(
                  visible: _showOrgSection,
                  maintainState: true,
                  child: Column(
                    children: [
                      const Divider(),
                      _sectionHeader(theme, AppConstants.orgName.toUpperCase()),
                      ListTile(
                        title: const Text('Instagram'),
                        subtitle: const Text('@nexgenxplorer_nxg'),
                        leading: const Icon(Icons.camera_alt),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => launchUrl(
                          Uri.parse(AppConstants.instagramUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      ListTile(
                        title: const Text('YouTube'),
                        subtitle: const Text('@nexgenxplorer'),
                        leading: const Icon(Icons.play_circle_fill),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => launchUrl(
                          Uri.parse(AppConstants.youtubeUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      ListTile(
                        title: Text(l10n.t('settingsPlayStore')),
                        subtitle: const Text('NextGenX Apps'),
                        leading: const Icon(Icons.shop),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => launchUrl(
                          Uri.parse(AppConstants.playStoreUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<String?> _getSnapshotPath() async {
    final directory = await _getSnapshotDirectory();
    final fileName = await _promptSnapshotFileName(directory.path);
    if (fileName == null || fileName.isEmpty) {
      return null;
    }
    return '${directory.path}/$fileName';
  }

  Future<Directory> _getSnapshotDirectory() async {
    final hasPermission = await NativeBridge.hasStoragePermission();
    if (hasPermission) {
      final sdcard = await NativeBridge.getExternalStoragePath();
      final downloadDir = Directory('$sdcard/Download');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    }
    // Fallback to app-private directory
    final dir = await getApplicationDocumentsDirectory();
    return dir;
  }

  String _defaultSnapshotFileName() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return 'openclaw-snapshot-$year-$month-$day-$hour$minute$second.json';
  }

  String _normalizeSnapshotFileName(String raw) {
    final trimmed = raw.trim();
    final safe = trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), '-');
    final fallback = safe.isEmpty ? _defaultSnapshotFileName() : safe;
    return fallback.toLowerCase().endsWith('.json')
        ? fallback
        : '$fallback.json';
  }

  Future<String?> _promptSnapshotFileName(String directoryPath) async {
    final controller = TextEditingController(text: _defaultSnapshotFileName());
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('settingsSnapshotFileNameTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('settingsSnapshotFileNameHelper', {
                'path': directoryPath,
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.t('settingsSnapshotFileNameLabel'),
                hintText: _defaultSnapshotFileName(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_normalizeSnapshotFileName(controller.text)),
            child: Text(context.l10n.t('settingsExportSnapshot')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _exportSnapshot() async {
    try {
      final snapshot =
          await SnapshotService.buildSnapshot(AppConstants.version);

      final path = await _getSnapshotPath();
      if (path == null || path.isEmpty) {
        return;
      }
      final file = File(path);
      await file
          .writeAsString(const JsonEncoder.withIndent('  ').convert(snapshot));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10n.t('settingsSnapshotSaved', {'path': path})),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('settingsExportFailed', {'error': e})),
        ),
      );
    }
  }

  Future<void> _importSnapshot() async {
    final l10n = context.l10n;
    try {
      final pickedName = await SnapshotService.pickAndRestoreSnapshot(
        emptyFileMessage: l10n.t('settingsSnapshotFileEmpty'),
      );
      if (pickedName == null) {
        return;
      }

      // Refresh UI
      await _loadSettings();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('settingsSnapshotRestored', {
              'file': pickedName,
            }),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('settingsImportFailed', {'error': e})),
        ),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    final l10n = context.l10n;
    setState(() => _checkingUpdate = true);
    try {
      final result = await UpdateService.check();
      if (!mounted) return;
      if (result.available) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.t('settingsUpdateAvailableTitle')),
            content: Text(
              l10n.t('settingsUpdateAvailableBody', {
                'current': AppConstants.version,
                'latest': result.latest,
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.t('settingsUpdateLater')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _downloadAndInstallUpdate(result);
                },
                child: Text(l10n.t('settingsUpdateDownload')),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('settingsLatestVersion'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('settingsUpdateCheckFailed'))),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _downloadAndInstallUpdate(UpdateResult result) async {
    final l10n = context.l10n;
    final progress = ValueNotifier<_UpdateProgressState>(
      _UpdateProgressState(
        title: l10n.t('settingsUpdateDownloadingTitle'),
        detail: l10n.t('settingsUpdatePreparingDownload'),
      ),
    );
    UpdateReleaseAsset? selectedAsset;
    var dialogShown = false;

    try {
      final arch = await NativeBridge.getArch();
      selectedAsset = result.preferredApkAssetForArch(arch);
      if (selectedAsset == null) {
        throw Exception(l10n.t('settingsUpdateNoCompatibleAsset'));
      }

      if (!mounted) return;
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: ValueListenableBuilder<_UpdateProgressState>(
            valueListenable: progress,
            builder: (context, state, _) {
              final detailStyle =
                  Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      );
              final progressText = state.progress == null
                  ? l10n.t('settingsUpdateProgressUnknown')
                  : l10n.t('settingsUpdateProgressPercent', {
                      'percent': (state.progress! * 100).clamp(0, 100).round(),
                    });

              return AlertDialog(
                title: Text(state.title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.detail),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: state.progress),
                    const SizedBox(height: 8),
                    Text(progressText, style: detailStyle),
                  ],
                ),
              );
            },
          ),
        ),
      );

      progress.value = _UpdateProgressState(
        title: l10n.t('settingsUpdateDownloadingTitle'),
        detail: l10n.t('settingsUpdateDownloadingFile', {
          'file': selectedAsset.name,
        }),
      );

      final apkPath = await UpdateService.downloadAsset(
        selectedAsset,
        onProgress: (received, total) {
          final normalizedProgress =
              total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          progress.value = _UpdateProgressState(
            title: l10n.t('settingsUpdateDownloadingTitle'),
            detail: l10n.t('settingsUpdateDownloadingFile', {
              'file': selectedAsset!.name,
            }),
            progress: normalizedProgress,
          );
        },
      );

      progress.value = _UpdateProgressState(
        title: l10n.t('settingsUpdateDownloadingTitle'),
        detail: l10n.t('settingsUpdateInstalling'),
      );

      await NativeBridge.installApk(apkPath);

      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('settingsUpdateInstallerOpened'))),
      );
    } catch (_) {
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      await _openUpdateFallback(result, asset: selectedAsset);
    } finally {
      progress.dispose();
    }
  }

  Future<void> _openUpdateFallback(
    UpdateResult result, {
    UpdateReleaseAsset? asset,
  }) async {
    if (!mounted) return;
    final l10n = context.l10n;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('settingsUpdateFallbackBrowser'))),
    );

    final preferredUrl = asset?.downloadUrl ?? result.url;
    final preferredUri = Uri.parse(preferredUrl);
    final openedPreferred = await launchUrl(
      preferredUri,
      mode: LaunchMode.externalApplication,
    );

    if (openedPreferred || preferredUrl == result.url) {
      return;
    }

    await launchUrl(
      Uri.parse(result.url),
      mode: LaunchMode.externalApplication,
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _UpdateProgressState {
  const _UpdateProgressState({
    required this.title,
    required this.detail,
    this.progress,
  });

  final String title;
  final String detail;
  final double? progress;
}
