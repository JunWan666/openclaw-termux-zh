import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/node_state.dart';
import '../providers/node_provider.dart';
import '../services/provider_config_service.dart';
import '../widgets/gateway_controls.dart';
import '../widgets/status_card.dart';
import 'command_shortcuts_screen.dart';
import 'config_editor_screen.dart';
import 'configure_screen.dart';
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

class _DashboardScreenState extends State<DashboardScreen> {
  String? _activeModel;
  bool _loadingActiveModel = true;

  @override
  void initState() {
    super.initState();
    _refreshActiveModel();
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

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    await _refreshActiveModel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('appName')),
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
              onTap: () => _openScreen(const SettingsScreen()),
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
              title: l10n.t('dashboardCommandsTitle'),
              subtitle: l10n.t('dashboardCommandsSubtitle'),
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
}
