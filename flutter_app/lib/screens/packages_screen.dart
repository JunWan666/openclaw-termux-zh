import 'package:flutter/material.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/optional_package.dart';
import '../services/cpolar_package_service.dart';
import '../services/package_service.dart';
import 'package_install_screen.dart';
import 'web_dashboard_screen.dart';

/// Lists all optional packages with install/uninstall actions.
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  Map<String, bool> _statuses = {};
  bool _loading = true;
  bool _cpolarBusy = false;
  bool _showCpolarInstallLogs = false;
  CpolarPackageState _cpolarState = const CpolarPackageState.empty();
  List<String> _cpolarInstallLogs = const <String>[];
  final ScrollController _cpolarInstallLogController = ScrollController();

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  @override
  void dispose() {
    _cpolarInstallLogController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatuses() async {
    final statuses = await PackageService.checkAllStatuses();
    CpolarPackageState cpolarState = const CpolarPackageState.empty();
    try {
      cpolarState = await CpolarPackageService.readState();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _statuses = statuses;
        _cpolarState = cpolarState;
        _loading = false;
      });
    }
  }

  Future<void> _navigateToInstall(
    OptionalPackage package, {
    bool isUninstall = false,
  }) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PackageInstallScreen(
          package: package,
          isUninstall: isUninstall,
        ),
      ),
    );
    if (result == true) {
      _refreshStatuses();
    }
  }

  Future<void> _openCpolarDashboard() async {
    if (!_cpolarState.installed || !_cpolarState.running) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebDashboardScreen(url: _cpolarState.dashboardUrl),
      ),
    );

    if (!mounted) {
      return;
    }
    await _refreshStatuses();
  }

  Future<void> _runCpolarAction(Future<void> Function() action) async {
    if (_cpolarBusy) {
      return;
    }

    setState(() => _cpolarBusy = true);
    try {
      await action();
      await _refreshStatuses();
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
        setState(() => _cpolarBusy = false);
      }
    }
  }

  Future<void> _runCpolarInstall() async {
    if (_cpolarBusy) {
      return;
    }

    final l10n = context.l10n;
    setState(() {
      _cpolarBusy = true;
      _showCpolarInstallLogs = true;
      _cpolarInstallLogs = <String>[l10n.t('packageCpolarPreparingInstall')];
    });
    _scrollCpolarInstallLogsToBottom();

    try {
      await CpolarPackageService.installOrUpdateLatest(
        onLogChanged: (lines) {
          if (!mounted) {
            return;
          }

          setState(() {
            _cpolarInstallLogs = lines.isEmpty
                ? <String>[l10n.t('packageCpolarPreparingInstall')]
                : lines;
          });
          _scrollCpolarInstallLogsToBottom();
        },
      );
      await _refreshStatuses();
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
          _cpolarBusy = false;
          _showCpolarInstallLogs = false;
          _cpolarInstallLogs = const <String>[];
        });
      }
    }
  }

  void _scrollCpolarInstallLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cpolarInstallLogController.hasClients) {
        return;
      }

      final position = _cpolarInstallLogController.position.maxScrollExtent;
      _cpolarInstallLogController.animateTo(
        position,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _confirmUninstall(OptionalPackage package) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('packagesUninstallTitle', {'name': package.name})),
        content: Text(
          l10n.t('packagesUninstallDescription', {'name': package.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToInstall(package, isUninstall: true);
            },
            child: Text(l10n.t('packagesUninstall')),
          ),
        ],
      ),
    );
  }

  void _confirmCpolarUninstall() {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('packagesUninstallTitle', {'name': 'cpolar'})),
        content: Text(
          l10n.t('packagesUninstallDescription', {'name': 'cpolar'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
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
    final isDark = theme.brightness == Brightness.dark;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('packagesTitle'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.t('packagesDescription'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final pkg in OptionalPackage.all)
                  _buildPackageCard(theme, l10n, pkg, isDark),
              ],
            ),
    );
  }

  Widget _buildPackageCard(
    ThemeData theme,
    AppLocalizations l10n,
    OptionalPackage package,
    bool isDark,
  ) {
    final installed = _statuses[package.id] ?? false;
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    package.icon,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            package.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (installed) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.statusGreen.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                l10n.t('commonInstalled'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.statusGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _packageDescription(l10n, package),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        package.estimatedSize,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (package.id != 'cpolar')
                  installed
                      ? OutlinedButton(
                          onPressed: () => _confirmUninstall(package),
                          child: Text(l10n.t('packagesUninstall')),
                        )
                      : FilledButton(
                          onPressed: () => _navigateToInstall(package),
                          child: Text(l10n.t('packagesInstall')),
                        ),
              ],
            ),
            if (package.id == 'cpolar') ...[
              const SizedBox(height: 12),
              _buildCpolarControls(theme, l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCpolarControls(
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final installed = _cpolarState.installed;
    final running = _cpolarState.running;
    final archSupported = _cpolarState.archSupported;
    final statusColor = !installed
        ? theme.colorScheme.outline
        : running
            ? AppColors.statusGreen
            : theme.colorScheme.secondary;
    final statusText = !installed
        ? l10n.t('commonNotInstalled')
        : running
            ? l10n.t('packageCpolarStatusRunning')
            : l10n.t('packageCpolarStatusStopped');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('packageCpolarRuntimeTitle'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.t('packageCpolarRuntimeBody'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_cpolarBusy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (_showCpolarInstallLogs) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(180),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('packageCpolarInstallLogsTitle'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Scrollbar(
                      controller: _cpolarInstallLogController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _cpolarInstallLogController,
                        child: SelectableText(
                          _cpolarInstallLogs.join('\n'),
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
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!installed)
                FilledButton.icon(
                  onPressed:
                      !_cpolarBusy && archSupported ? _runCpolarInstall : null,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(l10n.t('packagesInstall')),
                ),
              if (installed)
                OutlinedButton.icon(
                  onPressed: !_cpolarBusy ? _confirmCpolarUninstall : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.t('packagesUninstall')),
                ),
              FilledButton.icon(
                onPressed: installed && !_cpolarBusy && !running
                    ? () => _runCpolarAction(CpolarPackageService.start)
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.t('packageCpolarStart')),
              ),
              OutlinedButton.icon(
                onPressed: installed && !_cpolarBusy && running
                    ? () => _runCpolarAction(CpolarPackageService.stop)
                    : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l10n.t('packageCpolarStop')),
              ),
              OutlinedButton.icon(
                onPressed: installed && running && !_cpolarBusy
                    ? _openCpolarDashboard
                    : null,
                icon: const Icon(Icons.open_in_browser_outlined),
                label: Text(l10n.t('packageCpolarOpenDashboard')),
              ),
            ],
          ),
          if (!archSupported) ...[
            const SizedBox(height: 10),
            Text(
              '${l10n.t('commonUnavailable')}: ${_cpolarState.architecture}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (installed && running && !_cpolarState.dashboardReachable) ...[
            const SizedBox(height: 10),
            Text(
              l10n.t('packageCpolarDashboardStarting'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _packageDescription(AppLocalizations l10n, OptionalPackage package) {
    switch (package.id) {
      case 'go':
        return l10n.t('packageGoDescription');
      case 'brew':
        return l10n.t('packageBrewDescription');
      case 'ssh':
        return l10n.t('packageSshDescription');
      case 'cpolar':
        return l10n.t('packageCpolarDescription');
      default:
        return package.description;
    }
  }
}
