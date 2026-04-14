import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/gateway_provider.dart';
import '../services/backup_library_service.dart';
import '../services/backup_service.dart';
import '../services/openclaw_version_service.dart';
import '../services/snapshot_service.dart';

class BackupManagerScreen extends StatefulWidget {
  const BackupManagerScreen({super.key});

  @override
  State<BackupManagerScreen> createState() => _BackupManagerScreenState();
}

class _BackupManagerScreenState extends State<BackupManagerScreen> {
  final _openClawVersionService = OpenClawVersionService();

  List<BackupLibraryEntry> _entries = const <BackupLibraryEntry>[];
  bool _loading = true;
  bool _busy = false;
  String? _currentOpenClawVersion;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final installedOpenClawVersion =
          await _openClawVersionService.readInstalledVersion();
      final entries = await BackupLibraryService.listEntries(
        currentAppVersion: AppConstants.version,
        currentOpenClawVersion: installedOpenClawVersion,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _currentOpenClawVersion = installedOpenClawVersion;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showSnack(error.toString());
    }
  }

  Future<void> _importExternalBackup() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final entry = await BackupLibraryService.importBackupFromPicker(
        currentAppVersion: AppConstants.version,
        currentOpenClawVersion: _currentOpenClawVersion,
      );
      if (entry == null) {
        return;
      }
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnack(
        context.l10n.t('backupManagerImported', {'file': entry.fileName}),
      );
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveConfigToLibrary() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final entry = await BackupLibraryService.saveCurrentConfigSnapshot(
        currentAppVersion: AppConstants.version,
        currentOpenClawVersion: _currentOpenClawVersion,
      );
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnack(
        context.l10n.t('backupManagerSavedLocal', {'file': entry.fileName}),
      );
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _exportConfigExternally() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await BackupService.exportConfigBackup(
        suggestedName: _defaultConfigBackupFileName(
          appVersion: AppConstants.version,
          openClawVersion: _currentOpenClawVersion,
        ),
      );
      if (saved == null || !mounted) {
        return;
      }
      final savedName = (saved['name'] as String?) ?? 'backup.json';
      _showSnack(context.l10n.t('settingsSnapshotSaved', {'path': savedName}));
    } catch (error) {
      if (mounted) {
        _showSnack(
          context.l10n.t('settingsExportFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _exportWorkspaceExternally() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await BackupService.exportWorkspaceBackup(
        suggestedName: _defaultWorkspaceBackupFileName(
          appVersion: AppConstants.version,
          openClawVersion: _currentOpenClawVersion,
        ),
        appVersion: AppConstants.version,
        openClawVersion: _currentOpenClawVersion,
      );
      if (saved == null || !mounted) {
        return;
      }
      final savedName = (saved['name'] as String?) ?? 'backup.zip';
      _showSnack(context.l10n.t('settingsSnapshotSaved', {'path': savedName}));
    } catch (error) {
      if (mounted) {
        _showSnack(
          context.l10n.t('settingsExportFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restoreEntry(BackupLibraryEntry entry) async {
    if (_busy) {
      return;
    }
    final l10n = context.l10n;
    final gatewayProvider = context.read<GatewayProvider>();
    final shouldContinue = await _confirmRestore(entry);
    if (!shouldContinue) {
      return;
    }

    setState(() => _busy = true);
    try {
      await gatewayProvider.stop();
      await gatewayProvider.syncState();
      await entry.bundle.restore();
      await gatewayProvider.syncState();
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnack(l10n.t('settingsSnapshotRestored', {'file': entry.fileName}));
    } catch (error) {
      if (mounted) {
        _showSnack(
          l10n.t('settingsImportFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteEntry(BackupLibraryEntry entry) async {
    if (_busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('backupManagerDeleteTitle')),
        content: Text(
          context.l10n.t('backupManagerDeleteBody', {'file': entry.fileName}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.t('providerDetailRemoveAction')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _busy = true);
    try {
      await BackupLibraryService.deleteEntry(entry);
      await _refresh();
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirmRestore(BackupLibraryEntry entry) async {
    final l10n = context.l10n;
    final compatibility = entry.compatibility;

    switch (entry.bundle.kind) {
      case BackupImportKind.config:
        return (await showDialog<bool>(
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
            )) ??
            false;
      case BackupImportKind.legacySnapshot:
        if (compatibility == null || !compatibility.requiresConfirmation) {
          return true;
        }
        return (await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(l10n.t('settingsSnapshotVersionWarningTitle')),
                content: SingleChildScrollView(
                  child: Text(
                    _buildSnapshotImportWarningMessage(l10n, compatibility),
                  ),
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
            )) ??
            false;
      case BackupImportKind.workspace:
        final lines = <String>[
          l10n.t('settingsBackupImportWorkspaceWarningBody'),
          if (compatibility != null && compatibility.requiresConfirmation) ...[
            '',
            _buildSnapshotImportWarningMessage(l10n, compatibility),
          ],
        ];
        return (await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title:
                    Text(l10n.t('settingsBackupImportWorkspaceWarningTitle')),
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
            )) ??
            false;
    }
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final fixed = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fixed)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('backupManagerTitle')),
        actions: [
          IconButton(
            tooltip: l10n.t('logsRefresh'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.t('backupManagerIntro'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _importExternalBackup,
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: Text(l10n.t('backupManagerImportAction')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _saveConfigToLibrary,
                          icon: const Icon(Icons.save_alt_outlined),
                          label: Text(l10n.t('backupManagerSaveCurrentAction')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _exportConfigExternally,
                          icon: const Icon(Icons.upload_file_outlined),
                          label:
                              Text(l10n.t('backupManagerExportConfigAction')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _exportWorkspaceExternally,
                          icon: const Icon(Icons.folder_zip_outlined),
                          label: Text(
                              l10n.t('backupManagerExportWorkspaceAction')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_entries.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.t('backupManagerEmpty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  for (final entry in _entries) ...[
                    _buildEntryCard(theme, l10n, entry),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
    );
  }

  Widget _buildEntryCard(
    ThemeData theme,
    AppLocalizations l10n,
    BackupLibraryEntry entry,
  ) {
    final compatibility = entry.compatibility;
    final kindLabel = switch (entry.bundle.kind) {
      BackupImportKind.config => l10n.t('backupManagerKindConfig'),
      BackupImportKind.legacySnapshot => l10n.t('backupManagerKindSnapshot'),
      BackupImportKind.workspace => l10n.t('backupManagerKindWorkspace'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.fileName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$kindLabel · ${_formatBytes(entry.sizeBytes)} · ${entry.modifiedAt.toLocal()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (compatibility?.requiresConfirmation == true) ...[
              const SizedBox(height: 8),
              Text(
                l10n.t('backupManagerCompatibilityWarning'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _restoreEntry(entry),
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(l10n.t('backupManagerRestoreAction')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _deleteEntry(entry),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.t('providerDetailRemoveAction')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
