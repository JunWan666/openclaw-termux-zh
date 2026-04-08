import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/gateway_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/node_provider.dart';
import '../services/backup_service.dart';
import '../services/native_bridge.dart';
import '../services/openclaw_version_service.dart';
import '../services/preferences_service.dart';
import '../services/provider_config_service.dart';
import '../services/snapshot_service.dart';
import '../services/update_flow_service.dart';
import '../services/update_service.dart';
import 'node_screen.dart';
import 'setup_wizard_screen.dart';

enum _BackupExportKind { config, workspace }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _showOrgSection = false;

  final _prefs = PreferencesService();
  final _openClawVersionService = OpenClawVersionService();
  bool _autoStart = false;
  bool _bonjourEnabled = false;
  bool _nodeEnabled = false;
  bool _batteryOptimized = true;
  String _arch = '';
  String _prootPath = '';
  Map<String, dynamic> _status = {};
  bool _loading = true;
  bool _goInstalled = false;
  bool _brewInstalled = false;
  bool _sshInstalled = false;
  bool _adbInstalled = false;
  bool _cpolarInstalled = false;
  bool _storageGranted = false;
  bool _persistentGatewayLogs = false;
  bool _checkingUpdate = false;
  bool _updatingBonjour = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _prefs.init();
    _autoStart = _prefs.autoStartGateway;
    _bonjourEnabled = await ProviderConfigService.readBonjourEnabled();
    _prefs.bonjourEnabled = _bonjourEnabled;
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
      final adbInstalled = File('$rootfs/usr/bin/adb').existsSync();
      final cpolarInstalled = File('$rootfs/usr/local/bin/cpolar').existsSync();

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
        _adbInstalled = adbInstalled;
        _cpolarInstalled = cpolarInstalled;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _setBonjourEnabled(bool value) async {
    final previous = _bonjourEnabled;
    setState(() {
      _bonjourEnabled = value;
      _updatingBonjour = true;
    });

    try {
      _prefs.bonjourEnabled = value;
      await ProviderConfigService.setBonjourEnabled(value);
      if (!mounted) return;
      await context.read<GatewayProvider>().applyConfigChanges(
            source: 'Bonjour discovery setting',
          );
    } catch (e) {
      _prefs.bonjourEnabled = previous;
      if (!mounted) return;
      setState(() => _bonjourEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('settingsBonjourUpdateFailed', {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingBonjour = false);
      }
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
                SwitchListTile(
                  title: Text(l10n.t('settingsBonjourDiscovery')),
                  subtitle: Text(l10n.t('settingsBonjourDiscoverySubtitle')),
                  value: _bonjourEnabled,
                  onChanged: _updatingBonjour
                      ? null
                      : (value) => _setBonjourEnabled(value),
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
                _sectionHeader(theme, l10n.t('settingsMaintenance')),
                ListTile(
                  title: Text(l10n.t('settingsExportSnapshot')),
                  subtitle: Text(l10n.t('settingsExportSnapshotSubtitle')),
                  leading: const Icon(Icons.upload_file),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportBackup,
                ),
                ListTile(
                  title: Text(l10n.t('settingsImportSnapshot')),
                  subtitle: Text(l10n.t('settingsImportSnapshotSubtitle')),
                  leading: const Icon(Icons.download),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _importBackup,
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
                ListTile(
                  title: Text(l10n.t('settingsAdb')),
                  subtitle: Text(_adbInstalled
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.developer_mode),
                ),
                ListTile(
                  title: Text(l10n.t('settingsCpolar')),
                  subtitle: Text(_cpolarInstalled
                      ? l10n.t('statusInstalled')
                      : l10n.t('statusNotInstalled')),
                  leading: const Icon(Icons.hub),
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

  String _backupTimestampSuffix() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$year-$month-$day-$hour$minute$second';
  }

  String _defaultConfigBackupFileName({
    required String appVersion,
    String? openClawVersion,
  }) {
    final appPart = _sanitizeBackupFilePart(appVersion);
    final openClawPart = _sanitizeBackupFilePart(openClawVersion);
    return 'openclaw-config-app-$appPart-openclaw-$openClawPart-${_backupTimestampSuffix()}.json';
  }

  String _defaultWorkspaceBackupFileName({
    required String appVersion,
    String? openClawVersion,
  }) {
    final appPart = _sanitizeBackupFilePart(appVersion);
    final openClawPart = _sanitizeBackupFilePart(openClawVersion);
    return 'openclaw-workspace-app-$appPart-openclaw-$openClawPart-${_backupTimestampSuffix()}.zip';
  }

  String _sanitizeBackupFilePart(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'unknown';
    }

    final sanitized = normalized
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  Future<_BackupExportKind?> _pickExportKind() async {
    final l10n = context.l10n;
    return showDialog<_BackupExportKind>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('settingsBackupExportTypeTitle')),
        contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(l10n.t('settingsBackupExportWorkspace')),
              subtitle: Text(l10n.t('settingsBackupExportWorkspaceSubtitle')),
              onTap: () => Navigator.of(dialogContext).pop(
                _BackupExportKind.workspace,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.t('settingsBackupExportConfig')),
              subtitle: Text(l10n.t('settingsBackupExportConfigSubtitle')),
              onTap: () => Navigator.of(dialogContext).pop(
                _BackupExportKind.config,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.t('commonCancel')),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmSnapshotImportIfNeeded(
    SnapshotCompatibility compatibility,
  ) async {
    if (!compatibility.requiresConfirmation) {
      return true;
    }

    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('settingsSnapshotVersionWarningTitle')),
        content: SingleChildScrollView(
          child: Text(_buildSnapshotImportWarningMessage(l10n, compatibility)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('commonContinue')),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<bool> _confirmConfigImport() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('settingsBackupImportConfigWarningTitle')),
        content: Text(l10n.t('settingsBackupImportConfigWarningBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('commonContinue')),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<bool> _confirmWorkspaceImportIfNeeded(
    SnapshotCompatibility? compatibility,
  ) async {
    final l10n = context.l10n;
    final lines = <String>[
      l10n.t('settingsBackupImportWorkspaceWarningBody'),
    ];

    if (compatibility != null && compatibility.requiresConfirmation) {
      lines
        ..add('')
        ..add(_buildSnapshotImportWarningMessage(l10n, compatibility));
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('settingsBackupImportWorkspaceWarningTitle')),
        content: SingleChildScrollView(
          child: Text(lines.join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('commonContinue')),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  String _buildSnapshotImportWarningMessage(
    AppLocalizations l10n,
    SnapshotCompatibility compatibility,
  ) {
    final unknown = l10n.t('commonUnknown');
    final lines = <String>[
      l10n.t('settingsSnapshotVersionWarningIntro'),
    ];

    if (compatibility.hasMissingVersionInfo) {
      lines.add(l10n.t('settingsSnapshotVersionWarningMissing'));
    }
    if (compatibility.hasAppVersionMismatch) {
      lines.add(l10n.t('settingsSnapshotVersionWarningAppMismatch'));
    }
    if (compatibility.hasOpenClawVersionMismatch) {
      lines.add(l10n.t('settingsSnapshotVersionWarningOpenClawMismatch'));
    }

    lines.add('');
    lines.add(
      l10n.t('settingsSnapshotVersionSnapshotApp', {
        'version': compatibility.snapshotAppVersion ?? unknown,
      }),
    );
    lines.add(
      l10n.t('settingsSnapshotVersionCurrentApp', {
        'version': compatibility.currentAppVersion ?? unknown,
      }),
    );
    lines.add(
      l10n.t('settingsSnapshotVersionSnapshotOpenClaw', {
        'version': compatibility.snapshotOpenClawVersion ?? unknown,
      }),
    );
    lines.add(
      l10n.t('settingsSnapshotVersionCurrentOpenClaw', {
        'version': compatibility.currentOpenClawVersion ?? unknown,
      }),
    );

    return lines.join('\n');
  }

  Future<void> _exportBackup() async {
    final exportKind = await _pickExportKind();
    if (exportKind == null) {
      return;
    }

    try {
      final installedOpenClawVersion =
          await _openClawVersionService.readInstalledVersion();
      late final String fallbackName;
      late final Map<String, dynamic>? saved;
      switch (exportKind) {
        case _BackupExportKind.config:
          fallbackName = _defaultConfigBackupFileName(
            appVersion: AppConstants.version,
            openClawVersion: installedOpenClawVersion,
          );
          saved = await BackupService.exportConfigBackup(
            suggestedName: fallbackName,
          );
          break;
        case _BackupExportKind.workspace:
          fallbackName = _defaultWorkspaceBackupFileName(
            appVersion: AppConstants.version,
            openClawVersion: installedOpenClawVersion,
          );
          saved = await BackupService.exportWorkspaceBackup(
            suggestedName: fallbackName,
            appVersion: AppConstants.version,
            openClawVersion: installedOpenClawVersion,
          );
          break;
      }

      if (saved == null) {
        return;
      }
      final savedName = (saved['name'] as String?) ?? fallbackName;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('settingsSnapshotSaved', {'path': savedName}),
          ),
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

  Future<void> _importBackup() async {
    final l10n = context.l10n;
    try {
      final picked = await BackupService.pickBackupForRestore(
        emptyFileMessage: l10n.t('settingsSnapshotFileEmpty'),
        unsupportedFileMessage: l10n.t('settingsBackupUnsupportedFile'),
        invalidWorkspaceBackupMessage:
            l10n.t('settingsBackupInvalidWorkspaceArchive'),
      );
      if (picked == null) {
        return;
      }

      final currentOpenClawVersion =
          await _openClawVersionService.readInstalledVersion();
      final compatibility = picked.compatibility(
        currentAppVersion: AppConstants.version,
        currentOpenClawVersion: currentOpenClawVersion,
      );
      final shouldContinue = switch (picked.kind) {
        BackupImportKind.config => await _confirmConfigImport(),
        BackupImportKind.legacySnapshot => compatibility == null
            ? true
            : await _confirmSnapshotImportIfNeeded(compatibility),
        BackupImportKind.workspace =>
          await _confirmWorkspaceImportIfNeeded(compatibility),
      };
      if (!shouldContinue) {
        return;
      }

      if (!mounted) return;
      final gatewayProvider = context.read<GatewayProvider>();
      await gatewayProvider.stop();
      await gatewayProvider.syncState();
      await picked.restore();

      // Refresh UI
      await _loadSettings();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('settingsSnapshotRestored', {
              'file': picked.fileName,
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
        await UpdateFlowService.showUpdateDialog(context, result);
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
