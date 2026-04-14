import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../services/local_model_service.dart';
import '../services/online_model_catalog_service.dart';

enum _CatalogMode {
  builtIn,
  online,
}

class LocalModelCatalogScreen extends StatefulWidget {
  const LocalModelCatalogScreen({
    super.key,
    required this.hardware,
  });

  final LocalModelHardwareProfile hardware;

  @override
  State<LocalModelCatalogScreen> createState() =>
      _LocalModelCatalogScreenState();
}

class _LocalModelCatalogScreenState extends State<LocalModelCatalogScreen> {
  final _searchController = TextEditingController();

  String _selectedGroup = 'all';
  _CatalogMode _mode = _CatalogMode.builtIn;
  bool _onlineLoading = false;
  String? _onlineError;
  String? _loadingRepoId;
  List<OnlineModelCatalogSearchResult> _onlineResults =
      const <OnlineModelCatalogSearchResult>[];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LocalModelCatalogEntry> get _builtInEntries {
    return LocalModelService.searchCatalog(
      query: _searchController.text,
      group: _selectedGroup,
      hardware: widget.hardware,
    );
  }

  void _handleSearchChanged(String _) {
    if (_mode == _CatalogMode.builtIn) {
      setState(() {});
      return;
    }

    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _onlineResults = const <OnlineModelCatalogSearchResult>[];
        _onlineError = null;
      });
      return;
    }
    setState(() {});
  }

  Future<void> _switchMode(_CatalogMode nextMode) async {
    if (_mode == nextMode) {
      return;
    }

    setState(() => _mode = nextMode);
  }

  Future<void> _runOnlineSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _onlineResults = const <OnlineModelCatalogSearchResult>[];
        _onlineError = context.l10n.t('localModelCatalogOnlineSearchRequired');
      });
      return;
    }

    setState(() {
      _onlineLoading = true;
      _onlineError = null;
    });

    try {
      final results = await OnlineModelCatalogService.searchGgufModels(
        query,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _onlineResults = results;
        _onlineLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _onlineLoading = false;
        _onlineError = _friendlyOnlineError(context.l10n, error);
      });
    }
  }

  Future<void> _selectOnlineEntry(OnlineModelCatalogSearchResult entry) async {
    if (_loadingRepoId != null) {
      return;
    }

    setState(() => _loadingRepoId = entry.repoId);
    try {
      final variants =
          await OnlineModelCatalogService.fetchGgufVariants(entry.repoId);
      if (!mounted) {
        return;
      }

      final selection = await showModalBottomSheet<LocalModelDownloadSelection>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => _VariantPickerSheet(
          entry: entry,
          variants: variants,
        ),
      );
      if (!mounted || selection == null) {
        return;
      }
      Navigator.of(context).pop(selection);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyOnlineError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingRepoId = null);
      }
    }
  }

  String _friendlyOnlineError(AppLocalizations l10n, Object error) {
    if (error is OnlineModelCatalogException) {
      switch (error.code) {
        case 'http_429':
          return l10n.t('localModelCatalogOnlineRateLimited');
        case 'timeout':
          return l10n.t('localModelCatalogOnlineTimeout');
        default:
          return l10n.t(
            'localModelCatalogOnlineRequestFailed',
            {'error': error.statusCode ?? error.message},
          );
      }
    }
    return '$error';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('localModelCatalogTitle')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeaderCard(theme, l10n),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.t('localModelCatalogModeBuiltIn')),
                selected: _mode == _CatalogMode.builtIn,
                onSelected: (_) => _switchMode(_CatalogMode.builtIn),
              ),
              ChoiceChip(
                label: Text(l10n.t('localModelCatalogModeOnline')),
                selected: _mode == _CatalogMode.online,
                onSelected: (_) => _switchMode(_CatalogMode.online),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _mode == _CatalogMode.builtIn
                  ? l10n.t('localModelCatalogSearchHint')
                  : l10n.t('localModelCatalogOnlineSearchHint'),
              suffixIcon: _mode == _CatalogMode.online
                  ? IconButton(
                      tooltip: l10n.t('localModelCatalogOnlineSearchAction'),
                      onPressed: _onlineLoading ? null : _runOnlineSearch,
                      icon: const Icon(Icons.travel_explore),
                    )
                  : null,
            ),
            onChanged: _handleSearchChanged,
            onSubmitted: (_) {
              if (_mode == _CatalogMode.online) {
                _runOnlineSearch();
              }
            },
          ),
          if (_mode == _CatalogMode.builtIn) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _filterOptions(l10n))
                  ChoiceChip(
                    label: Text(option.label),
                    selected: option.value == _selectedGroup,
                    onSelected: (_) {
                      setState(() => _selectedGroup = option.value);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ..._buildBuiltInSection(theme, l10n),
          ] else ...[
            const SizedBox(height: 16),
            ..._buildOnlineSection(theme, l10n),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildBuiltInSection(ThemeData theme, AppLocalizations l10n) {
    final entries = _builtInEntries;
    if (entries.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.t('localModelCatalogNoResults'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ];
    }

    return [
      for (final entry in entries) ...[
        _buildBuiltInEntryCard(theme, l10n, entry),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildOnlineSection(ThemeData theme, AppLocalizations l10n) {
    final widgets = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.t('localModelCatalogOnlineIntro'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];

    if (_onlineLoading) {
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l10n.t('localModelCatalogOnlineLoading')),
                ),
              ],
            ),
          ),
        ),
      );
      return widgets;
    }

    if (_onlineError != null) {
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _onlineError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      );
      return widgets;
    }

    if (_onlineResults.isEmpty) {
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.t('localModelCatalogOnlineEmpty'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
      return widgets;
    }

    for (final entry in _onlineResults) {
      widgets.add(_buildOnlineEntryCard(theme, l10n, entry));
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  Widget _buildHeaderCard(ThemeData theme, AppLocalizations l10n) {
    final memory = widget.hardware.memoryGiB;
    final storage = widget.hardware.freeStorageGiB;
    final summaryText = [
      if (memory > 0)
        l10n.t('localModelChipRam', {'value': memory.toStringAsFixed(1)}),
      if (storage > 0)
        l10n.t('localModelChipStorage', {'value': storage.toStringAsFixed(1)}),
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelCatalogTitle'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('localModelCatalogIntro'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (summaryText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  summaryText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.t('localModelCatalogAutoDownloadHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuiltInEntryCard(
    ThemeData theme,
    AppLocalizations l10n,
    LocalModelCatalogEntry entry,
  ) {
    final compatibility = _compatibilityFor(entry, theme, l10n);

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
                        entry.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildChip(theme, compatibility.label, compatibility.color),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip(theme, entry.sizeLabel, theme.colorScheme.primary),
                _buildChip(
                  theme,
                  l10n.t(
                    'localModelCatalogRecommendRam',
                    {'value': entry.recommendedMemoryGiB.toStringAsFixed(0)},
                  ),
                  theme.colorScheme.secondary,
                ),
                _buildChip(
                  theme,
                  entry.sourceLabel,
                  theme.colorScheme.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${l10n.t('localModelCatalogBestForLabel')}: ${entry.bestFor}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              compatibility.detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: compatibility.color,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                LocalModelDownloadSelection(
                  title: entry.title,
                  subtitle: entry.subtitle,
                  fileName: entry.fileName,
                  downloadUrl: entry.downloadUrl,
                  defaultAlias: entry.defaultAlias,
                  sourceLabel: entry.sourceLabel,
                ),
              ),
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(l10n.t('localModelCatalogOneTapDownload')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineEntryCard(
    ThemeData theme,
    AppLocalizations l10n,
    OnlineModelCatalogSearchResult entry,
  ) {
    final loadingThisRepo = _loadingRepoId == entry.repoId;
    final tags = entry.tags
        .where((tag) => !tag.startsWith('base_model:'))
        .take(3)
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (entry.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                entry.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip(
                  theme,
                  l10n.t(
                    'localModelCatalogOnlineDownloads',
                    {'value': _compactNumber(entry.downloads)},
                  ),
                  theme.colorScheme.primary,
                ),
                _buildChip(
                  theme,
                  l10n.t(
                    'localModelCatalogOnlineLikes',
                    {'value': _compactNumber(entry.likes)},
                  ),
                  theme.colorScheme.secondary,
                ),
                if (entry.gated)
                  _buildChip(
                    theme,
                    l10n.t('localModelCatalogOnlineGated'),
                    AppColors.statusAmber,
                  ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    _buildChip(theme, tag, theme.colorScheme.tertiary),
                ],
              ),
            ],
            if (entry.updatedAt != null) ...[
              const SizedBox(height: 10),
              Text(
                l10n.t(
                  'localModelCatalogOnlineUpdated',
                  {'value': _formatDate(entry.updatedAt!)},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  loadingThisRepo ? null : () => _selectOnlineEntry(entry),
              icon: loadingThisRepo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(l10n.t('localModelCatalogOnlineAction')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  _CatalogCompatibility _compatibilityFor(
    LocalModelCatalogEntry entry,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final memory = widget.hardware.memoryGiB;
    if (memory <= 0) {
      return _CatalogCompatibility(
        label: l10n.t('localModelCatalogCompatUnknown'),
        detail: l10n.t('localModelCatalogCompatUnknownBody'),
        color: theme.colorScheme.outline,
      );
    }
    if (memory >= entry.recommendedMemoryGiB) {
      return _CatalogCompatibility(
        label: l10n.t('localModelCatalogCompatGreat'),
        detail: l10n.t('localModelCatalogCompatGreatBody'),
        color: AppColors.statusGreen,
      );
    }
    if (memory >= entry.minimumMemoryGiB) {
      return _CatalogCompatibility(
        label: l10n.t('localModelCatalogCompatOkay'),
        detail: l10n.t('localModelCatalogCompatOkayBody'),
        color: AppColors.statusAmber,
      );
    }
    return _CatalogCompatibility(
      label: l10n.t('localModelCatalogCompatTooHeavy'),
      detail: l10n.t('localModelCatalogCompatTooHeavyBody'),
      color: AppColors.statusRed,
    );
  }

  List<_FilterOption> _filterOptions(AppLocalizations l10n) {
    return [
      _FilterOption('all', l10n.t('localModelCatalogFilterAll')),
      _FilterOption('starter', l10n.t('localModelCatalogFilterStarter')),
      _FilterOption('daily', l10n.t('localModelCatalogFilterDaily')),
      _FilterOption('strong', l10n.t('localModelCatalogFilterStrong')),
      _FilterOption('coding', l10n.t('localModelCatalogFilterCoding')),
    ];
  }

  String _compactNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return '$value';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _VariantPickerSheet extends StatelessWidget {
  const _VariantPickerSheet({
    required this.entry,
    required this.variants,
  });

  final OnlineModelCatalogSearchResult entry;
  final List<OnlineModelCatalogVariant> variants;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelCatalogVariantTitle'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.repoId,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.t('localModelCatalogVariantHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (variants.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.t('localModelCatalogOnlineEmpty'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: variants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final variant = variants[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(variant.fileName),
                        subtitle: Text(_variantHint(context, variant.fileName)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(
                          variant.toSelection(
                            title: entry.repoId,
                            subtitle: entry.subtitle,
                            sourceLabel: 'Hugging Face GGUF',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _variantHint(BuildContext context, String fileName) {
    final l10n = context.l10n;
    final lower = fileName.toLowerCase();
    if (lower.contains('q4_k_m')) {
      return l10n.t('localModelCatalogVariantRecommendQ4km');
    }
    if (lower.contains('q4_0')) {
      return l10n.t('localModelCatalogVariantRecommendQ40');
    }
    if (lower.contains('fp16')) {
      return l10n.t('localModelCatalogVariantTooLarge');
    }
    return l10n.t('localModelCatalogVariantGeneral');
  }
}

class _FilterOption {
  const _FilterOption(this.value, this.label);

  final String value;
  final String label;
}

class _CatalogCompatibility {
  const _CatalogCompatibility({
    required this.label,
    required this.detail,
    required this.color,
  });

  final String label;
  final String detail;
  final Color color;
}
