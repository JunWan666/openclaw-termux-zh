import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../services/cpolar_package_service.dart';
import 'web_dashboard_screen.dart';

class CpolarScreen extends StatefulWidget {
  final bool startInstallOnOpen;

  const CpolarScreen({
    super.key,
    this.startInstallOnOpen = false,
  });

  @override
  State<CpolarScreen> createState() => _CpolarScreenState();
}

class _CpolarScreenState extends State<CpolarScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _showInstallLogs = false;
  CpolarPackageState _state = const CpolarPackageState.empty();
  List<String> _installLogs = const <String>[];
  final ScrollController _installLogController = ScrollController();

  @override
  void initState() {
    super.initState();
    _refreshState();
    if (widget.startInstallOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runInstallIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _installLogController.dispose();
    super.dispose();
  }

  Future<void> _refreshState() async {
    try {
      final state = await CpolarPackageService.readState();
      if (mounted) {
        setState(() {
          _state = state;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t(
                'packageCpolarOperationFailed',
                {'error': error.toString()},
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _runInstallIfNeeded() async {
    if (_busy) {
      return;
    }
    if (_state.installed) {
      return;
    }
    await _runInstall();
  }

  Future<void> _runInstall() async {
    if (_busy) {
      return;
    }

    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _showInstallLogs = true;
      _installLogs = <String>[l10n.t('packageCpolarPreparingInstall')];
    });
    _scrollInstallLogsToBottom();

    try {
      await CpolarPackageService.installOrUpdateLatest(
        onLogChanged: (lines) {
          if (!mounted) {
            return;
          }
          setState(() {
            _installLogs = lines.isEmpty
                ? <String>[l10n.t('packageCpolarPreparingInstall')]
                : lines;
          });
          _scrollInstallLogsToBottom();
        },
      );
      await _refreshState();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'packageCpolarOperationFailed',
              {'error': error.toString()},
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showInstallLogs = false;
          _installLogs = const <String>[];
        });
      }
    }
  }

  Future<void> _runCpolarAction(Future<void> Function() action) async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);
    try {
      await action();
      await _refreshState();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'packageCpolarOperationFailed',
              {'error': error.toString()},
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openDashboard() async {
    if (!_state.canOpenDashboard) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebDashboardScreen(url: _state.dashboardUrl),
      ),
    );

    if (!mounted) {
      return;
    }
    await _refreshState();
  }

  Future<void> _openTokenPage() async {
    await launchUrl(
      Uri.parse(_state.tokenPageUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void _scrollInstallLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_installLogController.hasClients) {
        return;
      }

      _installLogController.animateTo(
        _installLogController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _confirmUninstall() {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('packagesUninstallTitle', {'name': 'cpolar'})),
        content: Text(
          l10n.t('packagesUninstallDescription', {'name': 'cpolar'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _runCpolarAction(CpolarPackageService.uninstall);
            },
            child: Text(l10n.t('packagesUninstall')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: const Text('cpolar'),
        actions: [
          IconButton(
            tooltip: l10n.t('logsRefresh'),
            onPressed: _busy ? null : _refreshState,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOverviewCard(theme, l10n),
                const SizedBox(height: 12),
                _buildActionCard(theme, l10n),
                if (_showInstallLogs) ...[
                  const SizedBox(height: 12),
                  _buildInstallLogsCard(theme, l10n),
                ],
                if (_state.installed) ...[
                  const SizedBox(height: 12),
                  _buildDetailsCard(theme, l10n),
                ],
                if (_state.installed && _state.deviceIps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildLocalAccessCard(theme, l10n),
                ],
                if (_state.installed && _state.recentLogs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildRecentLogsCard(theme, l10n),
                ],
              ],
            ),
    );
  }

  Widget _buildOverviewCard(ThemeData theme, AppLocalizations l10n) {
    final statusColor = !_state.installed
        ? theme.colorScheme.outline
        : _state.running
            ? AppColors.statusGreen
            : theme.colorScheme.secondary;
    final statusText = !_state.installed
        ? l10n.t('commonNotInstalled')
        : _state.running
            ? l10n.t('packageCpolarStatusRunning')
            : l10n.t('packageCpolarStatusStopped');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'cpolar',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.t('packageCpolarRuntimeBody'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (!_state.archSupported) ...[
              const SizedBox(height: 12),
              Text(
                '${l10n.t('commonUnavailable')}: ${_state.architecture}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_state.installed &&
                _state.running &&
                !_state.dashboardReachable) ...[
              const SizedBox(height: 12),
              Text(
                l10n.t('packageCpolarDashboardStarting'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('packageCpolarRuntimeTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_state.installed)
                  FilledButton.icon(
                    onPressed:
                        !_busy && _state.archSupported ? _runInstall : null,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(l10n.t('packagesInstall')),
                  ),
                if (_state.installed && !_state.running)
                  FilledButton.icon(
                    onPressed: !_busy
                        ? () => _runCpolarAction(CpolarPackageService.start)
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(l10n.t('packageCpolarStart')),
                  ),
                if (_state.installed && _state.running)
                  OutlinedButton.icon(
                    onPressed: !_busy
                        ? () => _runCpolarAction(CpolarPackageService.stop)
                        : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(l10n.t('packageCpolarStop')),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openTokenPage,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.t('packageCpolarTokenPage')),
                ),
                OutlinedButton.icon(
                  onPressed:
                      !_busy && _state.canOpenDashboard ? _openDashboard : null,
                  icon: const Icon(Icons.open_in_browser_outlined),
                  label: Text(l10n.t('packageCpolarOpenDashboard')),
                ),
                if (_state.installed)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _confirmUninstall,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.t('packagesUninstall')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallLogsCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('packageCpolarInstallLogsTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Scrollbar(
                controller: _installLogController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _installLogController,
                  child: SelectableText(
                    _installLogs.join('\n'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(l10n.t('commonStatus')),
            subtitle: Text(
              _state.running
                  ? l10n.t('packageCpolarStatusRunning')
                  : l10n.t('packageCpolarStatusStopped'),
            ),
          ),
          ListTile(
            title: Text(l10n.t('commonVersion')),
            subtitle: Text(_state.installedVersion ?? l10n.t('commonUnknown')),
          ),
          ListTile(
            title: Text(l10n.t('settingsArchitecture')),
            subtitle: Text(_state.architecture),
          ),
          ListTile(
            title: Text(l10n.t('packageCpolarAuthtokenLabel')),
            subtitle: Text(
              _state.authtokenPreview ?? l10n.t('commonNotConfigured'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalAccessCard(ThemeData theme, AppLocalizations l10n) {
    final urls = <String>[
      _state.dashboardUrl,
      ..._state.deviceIps.map((ip) => 'http://$ip:${_state.dashboardPort}'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('packageCpolarLocalAccessTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              urls.join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLogsCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('packageCpolarRecentLogsTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SelectableText(
                  _state.recentLogs.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
