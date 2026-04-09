import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/gateway_state.dart';
import '../models/openclaw_install_options.dart';
import '../providers/gateway_provider.dart';
import '../screens/logs_screen.dart';
import '../screens/web_dashboard_screen.dart';
import '../services/dashboard_url_resolver.dart';
import '../services/install_status_message_formatter.dart';
import '../services/openclaw_version_service.dart';

class GatewayControls extends StatefulWidget {
  const GatewayControls({
    super.key,
    this.activeModel,
    this.isLoadingActiveModel = false,
  });

  final String? activeModel;
  final bool isLoadingActiveModel;

  @override
  State<GatewayControls> createState() => _GatewayControlsState();
}

class _GatewayControlsState extends State<GatewayControls> {
  final _versionService = OpenClawVersionService();

  String? _installedVersion;
  OpenClawReleaseInfo? _latestRelease;
  OpenClawReleaseInfo? _selectedRelease;
  List<OpenClawReleaseInfo> _availableReleases = const [];
  bool _loadingInstalledVersion = true;
  bool _loadingReleaseOptions = false;
  bool _updating = false;
  double? _installProgress;
  String _installStatusMessage = '';
  String? _installStatusDetail;

  @override
  void initState() {
    super.initState();
    _initializeVersionCard();
  }

  @override
  void dispose() => super.dispose();

  Future<void> _initializeVersionCard() async {
    await _refreshInstalledVersion();
    await _loadReleaseOptions();
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

  Future<void> _loadReleaseOptions() async {
    if (_loadingReleaseOptions) return;

    setState(() => _loadingReleaseOptions = true);
    try {
      final latestRelease = await _versionService.fetchLatestRelease();
      List<OpenClawReleaseInfo> availableReleases;
      Object? releaseOptionsError;
      try {
        availableReleases = await _versionService.fetchAvailableReleases();
      } catch (e) {
        availableReleases = [latestRelease];
        releaseOptionsError = e;
      }
      final mergedReleases =
          _mergeAvailableReleases(availableReleases, latestRelease);
      final preferredVersion = _selectedRelease?.version ?? _installedVersion;
      final selectedRelease =
          _findReleaseByVersion(mergedReleases, preferredVersion) ??
              _findReleaseByVersion(
                mergedReleases,
                defaultRecommendedOpenClawReleaseVersion,
              ) ??
              _findReleaseByVersion(mergedReleases, latestRelease.version) ??
              latestRelease;

      if (!mounted) return;
      setState(() {
        _latestRelease = latestRelease;
        _availableReleases = mergedReleases;
        _selectedRelease = selectedRelease;
      });

      if (releaseOptionsError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t('gatewayVersionListFailed', {
                'error': releaseOptionsError,
              }),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('gatewayVersionListFailed', {'error': e}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingReleaseOptions = false);
      }
    }
  }

  Future<void> _installSelectedRelease(GatewayProvider provider) async {
    final selectedRelease = _selectedRelease ?? _latestRelease;
    if (_updating || _loadingReleaseOptions || selectedRelease == null) return;
    final l10n = context.l10n;

    if (OpenClawVersionService.isSameVersion(
      installedVersion: _installedVersion,
      targetVersion: selectedRelease.version,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('gatewaySelectedVersionAlreadyInstalled', {
              'version': selectedRelease.version,
            }),
          ),
        ),
      );
      return;
    }

    final confirmed = await _confirmInstallSelectedRelease(selectedRelease);
    if (!confirmed || !mounted) {
      return;
    }

    final shouldRestart = provider.state.isRunning ||
        provider.state.status == GatewayStatus.starting;

