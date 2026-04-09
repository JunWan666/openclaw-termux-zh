import 'dart:io';
import 'dart:math' as math;

import '../l10n/app_localizations.dart';

const String defaultRecommendedOpenClawReleaseVersion = '2026.3.23';
const Set<String> recommendedOpenClawReleaseVersions = {
  '2026.3.13',
  '2026.3.23',
};

bool isRecommendedOpenClawReleaseVersion(String version) {
  return recommendedOpenClawReleaseVersions.contains(version);
}

String formatOpenClawReleaseLabel(
  AppLocalizations l10n,
  String version, {
  String? latestVersion,
}) {
  final tags = <String>[];
  if (version == latestVersion) {
    tags.add(l10n.t('gatewayLatest'));
  }
  if (isRecommendedOpenClawReleaseVersion(version)) {
    tags.add(l10n.t('setupWizardRecommended'));
  }

  if (tags.isEmpty) {
    return version;
  }
  return '$version (${tags.join(' / ')})';
}

class OpenClawInstallOptions {
  static const List<int> supportedParallelJobs = [1, 2, 4, 6, 8];

  final int? parallelJobs;
  final bool ignoreScripts;

  const OpenClawInstallOptions({
    this.parallelJobs,
    this.ignoreScripts = false,
  });

  int get resolvedParallelJobs {
    final manualJobs = parallelJobs;
    if (manualJobs != null) {
      return manualJobs;
    }

    final processors = math.max(1, Platform.numberOfProcessors);
    final autoJobs = processors <= 2 ? 1 : processors - 1;
    return autoJobs.clamp(1, 6).toInt();
  }

  List<String> get npmFlags => [
        '--no-audit',
        '--no-fund',
        '--no-progress',
        if (ignoreScripts) '--ignore-scripts',
      ];

  Map<String, String> get installEnvironment => {
        'npm_package_config_node_gyp_jobs': '$resolvedParallelJobs',
        'MAKEFLAGS': '-j$resolvedParallelJobs',
        'CMAKE_BUILD_PARALLEL_LEVEL': '$resolvedParallelJobs',
      };

  OpenClawInstallOptions copyWith({
    int? parallelJobs,
    bool? ignoreScripts,
    bool clearParallelJobs = false,
  }) {
    return OpenClawInstallOptions(
      parallelJobs:
          clearParallelJobs ? null : (parallelJobs ?? this.parallelJobs),
      ignoreScripts: ignoreScripts ?? this.ignoreScripts,
    );
  }

  String parallelJobsLabel(
    AppLocalizations l10n, {
    bool includeResolvedForAuto = false,
  }) {
    if (parallelJobs == null) {
      if (!includeResolvedForAuto) {
        return l10n.t('openClawInstallOptionsParallelAuto');
      }
      return '${l10n.t('openClawInstallOptionsParallelAuto')} · ${l10n.t('openClawInstallOptionsParallelThreadCount', {
            'count': resolvedParallelJobs,
          })}';
    }

    return l10n.t('openClawInstallOptionsParallelThreadCount', {
      'count': parallelJobs,
    });
  }
}
