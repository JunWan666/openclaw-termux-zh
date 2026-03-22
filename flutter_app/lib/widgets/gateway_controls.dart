import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/gateway_state.dart';
import '../providers/gateway_provider.dart';
import '../screens/logs_screen.dart';
import '../screens/web_dashboard_screen.dart';
import '../services/openclaw_version_service.dart';

class GatewayControls extends StatefulWidget {
  const GatewayControls({super.key});

  @override
  State<GatewayControls> createState() => _GatewayControlsState();
}

class _GatewayControlsState extends State<GatewayControls> {
  final _versionService = OpenClawVersionService();

  String? _installedVersion;
  OpenClawReleaseInfo? _latestRelease;
  bool _loadingInstalledVersion = true;
  bool _checkingForUpdate = false;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _refreshInstalledVersion();
  }

  bool get _hasUpdateAvailable {
    final latestRelease = _latestRelease;
    if (latestRelease == null) {
      return false;
    }

    return OpenClawVersionService.isUpdateAvailable(
      installedVersion: _installedVersion,
      latestVersion: latestRelease.version,
    );
  }

  Future<void> _refreshInstalledVersion({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _loadingInstalledVersion = true);
    }

    try {
      final version = await _versionService.readInstalledVersion();
      if (!mounted) return;
      setState(() {
        _installedVersion = version;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingInstalledVersion = false);
      }
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdate || _updating) return;

    setState(() => _checkingForUpdate = true);
    try {
      final latestRelease = await _versionService.fetchLatestRelease();
      if (!mounted) return;
      setState(() => _latestRelease = latestRelease);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('gatewayVersionCheckFailed', {'error': e}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checkingForUpdate = false);
      }
    }
  }

  Future<void> _runUpdate(GatewayProvider provider) async {
    if (_updating || _checkingForUpdate) return;

    final shouldRestart = provider.state.isRunning ||
        provider.state.status == GatewayStatus.starting;

    setState(() => _updating = true);
    try {
      if (provider.state.status != GatewayStatus.stopped) {
        await provider.stop();
      }

      await _versionService.updateToLatest(latestRelease: _latestRelease);
      await _refreshInstalledVersion(showLoading: false);
      final latestRelease = await _versionService.fetchLatestRelease();

      if (!mounted) return;
      setState(() => _latestRelease = latestRelease);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('gatewayUpdated', {
              'version': _installedVersion ?? latestRelease.version,
            }),
          ),
        ),
      );

      if (shouldRestart && mounted) {
        await provider.start();
      }
    } catch (e) {
      if (shouldRestart && mounted) {
        await provider.start();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('gatewayUpdateFailed', {'error': e})),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Consumer<GatewayProvider>(
      builder: (context, provider, _) {
        final state = provider.state;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.t('gatewayTitle'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _statusBadge(context, state.status, theme),
                  ],
                ),
                const SizedBox(height: 8),
                if (state.isRunning) ...[
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => WebDashboardScreen(
                                  url: state.dashboardUrl,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            state.dashboardUrl ?? AppConstants.gatewayUrl,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontFamily: 'DejaVuSansMono',
                              decoration: TextDecoration.underline,
                              decorationColor: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: l10n.t('gatewayCopyUrl'),
                        onPressed: () {
                          final url =
                              state.dashboardUrl ?? AppConstants.gatewayUrl;
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.t('gatewayUrlCopied')),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _buildVersionCard(theme, l10n, provider),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      state.errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (state.isStopped || state.status == GatewayStatus.error)
                      FilledButton.icon(
                        onPressed: () => provider.start(),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.t('gatewayStart')),
                      ),
                    if (state.status == GatewayStatus.starting)
                      FilledButton.icon(
                        onPressed: null,
                        icon: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        label: Text(l10n.t('gatewayStarting')),
                      ),
                    if (state.isRunning ||
                        state.status == GatewayStatus.stopping)
                      OutlinedButton.icon(
                        onPressed: state.status == GatewayStatus.stopping
                            ? null
                            : () => provider.stop(),
                        icon: state.status == GatewayStatus.stopping
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onSurface,
                                ),
                              )
                            : const Icon(Icons.stop),
                        label: Text(
                          state.status == GatewayStatus.stopping
                              ? l10n.t('gatewayStopping')
                              : l10n.t('gatewayStop'),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                      icon: const Icon(Icons.article_outlined),
                      label: Text(l10n.t('gatewayViewLogs')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVersionCard(
    ThemeData theme,
    AppLocalizations l10n,
    GatewayProvider provider,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface;
    final installedVersion = _loadingInstalledVersion
        ? '...'
        : _installedVersion ?? l10n.t('dashboardOpenclawVersionUnknown');
    final latestRelease = _latestRelease;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.integration_instructions_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('dashboardOpenclawVersionLabel'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  installedVersion,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'DejaVuSansMono',
                  ),
                ),
                if (latestRelease != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.t('gatewayLatestReleaseHint', {
                      'version': latestRelease.version,
                      'size': latestRelease.unpackedSizeLabel ??
                          AppConstants.openClawEstimatedSize,
                    }),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (latestRelease.nodeRequirement != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.t('gatewayNodeRequirementHint', {
                        'requirement': latestRelease.nodeRequirement,
                      }),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildVersionAction(theme, l10n, provider),
        ],
      ),
    );
  }

  Widget _buildVersionAction(
    ThemeData theme,
    AppLocalizations l10n,
    GatewayProvider provider,
  ) {
    if (_updating) {
      return FilledButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        label: Text(l10n.t('gatewayUpdating')),
      );
    }

    if (_checkingForUpdate) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        label: Text(l10n.t('gatewayCheckingUpdate')),
      );
    }

    if (_hasUpdateAvailable) {
      return FilledButton.icon(
        onPressed: provider.state.status == GatewayStatus.stopping
            ? null
            : () => _runUpdate(provider),
        icon: const Icon(Icons.system_update_alt),
        label: Text(l10n.t('gatewayUpdate')),
      );
    }

    if (_latestRelease != null) {
      return OutlinedButton.icon(
        onPressed: _checkForUpdates,
        icon: const Icon(Icons.verified_outlined),
        label: Text(l10n.t('gatewayLatest')),
      );
    }

    return OutlinedButton.icon(
      onPressed: _checkForUpdates,
      icon: const Icon(Icons.refresh),
      label: Text(l10n.t('gatewayCheckUpdate')),
    );
  }

  Widget _statusBadge(
    BuildContext context,
    GatewayStatus status,
    ThemeData theme,
  ) {
    final l10n = context.l10n;
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case GatewayStatus.running:
        color = AppColors.statusGreen;
        label = l10n.t('gatewayStatusRunning');
        icon = Icons.check_circle_outline;
      case GatewayStatus.starting:
        color = AppColors.statusAmber;
        label = l10n.t('gatewayStatusStarting');
        icon = Icons.hourglass_top;
      case GatewayStatus.stopping:
        color = AppColors.statusAmber;
        label = l10n.t('gatewayStatusStopping');
        icon = Icons.stop_circle_outlined;
      case GatewayStatus.error:
        color = AppColors.statusRed;
        label = l10n.t('gatewayStatusError');
        icon = Icons.error_outline;
      case GatewayStatus.stopped:
        color = AppColors.statusGrey;
        label = l10n.t('gatewayStatusStopped');
        icon = Icons.circle_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