    _startInstallProgress();
    setState(() => _updating = true);
    try {
      _setInstallProgress(
        0.08,
        message: 'Preparing installation...',
        detail: '',
      );
      if (provider.state.status != GatewayStatus.stopped) {
        _setInstallProgress(0.18, message: 'Stopping gateway...', detail: '');
        await provider.stop();
      }

      await _versionService.installVersion(
        selectedRelease.version,
        releaseInfo: selectedRelease,
        onProgress: (progress) {
          _setInstallProgress(
            0.30 + (progress.progress * 0.62),
            message: progress.message,
            detail: progress.detail,
          );
        },
      );
      _setInstallProgress(
        0.95,
        message: 'Refreshing installed version...',
        detail: '',
      );
      await _refreshInstalledVersion(showLoading: false);
      await _loadReleaseOptions();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('gatewayAppliedVersion', {
              'version': _installedVersion ?? selectedRelease.version,
            }),
          ),
        ),
      );

      if (shouldRestart && mounted) {
        _setInstallProgress(0.98, message: 'Restarting gateway...', detail: '');
        await provider.start();
      }
      await _completeInstallProgress();
    } catch (e) {
      if (shouldRestart && mounted) {
        _setInstallProgress(0.97, message: 'Restarting gateway...', detail: '');
        await provider.start();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('gatewayApplyVersionFailed', {'error': e}),
          ),
        ),
      );
    } finally {
      _stopInstallProgress(reset: true);
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<bool> _confirmInstallSelectedRelease(
    OpenClawReleaseInfo selectedRelease,
  ) async {
    final l10n = context.l10n;
    final currentVersion = _installedVersion?.trim().isNotEmpty == true
        ? _installedVersion!.trim()
        : l10n.t('dashboardOpenclawVersionUnknown');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('gatewayInstallVersionConfirmTitle')),
        content: Text(
          l10n.t('gatewayInstallVersionConfirmBody', {
            'current': currentVersion,
            'selected': selectedRelease.version,
          }),
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

  void _startInstallProgress() {
    if (!mounted) {
      return;
    }
    setState(() {
      _installProgress = 0.03;
      _installStatusMessage = 'Preparing installation...';
      _installStatusDetail = null;
    });
  }

  void _setInstallProgress(double value, {String? message, String? detail}) {
    if (!mounted) {
      return;
    }
    setState(() {
      final current = _installProgress ?? 0.0;
      _installProgress = value > current ? value : current;
      if (message != null && message.trim().isNotEmpty) {
        _installStatusMessage = message.trim();
      }
      if (detail != null) {
        final trimmed = detail.trim();
        _installStatusDetail = trimmed.isEmpty ? null : trimmed;
      }
    });
  }

  Future<void> _completeInstallProgress() async {
    if (!mounted) {
      return;
    }
    setState(() => _installProgress = 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void _stopInstallProgress({bool reset = false}) {
    if (reset && mounted) {
      setState(() {
        _installProgress = null;
        _installStatusMessage = '';
        _installStatusDetail = null;
      });
    }
  }

  String _installProgressText() {
    final progress = _installProgress;
    if (progress == null) {
      return '0%';
    }
    return '${(progress * 100).clamp(0, 100).round()}%';
  }

  String _localizedInstallStatus(AppLocalizations l10n) {
    return InstallStatusMessageFormatter.localize(l10n, _installStatusMessage);
  }

  String? _localizedInstallDetail(AppLocalizations l10n) {
    return InstallStatusMessageFormatter.localizeDetail(
      l10n,
      _installStatusDetail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Consumer<GatewayProvider>(
      builder: (context, provider, _) {
        final state = provider.state;
        final dashboardUrl = DashboardUrlResolver.normalizeDashboardUrl(
              state.dashboardUrl,
              baseUri: Uri.parse(AppConstants.gatewayUrl),
            ) ??
            AppConstants.gatewayUrl;

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
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => WebDashboardScreen(
                                  url: dashboardUrl,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            await provider.syncState();
                          },
                          child: Text(
                            dashboardUrl,
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
                          Clipboard.setData(ClipboardData(text: dashboardUrl));
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
                _buildCurrentModelBanner(theme, l10n),
                const SizedBox(height: 12),
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

  Widget _buildCurrentModelBanner(ThemeData theme, AppLocalizations l10n) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface;
    final modelName = widget.isLoadingActiveModel
        ? '...'
        : widget.activeModel ?? l10n.t('dashboardCurrentModelUnknown');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.memory_outlined,
              size: 15,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.t('dashboardCurrentModelLabel'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              modelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFamily: 'DejaVuSansMono',
              ),
            ),
          ),
        ],
      ),
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
    final selectedRelease = _selectedRelease ?? latestRelease;
    final isSelectedVersionInstalled = OpenClawVersionService.isSameVersion(
      installedVersion: _installedVersion,
      targetVersion: selectedRelease?.version,
    );
    final installedVersionStatus = _buildInstalledVersionStatus(
      theme,
      l10n,
      installedVersion: _installedVersion,
      latestRelease: latestRelease,
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.integration_instructions_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('dashboardOpenclawVersionLabel'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      installedVersion,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'DejaVuSansMono',
                      ),
                    ),
                    if (installedVersionStatus != null) ...[
                      const SizedBox(height: 6),
                      installedVersionStatus,
                    ],
                    if (latestRelease != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.t('gatewayLatestReleaseHint', {
                          'version': latestRelease.version,
                          'size': latestRelease.unpackedSizeLabel ??
                              AppConstants.openClawEstimatedSize,
                        }),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedRelease?.version,
            decoration: InputDecoration(
              labelText: l10n.t('gatewaySelectVersion'),
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: _availableReleases
                .map(
                  (release) => DropdownMenuItem(
                    value: release.version,
                    child: Text(
                      _formatReleaseLabel(release, l10n),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _updating || _loadingReleaseOptions
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedRelease =
                          _findReleaseByVersion(_availableReleases, value);
                    });
                  },
          ),
          if (selectedRelease != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.t('gatewaySelectedReleaseHint', {
                'version': selectedRelease.version,
                'size': selectedRelease.unpackedSizeLabel ??
                    AppConstants.openClawEstimatedSize,
              }),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.2,
              ),
            ),
            if (selectedRelease.nodeRequirement != null) ...[
              const SizedBox(height: 2),
              Text(
                l10n.t('gatewayNodeRequirementHint', {
                  'requirement': selectedRelease.nodeRequirement,
                }),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
            ],
            if (isSelectedVersionInstalled) ...[
              const SizedBox(height: 6),
              Text(
                l10n.t('gatewaySelectedVersionAlreadyInstalled', {
                  'version': selectedRelease.version,
                }),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.statusGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildVersionRefreshAction(theme, l10n),
              _buildVersionAction(theme, l10n, provider, selectedRelease),
            ],
          ),
          if (_updating && _installProgress != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: _installProgress),
                ),
                const SizedBox(width: 10),
                Text(
                  _installProgressText(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'DejaVuSansMono',
                  ),
                ),
              ],
            ),
            if (_localizedInstallStatus(l10n).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _localizedInstallStatus(l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((_localizedInstallDetail(l10n) ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _localizedInstallDetail(l10n)!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'DejaVuSansMono',
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget? _buildInstalledVersionStatus(
    ThemeData theme,
    AppLocalizations l10n, {
    required String? installedVersion,
    required OpenClawReleaseInfo? latestRelease,
  }) {
    final latestVersion = latestRelease?.version;
    final normalizedInstalled = installedVersion?.trim();
    if (latestVersion == null ||
        normalizedInstalled == null ||
        normalizedInstalled.isEmpty) {
      return null;
    }

    late final Color color;
    late final String label;
    if (OpenClawVersionService.isUpdateAvailable(
      installedVersion: normalizedInstalled,
      latestVersion: latestVersion,
    )) {
      color = AppColors.statusAmber;
      label = l10n.t('gatewayVersionUpdatable');
    } else {
      color = AppColors.statusGreen;
      label = l10n.t('gatewayVersionCurrent');
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  ButtonStyle _buildCompactOutlinedButtonStyle(ThemeData theme) {
    return OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  ButtonStyle _buildCompactFilledButtonStyle(ThemeData theme) {
    return FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildVersionAction(
    ThemeData theme,
    AppLocalizations l10n,
    GatewayProvider provider,
    OpenClawReleaseInfo? selectedRelease,
  ) {
    if (_updating) {
      return FilledButton.icon(
        style: _buildCompactFilledButtonStyle(theme),
        onPressed: null,
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        label: Text(
            '${l10n.t('gatewayApplyingVersion')} ${_installProgressText()}'),
      );
    }

    final isSelectedVersionInstalled = OpenClawVersionService.isSameVersion(
      installedVersion: _installedVersion,
      targetVersion: selectedRelease?.version,
    );

    return FilledButton.icon(
      style: _buildCompactFilledButtonStyle(theme),
      onPressed: provider.state.status == GatewayStatus.stopping ||
              selectedRelease == null ||
              isSelectedVersionInstalled
          ? null
          : () => _installSelectedRelease(provider),
      icon: Icon(
        isSelectedVersionInstalled
            ? Icons.check_circle_outline
            : Icons.system_update_alt,
        size: 16,
      ),
      label: Text(
        isSelectedVersionInstalled
            ? l10n.t('gatewaySelectedVersionCurrent')
            : l10n.t('gatewayInstallSelectedVersion'),
      ),
    );
  }

  Widget _buildVersionRefreshAction(
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    if (_loadingReleaseOptions) {
      return OutlinedButton.icon(
        style: _buildCompactOutlinedButtonStyle(theme),
        onPressed: null,
        icon: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        label: Text(l10n.t('gatewayCheckingUpdate')),
      );
    }

    return OutlinedButton.icon(
      style: _buildCompactOutlinedButtonStyle(theme),
      onPressed: _loadReleaseOptions,
      icon: const Icon(Icons.refresh, size: 16),
      label: Text(l10n.t('gatewayCheckUpdate')),
    );
  }

  List<OpenClawReleaseInfo> _mergeAvailableReleases(
    List<OpenClawReleaseInfo> releases,
    OpenClawReleaseInfo latestRelease,
  ) {
    final releasesByVersion = <String, OpenClawReleaseInfo>{
      for (final release in releases) release.version: release,
      latestRelease.version: latestRelease,
    };

    final merged = releasesByVersion.values.toList()
      ..sort((a, b) => OpenClawVersionService.compareVersions(
            b.version,
            a.version,
          ));
    return merged;
  }

  OpenClawReleaseInfo? _findReleaseByVersion(
    List<OpenClawReleaseInfo> releases,
    String? version,
  ) {
    if (version == null || version.trim().isEmpty) {
      return null;
    }

    for (final release in releases) {
      if (release.version == version) {
        return release;
      }
    }
    return null;
  }

  String _formatReleaseLabel(
    OpenClawReleaseInfo release,
    AppLocalizations l10n,
  ) {
    return formatOpenClawReleaseLabel(
      l10n,
      release.version,
      latestVersion: _latestRelease?.version,
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
