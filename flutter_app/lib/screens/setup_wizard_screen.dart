import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/openclaw_install_options.dart';
import '../models/setup_state.dart';
import '../providers/setup_provider.dart';
import '../services/backup_service.dart';
import '../services/bundled_sample_config_service.dart';
import '../services/install_status_message_formatter.dart';
import '../services/openclaw_version_service.dart';
import '../services/preferences_service.dart';
import '../services/provider_config_service.dart';
import '../services/snapshot_service.dart';
import '../widgets/progress_step.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

class SetupWizardScreen extends StatefulWidget {
  final bool resumeCompletionChoice;

  const SetupWizardScreen({
    super.key,
    this.resumeCompletionChoice = false,
  });

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final OpenClawVersionService _versionService = OpenClawVersionService();

  bool _started = false;
  bool _resolvingExistingSetupState = false;
  bool _didRestoreCompletedSetupState = false;
  List<OpenClawReleaseInfo> _availableReleases = const [];
  OpenClawReleaseInfo? _latestRelease;
  OpenClawReleaseInfo? _selectedRelease;
  bool _loadingReleaseOptions = false;
  String? _releaseOptionsError;

  @override
  void initState() {
    super.initState();
    _resolvingExistingSetupState = widget.resumeCompletionChoice;
    _loadOpenClawReleaseOptions();
    if (widget.resumeCompletionChoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreCompletedSetupState();
      });
    }
  }

  Future<void> _loadOpenClawReleaseOptions() async {
    if (mounted) {
      setState(() => _loadingReleaseOptions = true);
    }

    try {
      final latestRelease = await _versionService.fetchLatestRelease();
      List<OpenClawReleaseInfo> availableReleases;
      String? releaseOptionsError;
      try {
        availableReleases = await _versionService.fetchAvailableReleases();
      } catch (e) {
        availableReleases = [latestRelease];
        releaseOptionsError = '$e';
      }
      final mergedReleases =
          _mergeAvailableReleases(availableReleases, latestRelease);
      final preferredVersion = _selectedRelease?.version;
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
        _releaseOptionsError = releaseOptionsError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _releaseOptionsError = '$e';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingReleaseOptions = false);
      }
    }
  }

  Future<PreferencesService> _loadPrefs() async {
    final prefs = PreferencesService();
    await prefs.init();
    return prefs;
  }

  Future<void> _restoreCompletedSetupState() async {
    if (_didRestoreCompletedSetupState || !mounted) {
      return;
    }
    _didRestoreCompletedSetupState = true;

    try {
      await context.read<SetupProvider>().checkIfSetupNeeded();
    } finally {
      if (mounted) {
        setState(() => _resolvingExistingSetupState = false);
      }
    }
  }

  Future<void> _setPendingSetupChoice(bool value) async {
    final prefs = await _loadPrefs();
    prefs.pendingSetupCompletionChoice = value;
  }

  Future<void> _finishSetupFlow() async {
    final prefs = await _loadPrefs();
    prefs.pendingSetupCompletionChoice = false;
    prefs.setupComplete = true;
    prefs.isFirstRun = false;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const DashboardScreen(),
      ),
    );
  }

  Future<void> _completeIfGatewayConfigured() async {
    final gatewayConfigured =
        await ProviderConfigService.hasRequiredGatewayConfig();
    if (!mounted || !gatewayConfigured) {
      return;
    }

    await _finishSetupFlow();
  }

  Future<void> _beginSetup(SetupProvider provider) async {
    setState(() {
      _started = true;
    });
    await provider.runSetup(
      selectedOpenClawRelease: _selectedRelease ?? _latestRelease,
    );

    if (!mounted || !provider.state.isComplete) {
      return;
    }

    await _setPendingSetupChoice(true);
  }

  Future<void> _importSnapshotAndContinue() async {
    final l10n = context.l10n;
    try {
      final picked = await BackupService.pickBackupForRestore(
        emptyFileMessage: l10n.t('settingsSnapshotFileEmpty'),
        unsupportedFileMessage: l10n.t('settingsBackupUnsupportedFile'),
        invalidWorkspaceBackupMessage:
            l10n.t('settingsBackupInvalidWorkspaceArchive'),
      );
      if (picked == null || !mounted) {
        return;
      }

      final currentOpenClawVersion =
          await _versionService.readInstalledVersion();
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

      await picked.restore(restoreNodeEnabled: false);

      final gatewayConfigured =
          await ProviderConfigService.hasRequiredGatewayConfig();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('settingsSnapshotRestored', {'file': picked.fileName}),
          ),
        ),
      );

      if (gatewayConfigured) {
        await _finishSetupFlow();
        return;
      }

      await _goToOnboarding();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('settingsImportFailed', {'error': e})),
        ),
      );
    }
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

  Future<bool> _confirmSnapshotImportIfNeeded(
    SnapshotCompatibility compatibility,
  ) async {
    if (!compatibility.requiresConfirmation || !mounted) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      body: SafeArea(
        child: Consumer<SetupProvider>(
          builder: (context, provider, _) {
            final state = provider.state;
            final isResolvingCompletionChoice =
                _resolvingExistingSetupState && !state.isComplete;

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  Image.asset(
                    'assets/ic_launcher.png',
                    width: 64,
                    height: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.t('setupWizardTitle'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _started
                        ? l10n.t('setupWizardIntroRunning')
                        : l10n.t('setupWizardIntroIdle'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _buildSteps(state, l10n),
                  ),
                  if (isResolvingCompletionChoice)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (state.hasError) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline,
                                color: theme.colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  state.error ?? 'Unknown error',
                                  style: TextStyle(
                                      color:
                                          theme.colorScheme.onErrorContainer),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.isComplete)
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _handleConfigureApi,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(l10n.t('setupWizardConfigureApiKeys')),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _importSnapshotAndContinue,
                            icon: const Icon(Icons.download_done_outlined),
                            label: Text(l10n.t('settingsImportSnapshot')),
                          ),
                        ),
                      ],
                    )
                  else if (isResolvingCompletionChoice)
                    const SizedBox.shrink()
                  else if (!_started || state.hasError)
                    Column(
                      children: [
                        _buildVersionSelector(theme, l10n, provider.isRunning),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: provider.isRunning
                                ? null
                                : () => _beginSetup(provider),
                            icon: const Icon(Icons.download),
                            label: Text(
                              _started
                                  ? l10n.t('setupWizardRetry')
                                  : l10n.t('setupWizardBegin'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (!_started && !state.isComplete) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        l10n.t('setupWizardRequirements'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (!_started &&
                      !state.isComplete &&
                      _releaseOptionsError != null) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        l10n.t('gatewayVersionListFailed', {
                          'error': _releaseOptionsError,
                        }),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'by ${AppConstants.authorName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSteps(
    SetupState state,
    AppLocalizations l10n,
  ) {
    final steps = [
      (1, l10n.t('setupWizardStepDownloadRootfs'), SetupStep.downloadingRootfs),
      (2, l10n.t('setupWizardStepExtractRootfs'), SetupStep.extractingRootfs),
      (3, l10n.t('setupWizardStepInstallNode'), SetupStep.installingNode),
      (
        4,
        l10n.t('setupWizardStepInstallOpenClawWithSize', {
          'size': _selectedRelease?.unpackedSizeLabel ??
              _latestRelease?.unpackedSizeLabel ??
              AppConstants.openClawEstimatedSize,
        }),
        SetupStep.installingOpenClaw
      ),
      (
        5,
        l10n.t('setupWizardStepConfigureBypass'),
        SetupStep.configuringBypass
      ),
    ];

    return ListView(
      children: [
        for (final (num, label, step) in steps)
          ProgressStep(
            stepNumber: num,
            label: state.step == step
                ? _localizedSetupMessage(l10n, state.message)
                : label,
            detail: state.step == step
                ? _localizedSetupDetail(l10n, state.detail)
                : null,
            isActive: state.step == step,
            isComplete: state.stepNumber > step.index + 1 || state.isComplete,
            hasError: state.hasError && state.step == step,
            progress: state.step == step ? state.progress : null,
          ),
        if (state.isComplete) ...[
          ProgressStep(
            stepNumber: 6,
            label: l10n.t('setupWizardComplete'),
            isComplete: true,
          ),
        ],
      ],
    );
  }

  Widget _buildVersionSelector(
    ThemeData theme,
    AppLocalizations l10n,
    bool disableSelection,
  ) {
    final latestRelease = _latestRelease;
    final selectedRelease = _selectedRelease ?? latestRelease;
    final availableReleases = _availableReleases;
    final canSelectVersions =
        availableReleases.isNotEmpty && selectedRelease != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: canSelectVersions ? selectedRelease.version : null,
          decoration: InputDecoration(
            labelText: l10n.t('setupWizardSelectVersion'),
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: _loadingReleaseOptions
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: l10n.t('gatewayCheckUpdate'),
                    onPressed:
                        disableSelection ? null : _loadOpenClawReleaseOptions,
                    icon: const Icon(Icons.refresh),
                  ),
          ),
          items: availableReleases
              .map(
                (release) => DropdownMenuItem(
                  value: release.version,
                  child: Text(
                    _formatSetupReleaseLabel(
                      l10n,
                      release,
                      latestRelease,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: disableSelection || !canSelectVersions
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedRelease =
                        _findReleaseByVersion(availableReleases, value);
                  });
                },
        ),
        if (selectedRelease != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.t('setupWizardSelectedVersionHint', {
              'version': selectedRelease.version,
              'size': selectedRelease.unpackedSizeLabel ??
                  AppConstants.openClawEstimatedSize,
            }),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (selectedRelease.nodeRequirement != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.t('gatewayNodeRequirementHint', {
                'requirement': selectedRelease.nodeRequirement,
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
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

  String _formatSetupReleaseLabel(
    AppLocalizations l10n,
    OpenClawReleaseInfo release,
    OpenClawReleaseInfo? latestRelease,
  ) {
    return formatOpenClawReleaseLabel(
      l10n,
      release.version,
      latestVersion: latestRelease?.version,
    );
  }

  String _localizedSetupMessage(AppLocalizations l10n, String? message) {
    return InstallStatusMessageFormatter.localize(l10n, message);
  }

  String? _localizedSetupDetail(AppLocalizations l10n, String? detail) {
    return InstallStatusMessageFormatter.localizeDetail(l10n, detail);
  }

  bool get _isChineseLocale =>
      Localizations.localeOf(context).languageCode == 'zh';

  Future<void> _handleConfigureApi() async {
    final installedVersion = await _versionService.readInstalledVersion();
    final sample = await BundledSampleConfigService.loadForVersion(
      installedVersion,
    );

    if (!mounted || sample == null) {
      await _goToOnboarding();
      return;
    }

    final choice = await _showBundledSampleConfigDialog(sample.version);
    if (!mounted || choice == null) {
      return;
    }

    switch (choice) {
      case _BundledConfigChoice.useSample:
        await _applyBundledSampleConfig(sample);
        break;
      case _BundledConfigChoice.useTerminalOnboarding:
        await _goToOnboarding();
        break;
    }
  }

  Future<_BundledConfigChoice?> _showBundledSampleConfigDialog(
    String version,
  ) async {
    final isZh = _isChineseLocale;
    return showDialog<_BundledConfigChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isZh ? '发现内置示例配置' : 'Built-in sample config available',
        ),
        content: Text(
          isZh
              ? '检测到当前已安装的 OpenClaw 版本为 $version，并且应用内置了对应示例配置。\n\n使用示例配置后，可以跳过终端引导，直接进入首页；之后只需要去“AI 提供商”里把 Base URL、API Key 和模型改成你自己的即可。'
              : 'A built-in sample config is available for the installed OpenClaw version $version.\n\nIf you use it, you can skip terminal onboarding and go straight to the dashboard. Afterwards, just update the Base URL, API key, and model from the AI Providers page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.t('commonCancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_BundledConfigChoice.useTerminalOnboarding),
            child: Text(
              isZh ? '继续终端引导' : 'Use terminal onboarding',
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_BundledConfigChoice.useSample),
            child: Text(
              isZh ? '使用示例配置' : 'Use sample config',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyBundledSampleConfig(BundledSampleConfig sample) async {
    final isZh = _isChineseLocale;

    try {
      await BundledSampleConfigService.apply(sample);
      await ProviderConfigService.ensureGatewayDefaults();

      if (!mounted) return;

      final acknowledged = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            isZh ? '示例配置已套用' : 'Sample config applied',
          ),
          content: Text(
            isZh
                ? '已为 OpenClaw ${sample.version} 套用内置示例配置。\n\n接下来会直接进入首页。进入后请打开“AI 提供商”，把 Base URL、API Key、模型改成你自己的，再启动 Gateway。'
                : 'The built-in sample config for OpenClaw ${sample.version} has been applied.\n\nYou will go straight to the dashboard next. Open AI Providers there and replace the Base URL, API key, and model with your own values before starting the gateway.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                isZh ? '前往首页' : 'Go to dashboard',
              ),
            ),
          ],
        ),
      );

      if (acknowledged == true) {
        await _finishSetupFlow();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isZh
                ? '套用内置示例配置失败，已回退到终端引导：$e'
                : 'Failed to apply the built-in sample config. Falling back to terminal onboarding: $e',
          ),
        ),
      );
      await _goToOnboarding();
    }
  }

  Future<void> _goToOnboarding() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OnboardingScreen(),
      ),
    );

    if (!mounted) return;
    await _completeIfGatewayConfigured();
  }
}

enum _BundledConfigChoice {
  useSample,
  useTerminalOnboarding,
}
