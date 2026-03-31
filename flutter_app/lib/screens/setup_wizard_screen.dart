import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/setup_state.dart';
import '../models/optional_package.dart';
import '../providers/setup_provider.dart';
import '../services/cpolar_package_service.dart';
import '../services/openclaw_version_service.dart';
import '../services/package_service.dart';
import '../services/preferences_service.dart';
import '../services/provider_config_service.dart';
import '../services/snapshot_service.dart';
import '../widgets/progress_step.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';
import 'package_install_screen.dart';

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
  Map<String, bool> _pkgStatuses = {};
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

  Future<void> _refreshPkgStatuses() async {
    final statuses = await PackageService.checkAllStatuses();
    if (mounted) setState(() => _pkgStatuses = statuses);
  }

  Future<void> _installPackage(OptionalPackage package) async {
    if (package.id == 'cpolar') {
      await _installCpolarPackage();
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PackageInstallScreen(package: package),
      ),
    );
    if (result == true) _refreshPkgStatuses();
  }

  Future<void> _installCpolarPackage() async {
    final l10n = context.l10n;
    NavigatorState? dialogNavigator;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogNavigator = Navigator.of(ctx);
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text('${l10n.t('packagesInstall')} cpolar...'),
              ),
            ],
          ),
        );
      },
    );

    try {
      await CpolarPackageService.installOrUpdateLatest();
      if (dialogNavigator != null) {
        dialogNavigator!.pop();
      }
      await _refreshPkgStatuses();
    } catch (e) {
      if (dialogNavigator != null) {
        dialogNavigator!.pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('packageCpolarOperationFailed', {'error': e.toString()}),
          ),
        ),
      );
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
      final picked = await SnapshotService.pickSnapshotForRestore(
        emptyFileMessage: l10n.t('settingsSnapshotFileEmpty'),
      );
      if (picked == null || !mounted) {
        return;
      }

      final currentOpenClawVersion =
          await _versionService.readInstalledVersion();
      final compatibility = SnapshotService.analyzeCompatibility(
        picked.snapshot,
        currentAppVersion: AppConstants.version,
        currentOpenClawVersion: currentOpenClawVersion,
      );
      final shouldContinue =
          await _confirmSnapshotImportIfNeeded(compatibility);
      if (!shouldContinue) {
        return;
      }

      await SnapshotService.restoreSnapshot(
        picked.snapshot,
        restoreNodeEnabled: false,
      );

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
    final isDark = theme.brightness == Brightness.dark;
    final l10n = context.l10n;

    return Scaffold(
      body: SafeArea(
        child: Consumer<SetupProvider>(
          builder: (context, provider, _) {
            final state = provider.state;
            final isResolvingCompletionChoice =
                _resolvingExistingSetupState && !state.isComplete;

            // Load package statuses once setup completes
            if (state.isComplete && _pkgStatuses.isEmpty) {
              _refreshPkgStatuses();
            }

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
                    child: _buildSteps(state, theme, isDark, l10n),
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
                            onPressed: _goToOnboarding,
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
    ThemeData theme,
    bool isDark,
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
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.t('setupWizardOptionalPackages'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final pkg in OptionalPackage.all)
            _buildPackageTile(theme, l10n, pkg, isDark),
        ],
      ],
    );
  }

  Widget _buildPackageTile(
    ThemeData theme,
    AppLocalizations l10n,
    OptionalPackage package,
    bool isDark,
  ) {
    final installed = _pkgStatuses[package.id] ?? false;
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(package.icon,
              color: theme.colorScheme.onSurfaceVariant, size: 22),
        ),
        title: Row(
          children: [
            Text(package.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (installed) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.statusGreen.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(l10n.t('commonInstalled'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.statusGreen,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ],
          ],
        ),
        subtitle: Text(
            '${_packageDescription(l10n, package)} (${package.estimatedSize})'),
        trailing: installed
            ? const Icon(Icons.check_circle, color: AppColors.statusGreen)
            : OutlinedButton(
                onPressed: () => _installPackage(package),
                child: Text(l10n.t('packagesInstall')),
              ),
      ),
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
          value: canSelectVersions ? selectedRelease.version : null,
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
                    release.version == latestRelease?.version
                        ? '${release.version} (${l10n.t('gatewayLatest')})'
                        : release.version,
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

  String _localizedSetupMessage(AppLocalizations l10n, String? message) {
    if (message == null || message.isEmpty) {
      return '';
    }

    final downloadProgress =
        RegExp(r'^Downloading: ([0-9.]+) MB / ([0-9.]+) MB$')
            .firstMatch(message);
    if (downloadProgress != null) {
      return l10n.t('setupWizardStatusDownloadingProgress', {
        'current': downloadProgress.group(1),
        'total': downloadProgress.group(2),
      });
    }

    final nodeDownloadProgress =
        RegExp(r'^Downloading Node\.js: ([0-9.]+) MB / ([0-9.]+) MB$')
            .firstMatch(message);
    if (nodeDownloadProgress != null) {
      return l10n.t('setupWizardStatusDownloadingNodeProgress', {
        'current': nodeDownloadProgress.group(1),
        'total': nodeDownloadProgress.group(2),
      });
    }

    final nodeVersionMatch =
        RegExp(r'^Downloading Node\.js (.+)\.\.\.$').firstMatch(message);
    if (nodeVersionMatch != null) {
      return l10n.t('setupWizardStatusDownloadingNode', {
        'version': nodeVersionMatch.group(1),
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
      case 'Extracting Node.js...':
        return l10n.t('setupWizardStatusExtractingNode');
      case 'Verifying Node.js...':
        return l10n.t('setupWizardStatusVerifyingNode');
      case 'Node.js installed':
        return l10n.t('setupWizardStatusNodeInstalled');
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
      default:
        return message;
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
