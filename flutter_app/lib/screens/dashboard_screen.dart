import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/node_state.dart';
import '../providers/gateway_provider.dart';
import '../providers/node_provider.dart';
import '../services/provider_config_service.dart';
import '../services/update_flow_service.dart';
import '../services/update_service.dart';
import '../widgets/gateway_controls.dart';
import '../widgets/status_card.dart';
import 'backup_manager_screen.dart';
import 'command_shortcuts_screen.dart';
import 'config_editor_screen.dart';
import 'configure_screen.dart';
import 'local_model_screen.dart';
import 'logs_screen.dart';
import 'message_platforms_screen.dart';
import 'node_screen.dart';
import 'packages_screen.dart';
import 'providers_screen.dart';
import 'settings_screen.dart';
import 'ssh_screen.dart';
import 'terminal_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _showLogsShortcut = false;

  String? _activeModel;
  bool _loadingActiveModel = true;
  UpdateResult? _latestAppUpdate;
  bool _checkingAppUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshActiveModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAppUpdateStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAppUpdateStatus();
    }
  }

  Future<void> _refreshActiveModel() async {
    if (mounted) {
      setState(() => _loadingActiveModel = true);
    }

    try {
      final config = await ProviderConfigService.readConfig();
      final activeModel = _formatModelName(config['activeModel'] as String?);
      if (!mounted) return;
      setState(() => _activeModel = activeModel);
    } finally {
      if (mounted) {
        setState(() => _loadingActiveModel = false);
      }
    }
  }

  String? _formatModelName(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final slashIndex = trimmed.lastIndexOf('/');
    return slashIndex >= 0 ? trimmed.substring(slashIndex + 1) : trimmed;
  }

  Future<void> _refreshAppUpdateStatus() async {
    try {
      final result = await UpdateService.check();
      if (!mounted) return;
      setState(() => _latestAppUpdate = result);
    } catch (_) {
      // Keep the header button quiet when the release API is temporarily unreachable.
    }
  }

  Future<void> _handleAppUpdateTap() async {
    if (_checkingAppUpdate) return;

    final cachedResult = _latestAppUpdate;
    if (cachedResult?.available == true) {
      await UpdateFlowService.showUpdateDialog(context, cachedResult!);
      return;
    }

    final l10n = context.l10n;
    setState(() => _checkingAppUpdate = true);
    try {
      final result = await UpdateService.check();
      if (!mounted) return;

      setState(() => _latestAppUpdate = result);
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
      if (mounted) {
        setState(() => _checkingAppUpdate = false);
      }
    }
  }

  Widget _buildAppUpdateAction(ThemeData theme, AppLocalizations l10n) {
    final hasUpdate = _latestAppUpdate?.available == true;
    final iconColor =
        hasUpdate ? AppColors.accent : theme.colorScheme.onSurfaceVariant;
    final borderColor = hasUpdate
        ? AppColors.accent.withAlpha(90)
        : theme.colorScheme.outline.withAlpha(180);
    final backgroundColor = hasUpdate
        ? AppColors.accent
            .withAlpha(theme.brightness == Brightness.dark ? 26 : 18)
        : Colors.transparent;
    final tooltip = hasUpdate
        ? l10n.t('settingsUpdateAvailableTitle')
        : l10n.t('settingsCheckForUpdates');
    final semanticLabel = hasUpdate
        ? '${l10n.t('settingsUpdateAvailableTitle')} ${_latestAppUpdate?.latest ?? ''}'
            .trim()
        : l10n.t('settingsCheckForUpdates');

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _checkingAppUpdate ? null : _handleAppUpdateTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _checkingAppUpdate
                          ? SizedBox(
                              key: const ValueKey('checking'),
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: iconColor,
                              ),
                            )
                          : Icon(
                              hasUpdate
                                  ? Icons.system_update_alt_rounded
                                  : Icons.system_update_alt_outlined,
                              key: ValueKey('update-$hasUpdate'),
                              size: 16,
                              color: iconColor,
                            ),
                    ),
                    if (hasUpdate && !_checkingAppUpdate)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.statusRed,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppVersionBadge(ThemeData theme) {
    final versionLabel = AppConstants.version.startsWith('v')
        ? AppConstants.version
        : 'v${AppConstants.version}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withAlpha(120),
        ),
      ),
      child: Text(
        versionLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    await context.read<GatewayProvider>().syncState();
    await _refreshActiveModel();
    await _refreshAppUpdateStatus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.t('appName')),
            const SizedBox(width: 8),
            _buildAppVersionBadge(theme),
            const SizedBox(width: 8),
            _buildAppUpdateAction(theme, l10n),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openScreen(const SettingsScreen()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GatewayControls(
              activeModel: _activeModel,
              isLoadingActiveModel: _loadingActiveModel,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                l10n.t('dashboardQuickActions'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            StatusCard(
              title: l10n.t('dashboardProvidersTitle'),
              subtitle: l10n.t('dashboardProvidersSubtitle'),
              icon: Icons.model_training,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const ProvidersScreen()),
            ),
            StatusCard(
              title: l10n.t('dashboardMessagePlatformsTitle'),
              subtitle: l10n.t('dashboardMessagePlatformsSubtitle'),
              icon: Icons.chat,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const MessagePlatformsScreen()),
            ),
            StatusCard(
              title: l10n.t('dashboardTerminalTitle'),
              subtitle: l10n.t('dashboardTerminalSubtitle'),
              icon: Icons.terminal,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const TerminalScreen()),
            ),
            StatusCard(
              title: l10n.t('dashboardConfigureTitle'),
              subtitle: l10n.t('dashboardConfigureSubtitle'),
              icon: Icons.tune,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const ConfigureScreen()),
            ),
            StatusCard(
              title: l10n.t('dashboardPackagesTitle'),
              subtitle: l10n.t('dashboardPackagesSubtitle'),
              icon: Icons.extension,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const PackagesScreen()),
            ),
            StatusCard(
              title: l10n.t('dashboardSshTitle'),
              subtitle: l10n.t('dashboardSshSubtitle'),
              icon: Icons.terminal,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const SshScreen()),
            ),
            StatusCard(
              title: l10n.t('dashboardLocalModelTitle'),
              subtitle: l10n.t('dashboardLocalModelSubtitle'),
              icon: Icons.memory_rounded,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const LocalModelScreen()),
            ),
            if (_showLogsShortcut)
              StatusCard(
                title: l10n.t('dashboardLogsTitle'),
                subtitle: l10n.t('dashboardLogsSubtitle'),
                icon: Icons.article_outlined,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openScreen(const LogsScreen()),
              ),
            StatusCard(
              title: l10n.t('dashboardSnapshotTitle'),
              subtitle: l10n.t('dashboardSnapshotSubtitle'),
              icon: Icons.backup,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const BackupManagerScreen()),
            ),
            StatusCard(
              title: l10n.t('dashboardEditConfigTitle'),
              subtitle: l10n.t('dashboardEditConfigSubtitle'),
              icon: Icons.edit_note_outlined,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const ConfigEditorScreen()),
            ),
            Consumer<NodeProvider>(
              builder: (context, nodeProvider, _) {
                final nodeState = nodeProvider.state;
                return StatusCard(
                  title: l10n.t('dashboardNodeTitle'),
                  subtitle: nodeState.isPaired
                      ? l10n.t('dashboardNodeConnected')
                      : nodeState.isDisabled
                          ? l10n.t('dashboardNodeDisabled')
                          : _nodeStatusText(l10n, nodeState.status),
                  icon: Icons.devices,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openScreen(const NodeScreen()),
                );
              },
            ),
            StatusCard(
              title: _guidesTitle(context, l10n),
              subtitle: _guidesSubtitle(context, l10n),
              icon: Icons.code_outlined,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openScreen(const CommandShortcutsScreen()),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Text(
                    l10n.t(
                      'dashboardVersionLabel',
                      {'version': AppConstants.version},
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.t(
                      'dashboardAuthorLabel',
                      {
                        'author': AppConstants.authorName,
                        'org': AppConstants.orgName,
                      },
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nodeStatusText(AppLocalizations l10n, NodeStatus status) {
    switch (status) {
      case NodeStatus.disabled:
        return l10n.t('nodeStatusDisabled');
      case NodeStatus.disconnected:
        return l10n.t('nodeStatusDisconnected');
      case NodeStatus.connecting:
      case NodeStatus.challenging:
      case NodeStatus.pairing:
        return l10n.t('nodeStatusConnecting');
      case NodeStatus.paired:
        return l10n.t('nodeStatusPaired');
      case NodeStatus.error:
        return l10n.t('nodeStatusError');
    }
  }

  String _guidesTitle(BuildContext context, AppLocalizations l10n) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '常用说明'
        : 'Guides';
  }

  String _guidesSubtitle(BuildContext context, AppLocalizations l10n) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '查看常见操作说明，并复制相关命令、地址或提示词'
        : 'Open common how-to guides and copy related commands or prompts';
  }
}
