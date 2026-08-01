import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/openclaw_install_options.dart';
import '../models/openclaw_version_policy.dart';
import '../models/setup_state.dart';
import '../providers/setup_provider.dart';
import '../services/backup_service.dart';
import '../services/install_status_message_formatter.dart';
import '../services/native_bridge.dart';
import '../services/openclaw_version_service.dart';
import '../services/preferences_service.dart';
import '../services/provider_config_service.dart';
import '../services/snapshot_service.dart';
import '../widgets/progress_step.dart';
import 'dashboard_screen.dart';

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
  bool _finalizingSetup = false;
  bool _resolvingExistingSetupState = false;
  bool _didRestoreCompletedSetupState = false;
  List<OpenClawReleaseInfo> _availableReleases = const [];
  OpenClawReleaseInfo? _latestRelease;
  OpenClawReleaseInfo? _selectedRelease;
  bool _loadingReleaseOptions = false;
  String? _releaseOptionsError;
  final TextEditingController _prebuiltRootfsUrlController =
      TextEditingController();
  final TextEditingController _ubuntuRootfsUrlController =
      TextEditingController();
  final TextEditingController _nodeArchiveUrlController =
      TextEditingController();
  String? _selectedPrebuiltRootfsArchivePath;
  String? _selectedPrebuiltRootfsArchiveName;
  String? _selectedUbuntuRootfsArchivePath;
  String? _selectedUbuntuRootfsArchiveName;
  String? _selectedNodeArchivePath;
  String? _selectedNodeArchiveName;

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

  @override
  void dispose() {
    _prebuiltRootfsUrlController.dispose();
    _ubuntuRootfsUrlController.dispose();
    _nodeArchiveUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadOpenClawReleaseOptions() async {
    if (mounted) {
      setState(() => _loadingReleaseOptions = true);
    }

    try {
      final prefs = await _loadPrefs();
      final catalog = await _versionService.loadReleaseCatalog();
      final showPrereleases = prefs.showPrereleaseVersions;
      final availableReleases = catalog.releases
          .where(
            (release) => OpenClawReleasePolicy.isVisibleInPicker(
              release.version,
              showPrereleases: showPrereleases,
            ),
          )
          .toList(growable: false);
      final preferredVersion = _selectedRelease?.version;
      final selectedRelease =
          _findReleaseByVersion(availableReleases, preferredVersion) ??
              catalog.stableRelease;

      if (!mounted) return;
      setState(() {
        _latestRelease = showPrereleases ||
                catalog.experimentalRelease == null ||
                !OpenClawReleasePolicy.isPrerelease(
                  catalog.experimentalRelease!.version,
                )
            ? catalog.experimentalRelease
            : null;
        _availableReleases = availableReleases;
        _selectedRelease = selectedRelease;
        _releaseOptionsError = catalog.warning;
      });
    } catch (e) {
      if (!mounted) return;
      final fallbackCatalog = OpenClawVersionService.buildReleaseCatalog(
        availableReleases: const [],
        latestRelease: null,
        arch: 'aarch64',
        warning: '$e',
        hasOnlineMetadata: false,
      );
      setState(() {
        _latestRelease = null;
        _availableReleases = fallbackCatalog.releases;
        _selectedRelease = fallbackCatalog.stableRelease;
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
      final setupNeeded =
          await context.read<SetupProvider>().checkIfSetupNeeded();
      if (!setupNeeded && mounted) {
        await _completeSetupWithAppDefaults();
      }
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

  Future<void> _completeSetupWithAppDefaults() async {
    if (_finalizingSetup) return;

    setState(() => _finalizingSetup = true);
    try {
      await ProviderConfigService.ensureInitialAppConfig();
      await _finishSetupFlow();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'setupWizardBaseConfigFailed',
              {'error': '$error'},
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _finalizingSetup = false);
      }
    }
  }

  Future<void> _beginSetup(SetupProvider provider) async {
    final l10n = context.l10n;
    if (_selectedRelease?.nodeValidationStatus ==
        OpenClawNodeValidationStatus.unsupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('openClawNodeRuntimeUnsupported'))),
      );
      return;
    }
    final prebuiltRootfsUrl = _prebuiltRootfsUrlController.text.trim();
    final ubuntuRootfsUrl = _ubuntuRootfsUrlController.text.trim();
    final nodeArchiveUrl = _nodeArchiveUrlController.text.trim();

    if (!_validateOptionalBootstrapUrl(
      url: prebuiltRootfsUrl,
      localPath: _selectedPrebuiltRootfsArchivePath,
      label: l10n.t('setupWizardBootstrapPrebuiltRootfsTitle'),
    )) {
      return;
    }
    if (!_validateOptionalBootstrapUrl(
      url: ubuntuRootfsUrl,
      localPath: _selectedUbuntuRootfsArchivePath,
      label: l10n.t('setupWizardBootstrapUbuntuRootfsTitle'),
    )) {
      return;
    }
    if (!_validateOptionalBootstrapUrl(
      url: nodeArchiveUrl,
      localPath: _selectedNodeArchivePath,
      label: l10n.t('setupWizardBootstrapNodeTitle'),
    )) {
      return;
    }

    setState(() {
      _started = true;
    });
    await provider.runSetup(
      selectedOpenClawRelease: _selectedRelease ?? _latestRelease,
      installOptions: OpenClawInstallOptions(
        prebuiltRootfsUrl: _selectedPrebuiltRootfsArchivePath == null
            ? prebuiltRootfsUrl
            : null,
        prebuiltRootfsArchivePath: _selectedPrebuiltRootfsArchivePath,
        ubuntuRootfsUrl:
            _selectedUbuntuRootfsArchivePath == null ? ubuntuRootfsUrl : null,
        ubuntuRootfsArchivePath: _selectedUbuntuRootfsArchivePath,
        nodeArchiveUrl:
            _selectedNodeArchivePath == null ? nodeArchiveUrl : null,
        nodeArchivePath: _selectedNodeArchivePath,
      ),
    );

    if (!mounted || !provider.state.isComplete) {
      return;
    }

    await _setPendingSetupChoice(true);
    if (!mounted) return;
    await _completeSetupWithAppDefaults();
  }

  bool _validateOptionalBootstrapUrl({
    required String url,
    required String? localPath,
    required String label,
  }) {
    if (localPath != null || url.isEmpty || _isValidHttpUrl(url)) {
      return true;
    }

    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.t('setupWizardBootstrapInvalidUrl', {'label': label}),
        ),
      ),
    );
    return false;
  }

  bool _isValidHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  _BootstrapResourceConfig _currentBootstrapResourceConfig() {
    return _BootstrapResourceConfig(
      prebuiltRootfsUrl: _prebuiltRootfsUrlController.text.trim(),
      prebuiltRootfsArchivePath: _selectedPrebuiltRootfsArchivePath,
      prebuiltRootfsArchiveName: _selectedPrebuiltRootfsArchiveName,
      ubuntuRootfsUrl: _ubuntuRootfsUrlController.text.trim(),
      ubuntuRootfsArchivePath: _selectedUbuntuRootfsArchivePath,
      ubuntuRootfsArchiveName: _selectedUbuntuRootfsArchiveName,
      nodeArchiveUrl: _nodeArchiveUrlController.text.trim(),
      nodeArchivePath: _selectedNodeArchivePath,
      nodeArchiveName: _selectedNodeArchiveName,
    );
  }

  void _applyBootstrapResourceConfig(_BootstrapResourceConfig config) {
    _prebuiltRootfsUrlController.text = config.prebuiltRootfsUrl;
    _ubuntuRootfsUrlController.text = config.ubuntuRootfsUrl;
    _nodeArchiveUrlController.text = config.nodeArchiveUrl;
    _selectedPrebuiltRootfsArchivePath = config.prebuiltRootfsArchivePath;
    _selectedPrebuiltRootfsArchiveName = config.prebuiltRootfsArchiveName;
    _selectedUbuntuRootfsArchivePath = config.ubuntuRootfsArchivePath;
    _selectedUbuntuRootfsArchiveName = config.ubuntuRootfsArchiveName;
    _selectedNodeArchivePath = config.nodeArchivePath;
    _selectedNodeArchiveName = config.nodeArchiveName;
  }

  bool get _hasBootstrapResourceConfig =>
      _prebuiltRootfsUrlController.text.trim().isNotEmpty ||
      _ubuntuRootfsUrlController.text.trim().isNotEmpty ||
      _nodeArchiveUrlController.text.trim().isNotEmpty ||
      (_selectedPrebuiltRootfsArchivePath ?? '').trim().isNotEmpty ||
      (_selectedUbuntuRootfsArchivePath ?? '').trim().isNotEmpty ||
      (_selectedNodeArchivePath ?? '').trim().isNotEmpty;

  Future<void> _openBootstrapResourceConfig() async {
    final result = await Navigator.of(context).push<_BootstrapResourceConfig>(
      MaterialPageRoute(
        builder: (_) => _BootstrapResourceConfigScreen(
          initialConfig: _currentBootstrapResourceConfig(),
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() => _applyBootstrapResourceConfig(result));
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
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('settingsSnapshotRestored', {'file': picked.fileName}),
          ),
        ),
      );

      await _completeSetupWithAppDefaults();
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
            final showIdleLayout = !_started &&
                !state.isComplete &&
                !state.hasError &&
                !isResolvingCompletionChoice;

            if (showIdleLayout) {
              return _buildIdleSetupLayout(theme, l10n, provider);
            }

            if (_started && provider.isRunning && !state.hasError) {
              return _buildRunningSetupLayout(theme, l10n, state, provider);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSetupHeader(theme, l10n, isRunning: _started),
                  const SizedBox(height: 18),
                  if (_started || state.isComplete || state.hasError)
                    Expanded(child: _buildSteps(state, l10n))
                  else
                    _buildSteps(state, l10n),
                  if (isResolvingCompletionChoice)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (state.hasError) ...[
                    const SizedBox(height: 10),
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
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  state.error ?? l10n.t('commonUnknown'),
                                  style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (state.isComplete) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _finalizingSetup
                            ? null
                            : _completeSetupWithAppDefaults,
                        icon: _finalizingSetup
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.home_outlined),
                        label: Text(
                          l10n.t('setupWizardSampleConfigGoDashboard'),
                        ),
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
                  ] else if (!isResolvingCompletionChoice &&
                      (!_started || state.hasError)) ...[
                    _buildVersionSelector(theme, l10n, provider.isRunning),
                    const SizedBox(height: 10),
                    _buildBootstrapResourceConfigButton(
                      theme,
                      l10n,
                      provider.isRunning,
                    ),
                    const SizedBox(height: 12),
                    _buildInstallButton(
                      theme,
                      label: _started
                          ? l10n.t('setupWizardRetry')
                          : l10n.t('setupWizardBegin'),
                      onPressed: provider.isRunning
                          ? null
                          : () => _beginSetup(provider),
                    ),
                  ],
                  if (!_started && !state.isComplete) ...[
                    const SizedBox(height: 10),
                    _buildSetupRequirement(theme, l10n),
                  ],
                  const SizedBox(height: 10),
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

  Widget _buildRunningSetupLayout(
    ThemeData theme,
    AppLocalizations l10n,
    SetupState state,
    SetupProvider provider,
  ) {
    final completedSteps = (state.stepNumber - 1).clamp(0, 5);
    final overallProgress =
        ((completedSteps + state.progress.clamp(0.0, 1.0)) / 5).clamp(0.0, 1.0);
    final version = _selectedRelease?.version ??
        _latestRelease?.version ??
        l10n.t('commonUnknown');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSetupHeader(theme, l10n, isRunning: true),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildRunningSummaryCard(
                    theme,
                    l10n,
                    state,
                    overallProgress,
                    version,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: theme.brightness == Brightness.light
                          ? const [
                              BoxShadow(
                                color: Color(0x0B000000),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    child: _buildSteps(state, l10n, embedded: true),
                  ),
                  const SizedBox(height: 12),
                  _buildRunningTip(theme, l10n),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmStopSetup(l10n, provider),
                  icon: const Icon(Icons.stop_circle_outlined, size: 19),
                  label: Text(l10n.t('setupWizardStop')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showSetupRunningHelp(l10n),
                  icon: const Icon(Icons.help_outline_rounded, size: 19),
                  label: Text(l10n.t('setupWizardInstallHelp')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
  }

  Widget _buildRunningSummaryCard(
    ThemeData theme,
    AppLocalizations l10n,
    SetupState state,
    double overallProgress,
    String version,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('setupWizardOverallProgress'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${(overallProgress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: overallProgress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildRunningMetric(
                  theme,
                  Icons.layers_outlined,
                  l10n.t('setupWizardCurrentStage'),
                  '${state.stepNumber.clamp(1, 5)} / 5',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRunningMetric(
                  theme,
                  Icons.smart_toy_outlined,
                  l10n.t('setupWizardInstallingVersion'),
                  version,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRunningMetric(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRunningTip(ThemeData theme, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            color: theme.colorScheme.primary,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.t('setupWizardRunningTip'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetupRunningHelp(AppLocalizations l10n) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('setupWizardInstallHelpTitle')),
        content: Text(l10n.t('setupWizardInstallHelpBody')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.t('commonDone')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmStopSetup(
    AppLocalizations l10n,
    SetupProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('setupWizardStopConfirmTitle')),
        content: Text(l10n.t('setupWizardStopConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.t('setupWizardStopAction')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await provider.cancelSetup();
    if (mounted) {
      setState(() => _started = false);
    }
  }

  Widget _buildIdleSetupLayout(
    ThemeData theme,
    AppLocalizations l10n,
    SetupProvider provider,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSetupHeader(theme, l10n, isRunning: false),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildSteps(provider.state, l10n),
                  const SizedBox(height: 12),
                  _buildVersionSelector(theme, l10n, provider.isRunning),
                  const SizedBox(height: 12),
                  _buildBootstrapResourceConfigButton(
                    theme,
                    l10n,
                    provider.isRunning,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildInstallButton(
            theme,
            label: l10n.t('setupWizardBegin'),
            onPressed: provider.isRunning ? null : () => _beginSetup(provider),
          ),
          const SizedBox(height: 10),
          _buildSetupRequirement(theme, l10n),
          const SizedBox(height: 10),
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
  }

  Widget _buildSetupHeader(
    ThemeData theme,
    AppLocalizations l10n, {
    required bool isRunning,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Image.asset('assets/ic_launcher.png'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('setupWizardTitle'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                isRunning
                    ? l10n.t('setupWizardIntroRunning')
                    : l10n.t('setupWizardIntroIdle'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetupRequirement(ThemeData theme, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.storage_outlined,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l10n.t('setupWizardRequirements'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSteps(
    SetupState state,
    AppLocalizations l10n, {
    bool embedded = false,
  }) {
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

    final stepWidgets = <Widget>[
      for (final (index, stepData) in steps.indexed)
        ProgressStep(
          stepNumber: stepData.$1,
          label: state.step == stepData.$3
              ? _localizedSetupMessage(l10n, state.message)
              : stepData.$2,
          detail: state.step == stepData.$3
              ? _localizedSetupDetail(l10n, state.detail)
              : null,
          isActive: state.step == stepData.$3,
          isComplete: state.stepNumber > stepData.$1 || state.isComplete,
          hasError: state.hasError && state.step == stepData.$3,
          progress: state.step == stepData.$3 ? state.progress : null,
          compact: !_started && !state.isComplete && !state.hasError,
          isLast: index == steps.length - 1,
        ),
    ];

    if (state.isComplete) {
      stepWidgets.add(
        ProgressStep(
          stepNumber: 6,
          label: l10n.t('setupWizardComplete'),
          isComplete: true,
        ),
      );
    }

    if (_started || state.isComplete || state.hasError) {
      if (embedded) {
        return Column(children: stepWidgets);
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: stepWidgets,
      );
    }

    final theme = Theme.of(context);
    final openClawSize = _selectedRelease?.unpackedSizeLabel ??
        _latestRelease?.unpackedSizeLabel ??
        AppConstants.openClawEstimatedSize;
    final cards = [
      _SetupStepCardData(
        number: 1,
        icon: Icons.download_rounded,
        action: l10n.t('setupWizardStepActionDownload'),
        target: 'Ubuntu rootfs',
      ),
      _SetupStepCardData(
        number: 2,
        icon: Icons.folder_open_rounded,
        action: l10n.t('setupWizardStepActionExtract'),
        target: 'rootfs',
      ),
      _SetupStepCardData(
        number: 3,
        icon: Icons.code_rounded,
        action: l10n.t('setupWizardStepActionInstall'),
        target: 'Node.js',
      ),
      _SetupStepCardData(
        number: 4,
        icon: Icons.smart_toy_outlined,
        action: l10n.t('setupWizardStepActionInstall'),
        target: 'OpenClaw\n($openClawSize)',
      ),
      _SetupStepCardData(
        number: 5,
        icon: Icons.shield_outlined,
        action: l10n.t('setupWizardStepActionConfigure'),
        target: 'Bionic Bypass',
      ),
    ];

    final panelColor = theme.brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF1A1A1A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: theme.brightness == Brightness.light
            ? const [
                BoxShadow(
                  color: Color(0x0B000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.format_list_bulleted_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.t('setupWizardStepsTitle'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SetupStepRow(data: card),
            ),
        ],
      ),
    );
  }

  Widget _buildInstallButton(
    ThemeData theme, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  const Color(0xFFEF2028),
                ],
              )
            : null,
        color: enabled ? null : theme.disabledColor.withAlpha(60),
        borderRadius: BorderRadius.circular(14),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withAlpha(42),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.download_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBootstrapResourceConfigButton(
    ThemeData theme,
    AppLocalizations l10n,
    bool disableSelection,
  ) {
    final hasConfig = _hasBootstrapResourceConfig;
    final subtitle = hasConfig
        ? l10n.t('setupWizardBootstrapResourcesConfigured')
        : l10n.t('setupWizardBootstrapResourcesOptional');
    final fillColor = theme.brightness == Brightness.light
        ? const Color(0xFFF7F8FA)
        : const Color(0xFF1A1A1A);
    final titleColor =
        disableSelection ? theme.disabledColor : theme.colorScheme.onSurface;
    final subtitleColor = disableSelection
        ? theme.disabledColor
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disableSelection ? null : _openBootstrapResourceConfig,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  hasConfig ? Icons.inventory_2 : Icons.inventory_2_outlined,
                  color: disableSelection
                      ? theme.disabledColor
                      : theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.t('setupWizardBootstrapResourcesTitle'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: subtitleColor,
              ),
            ],
          ),
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
    final panelColor = theme.brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF1A1A1A);
    final fieldColor = theme.brightness == Brightness.light
        ? Colors.white
        : theme.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: theme.brightness == Brightness.light
            ? const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.new_releases_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.t('setupWizardSelectVersion'),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue:
                      canSelectVersions ? selectedRelease.version : null,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.t('setupWizardVersionLoading'),
                    filled: true,
                    fillColor: fieldColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary.withAlpha(150),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary.withAlpha(120),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
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
                            _selectedRelease = _findReleaseByVersion(
                              availableReleases,
                              value,
                            );
                          });
                        },
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: fieldColor,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: disableSelection || _loadingReleaseOptions
                      ? null
                      : _loadOpenClawReleaseOptions,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Center(
                      child: _loadingReleaseOptions
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                ),
              ),
            ],
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
            if (OpenClawReleasePolicy.isPrerelease(
              selectedRelease.version,
            )) ...[
              const SizedBox(height: 6),
              Text(
                l10n.t('setupWizardExperimentalWarning'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (selectedRelease.nodeValidationStatus ==
                OpenClawNodeValidationStatus.unsupported) ...[
              const SizedBox(height: 6),
              Text(
                l10n.t('openClawNodeRuntimeUnsupported'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
          if (_releaseOptionsError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 18,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.t('setupWizardVersionOffline'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        height: 1.3,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadingReleaseOptions || disableSelection
                        ? null
                        : _loadOpenClawReleaseOptions,
                    child: Text(l10n.t('commonRetry')),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
  ) {
    return formatOpenClawReleaseLabel(
      l10n,
      release.version,
      channel: release.channel,
    );
  }

  String _localizedSetupMessage(AppLocalizations l10n, String? message) {
    return InstallStatusMessageFormatter.localize(l10n, message);
  }

  String? _localizedSetupDetail(AppLocalizations l10n, String? detail) {
    return InstallStatusMessageFormatter.localizeDetail(l10n, detail);
  }
}

class _BootstrapResourceConfig {
  final String prebuiltRootfsUrl;
  final String? prebuiltRootfsArchivePath;
  final String? prebuiltRootfsArchiveName;
  final String ubuntuRootfsUrl;
  final String? ubuntuRootfsArchivePath;
  final String? ubuntuRootfsArchiveName;
  final String nodeArchiveUrl;
  final String? nodeArchivePath;
  final String? nodeArchiveName;

  const _BootstrapResourceConfig({
    this.prebuiltRootfsUrl = '',
    this.prebuiltRootfsArchivePath,
    this.prebuiltRootfsArchiveName,
    this.ubuntuRootfsUrl = '',
    this.ubuntuRootfsArchivePath,
    this.ubuntuRootfsArchiveName,
    this.nodeArchiveUrl = '',
    this.nodeArchivePath,
    this.nodeArchiveName,
  });
}

class _BootstrapResourceConfigScreen extends StatefulWidget {
  final _BootstrapResourceConfig initialConfig;

  const _BootstrapResourceConfigScreen({
    required this.initialConfig,
  });

  @override
  State<_BootstrapResourceConfigScreen> createState() =>
      _BootstrapResourceConfigScreenState();
}

class _BootstrapResourceConfigScreenState
    extends State<_BootstrapResourceConfigScreen> {
  late final TextEditingController _prebuiltRootfsUrlController;
  late final TextEditingController _ubuntuRootfsUrlController;
  late final TextEditingController _nodeArchiveUrlController;
  late final TextEditingController _prebuiltRootfsFileController;
  late final TextEditingController _ubuntuRootfsFileController;
  late final TextEditingController _nodeArchiveFileController;

  String? _prebuiltRootfsArchivePath;
  String? _prebuiltRootfsArchiveName;
  String? _ubuntuRootfsArchivePath;
  String? _ubuntuRootfsArchiveName;
  String? _nodeArchivePath;
  String? _nodeArchiveName;
  String? _pickingResourceKey;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    _prebuiltRootfsUrlController =
        TextEditingController(text: initial.prebuiltRootfsUrl);
    _ubuntuRootfsUrlController =
        TextEditingController(text: initial.ubuntuRootfsUrl);
    _nodeArchiveUrlController =
        TextEditingController(text: initial.nodeArchiveUrl);
    _prebuiltRootfsArchivePath = initial.prebuiltRootfsArchivePath;
    _prebuiltRootfsArchiveName = initial.prebuiltRootfsArchiveName;
    _ubuntuRootfsArchivePath = initial.ubuntuRootfsArchivePath;
    _ubuntuRootfsArchiveName = initial.ubuntuRootfsArchiveName;
    _nodeArchivePath = initial.nodeArchivePath;
    _nodeArchiveName = initial.nodeArchiveName;
    _prebuiltRootfsFileController = TextEditingController(
      text: _displayArchive(
          initial.prebuiltRootfsArchiveName, initial.prebuiltRootfsArchivePath),
    );
    _ubuntuRootfsFileController = TextEditingController(
      text: _displayArchive(
          initial.ubuntuRootfsArchiveName, initial.ubuntuRootfsArchivePath),
    );
    _nodeArchiveFileController = TextEditingController(
      text: _displayArchive(initial.nodeArchiveName, initial.nodeArchivePath),
    );
  }

  @override
  void dispose() {
    _prebuiltRootfsUrlController.dispose();
    _ubuntuRootfsUrlController.dispose();
    _nodeArchiveUrlController.dispose();
    _prebuiltRootfsFileController.dispose();
    _ubuntuRootfsFileController.dispose();
    _nodeArchiveFileController.dispose();
    super.dispose();
  }

  static String _displayArchive(String? name, String? path) {
    final value = name?.trim().isNotEmpty == true ? name : path;
    return value?.trim() ?? '';
  }

  _BootstrapResourceConfig _result() {
    return _BootstrapResourceConfig(
      prebuiltRootfsUrl: _prebuiltRootfsUrlController.text.trim(),
      prebuiltRootfsArchivePath: _prebuiltRootfsArchivePath,
      prebuiltRootfsArchiveName: _prebuiltRootfsArchiveName,
      ubuntuRootfsUrl: _ubuntuRootfsUrlController.text.trim(),
      ubuntuRootfsArchivePath: _ubuntuRootfsArchivePath,
      ubuntuRootfsArchiveName: _ubuntuRootfsArchiveName,
      nodeArchiveUrl: _nodeArchiveUrlController.text.trim(),
      nodeArchivePath: _nodeArchivePath,
      nodeArchiveName: _nodeArchiveName,
    );
  }

  void _save() {
    Navigator.of(context).pop(_result());
  }

  void _useDefaultFlow() {
    Navigator.of(context).pop(const _BootstrapResourceConfig());
  }

  void _useGitHubDefaults() {
    setState(() {
      _prebuiltRootfsUrlController.text =
          AppConstants.basicResourcePrebuiltRootfsArm64;
      _ubuntuRootfsUrlController.text =
          AppConstants.basicResourceUbuntuRootfsArm64;
      _nodeArchiveUrlController.text = AppConstants.basicResourceNodeArm64;
      _setArchive('prebuilt', null, null);
      _setArchive('ubuntu', null, null);
      _setArchive('node', null, null);
    });
  }

  void _setArchive(String key, String? path, String? name) {
    final text = _displayArchive(name, path);
    switch (key) {
      case 'prebuilt':
        _prebuiltRootfsArchivePath = path;
        _prebuiltRootfsArchiveName = name;
        _prebuiltRootfsFileController.text = text;
        if (path != null) {
          _prebuiltRootfsUrlController.clear();
        }
        break;
      case 'ubuntu':
        _ubuntuRootfsArchivePath = path;
        _ubuntuRootfsArchiveName = name;
        _ubuntuRootfsFileController.text = text;
        if (path != null) {
          _ubuntuRootfsUrlController.clear();
        }
        break;
      case 'node':
        _nodeArchivePath = path;
        _nodeArchiveName = name;
        _nodeArchiveFileController.text = text;
        if (path != null) {
          _nodeArchiveUrlController.clear();
        }
        break;
    }
  }

  Future<void> _pickArchive(String key) async {
    if (_pickingResourceKey != null) {
      return;
    }

    setState(() => _pickingResourceKey = key);
    try {
      final picked = await NativeBridge.pickBootstrapArchiveFile();
      if (!mounted || picked == null) {
        return;
      }
      setState(() {
        _setArchive(
          key,
          picked['path'] as String?,
          picked['name'] as String?,
        );
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('setupWizardBootstrapPickFailed', {'error': e}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pickingResourceKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('setupWizardBootstrapResourcesTitle')),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(l10n.t('setupWizardBootstrapSave')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.t('setupWizardBootstrapResourcesIntro'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _useGitHubDefaults,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(l10n.t('setupWizardBootstrapUseGithub')),
                ),
                OutlinedButton.icon(
                  onPressed: _useDefaultFlow,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text(l10n.t('setupWizardBootstrapUseDefault')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildResourceEditor(
              theme: theme,
              keyName: 'prebuilt',
              title: l10n.t('setupWizardBootstrapPrebuiltRootfsTitle'),
              subtitle: l10n.t('setupWizardBootstrapPrebuiltRootfsSubtitle'),
              urlController: _prebuiltRootfsUrlController,
              fileController: _prebuiltRootfsFileController,
              localPath: _prebuiltRootfsArchivePath,
              urlHint: 'openclaw-rootfs-noble-arm64.tar.gz',
            ),
            const SizedBox(height: 12),
            _buildResourceEditor(
              theme: theme,
              keyName: 'ubuntu',
              title: l10n.t('setupWizardBootstrapUbuntuRootfsTitle'),
              subtitle: l10n.t('setupWizardBootstrapUbuntuRootfsSubtitle'),
              urlController: _ubuntuRootfsUrlController,
              fileController: _ubuntuRootfsFileController,
              localPath: _ubuntuRootfsArchivePath,
              urlHint: 'ubuntu-base-24.04.3-base-arm64.tar.gz',
            ),
            const SizedBox(height: 12),
            _buildResourceEditor(
              theme: theme,
              keyName: 'node',
              title: l10n.t('setupWizardBootstrapNodeTitle'),
              subtitle: l10n.t('setupWizardBootstrapNodeSubtitle'),
              urlController: _nodeArchiveUrlController,
              fileController: _nodeArchiveFileController,
              localPath: _nodeArchivePath,
              urlHint: 'node-v24.18.1-linux-arm64.tar.xz',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(l10n.t('setupWizardBootstrapSave')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceEditor({
    required ThemeData theme,
    required String keyName,
    required String title,
    required String subtitle,
    required TextEditingController urlController,
    required TextEditingController fileController,
    required String? localPath,
    required String urlHint,
  }) {
    final l10n = context.l10n;
    final hasLocalFile = (localPath ?? '').trim().isNotEmpty;
    final isPicking = _pickingResourceKey == keyName;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlController,
            enabled: !hasLocalFile,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.t('setupWizardBootstrapDownloadUrl'),
              hintText: urlHint,
              border: const OutlineInputBorder(),
              suffixIcon: urlController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.t('setupWizardBootstrapClearUrl'),
                      onPressed: () {
                        urlController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: fileController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: l10n.t('setupWizardBootstrapLocalFile'),
              hintText: l10n.t('setupWizardBootstrapNoFile'),
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.t('setupWizardBootstrapPickFile'),
                    onPressed: isPicking ? null : () => _pickArchive(keyName),
                    icon: isPicking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                  ),
                  if (hasLocalFile)
                    IconButton(
                      tooltip: l10n.t('setupWizardBootstrapRemoveFile'),
                      onPressed: () => setState(
                        () => _setArchive(keyName, null, null),
                      ),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupStepCardData {
  final int number;
  final IconData icon;
  final String action;
  final String target;

  const _SetupStepCardData({
    required this.number,
    required this.icon,
    required this.action,
    required this.target,
  });
}

class _SetupStepRow extends StatelessWidget {
  final _SetupStepCardData data;

  const _SetupStepRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? const Color(0xFFFDFDFD)
            : const Color(0xFF202020),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(35)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.light
                  ? const Color(0xFFFFECEC)
                  : theme.colorScheme.primary.withAlpha(35),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${data.number}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Icon(data.icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '${data.action} ${data.target.replaceAll('\n', ' ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
