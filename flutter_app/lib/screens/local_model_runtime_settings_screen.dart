import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/local_model_service.dart';
import '../services/preferences_service.dart';

class LocalModelRuntimeSettingsScreen extends StatefulWidget {
  const LocalModelRuntimeSettingsScreen({
    super.key,
    required this.hardware,
  });

  final LocalModelHardwareProfile hardware;

  @override
  State<LocalModelRuntimeSettingsScreen> createState() =>
      _LocalModelRuntimeSettingsScreenState();
}

class _LocalModelRuntimeSettingsScreenState
    extends State<LocalModelRuntimeSettingsScreen> {
  final _prefs = PreferencesService();
  final _memoryLimitController = TextEditingController();

  bool _loading = true;
  int _maxCpuCores = 0;
  LocalModelPerformanceMode _performanceMode =
      LocalModelPerformanceMode.balanced;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memoryLimitController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _prefs.init();
    if (!mounted) {
      return;
    }
    setState(() {
      _maxCpuCores = _prefs.localModelMaxCpuCores;
      _performanceMode = _modeFromValue(_prefs.localModelPerformanceMode);
      final memoryLimitMiB = _prefs.localModelMemoryLimitMiB;
      _memoryLimitController.text =
          memoryLimitMiB > 0 ? _formatGiB(memoryLimitMiB / 1024) : '';
      _loading = false;
    });
  }

  LocalModelPerformanceMode _modeFromValue(String value) {
    switch (value.trim()) {
      case 'memorySaver':
        return LocalModelPerformanceMode.memorySaver;
      case 'performance':
        return LocalModelPerformanceMode.performance;
      case 'balanced':
      default:
        return LocalModelPerformanceMode.balanced;
    }
  }

  String _modeValue(LocalModelPerformanceMode mode) {
    switch (mode) {
      case LocalModelPerformanceMode.memorySaver:
        return 'memorySaver';
      case LocalModelPerformanceMode.balanced:
        return 'balanced';
      case LocalModelPerformanceMode.performance:
        return 'performance';
    }
  }

  String _formatGiB(double value) {
    return value.toStringAsFixed(1);
  }

  double? _parseMemoryLimitGiB(String raw) {
    final normalized =
        raw.trim().toLowerCase().replaceAll('gb', '').replaceAll('g', '');
    if (normalized.isEmpty) {
      return 0;
    }
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed < 0) {
      return null;
    }
    return double.parse(parsed.toStringAsFixed(1));
  }

  String _modeDescription(
    AppLocalizations l10n,
    LocalModelPerformanceMode mode,
  ) {
    switch (mode) {
      case LocalModelPerformanceMode.memorySaver:
        return l10n.t('localModelRuntimeSettingsModeMemorySaverDetail');
      case LocalModelPerformanceMode.balanced:
        return l10n.t('localModelRuntimeSettingsModeBalancedDetail');
      case LocalModelPerformanceMode.performance:
        return l10n.t('localModelRuntimeSettingsModePerformanceDetail');
    }
  }

  Widget _buildModeCard(
    ThemeData theme,
    AppLocalizations l10n,
    LocalModelPerformanceMode mode,
  ) {
    final selected = _performanceMode == mode;
    final title = switch (mode) {
      LocalModelPerformanceMode.memorySaver =>
        l10n.t('localModelRuntimeSettingsModeMemorySaver'),
      LocalModelPerformanceMode.balanced =>
        l10n.t('localModelRuntimeSettingsModeBalanced'),
      LocalModelPerformanceMode.performance =>
        l10n.t('localModelRuntimeSettingsModePerformance'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withAlpha(18)
            : theme.colorScheme.surfaceContainerHighest.withAlpha(72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withAlpha(90)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _modeDescription(l10n, mode),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final parsedLimitGiB = _parseMemoryLimitGiB(_memoryLimitController.text);
    if (parsedLimitGiB == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('localModelRuntimeSettingsMemoryInvalid'),
          ),
        ),
      );
      return;
    }
    final memoryLimit =
        parsedLimitGiB <= 0 ? 0 : (parsedLimitGiB * 1024).round();
    _prefs.localModelMaxCpuCores = _maxCpuCores;
    _prefs.localModelMemoryLimitMiB = memoryLimit;
    _prefs.localModelPerformanceMode = _modeValue(_performanceMode);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('localModelRuntimeSettingsSaved'))),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final cpuCount =
        widget.hardware.cpuCount > 0 ? widget.hardware.cpuCount : 8;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('localModelRuntimeSettingsTitle')),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: Text(l10n.t('commonDone')),
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
                      l10n.t('localModelRuntimeSettingsIntro'),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('localModelRuntimeSettingsDeviceTitle'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.t('localModelRuntimeSettingsDeviceSummary', {
                            'cpu': '$cpuCount',
                            'memory':
                                widget.hardware.memoryGiB.toStringAsFixed(1),
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('localModelRuntimeSettingsCpuTitle'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _maxCpuCores,
                          items: [
                            DropdownMenuItem(
                              value: 0,
                              child:
                                  Text(l10n.t('localModelRuntimeSettingsAuto')),
                            ),
                            for (var core = 1; core <= cpuCount; core++)
                              DropdownMenuItem(
                                value: core,
                                child: Text(
                                  l10n.t(
                                    'localModelRuntimeSettingsCpuOption',
                                    {'value': '$core'},
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() => _maxCpuCores = value);
                          },
                          decoration: InputDecoration(
                            labelText:
                                l10n.t('localModelRuntimeSettingsCpuLabel'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.t('localModelRuntimeSettingsCpuHint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('localModelRuntimeSettingsMemoryTitle'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _memoryLimitController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                l10n.t('localModelRuntimeSettingsMemoryLabel'),
                            hintText: '5.8',
                            suffixText: 'GB',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${l10n.t('localModelRuntimeSettingsMemoryHint')}\n${l10n.t('localModelRuntimeSettingsMemoryDetected', {
                                'value': _formatGiB(widget.hardware.memoryGiB)
                              })}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('localModelRuntimeSettingsModeTitle'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<LocalModelPerformanceMode>(
                          segments: [
                            ButtonSegment(
                              value: LocalModelPerformanceMode.memorySaver,
                              label: Text(
                                l10n.t(
                                  'localModelRuntimeSettingsModeMemorySaver',
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: LocalModelPerformanceMode.balanced,
                              label: Text(
                                l10n.t(
                                  'localModelRuntimeSettingsModeBalanced',
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: LocalModelPerformanceMode.performance,
                              label: Text(
                                l10n.t(
                                  'localModelRuntimeSettingsModePerformance',
                                ),
                              ),
                            ),
                          ],
                          selected: {_performanceMode},
                          onSelectionChanged: (selection) {
                            setState(() => _performanceMode = selection.first);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.t('localModelRuntimeSettingsModeHint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildModeCard(
                          theme,
                          l10n,
                          LocalModelPerformanceMode.memorySaver,
                        ),
                        const SizedBox(height: 8),
                        _buildModeCard(
                          theme,
                          l10n,
                          LocalModelPerformanceMode.balanced,
                        ),
                        const SizedBox(height: 8),
                        _buildModeCard(
                          theme,
                          l10n,
                          LocalModelPerformanceMode.performance,
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
