import 'dart:io';
import 'dart:math' as math;

import '../l10n/app_localizations.dart';
import 'openclaw_version_policy.dart';

const String defaultRecommendedOpenClawReleaseVersion =
    OpenClawReleasePolicy.stableVersion;
const Set<String> recommendedOpenClawReleaseVersions = {
  '2026.3.13',
  OpenClawReleasePolicy.stableVersion,
  OpenClawReleasePolicy.knownLatestVersion,
};

bool isRecommendedOpenClawReleaseVersion(String version) {
  return recommendedOpenClawReleaseVersions.contains(version);
}

String formatOpenClawReleaseLabel(
  AppLocalizations l10n,
  String version, {
  OpenClawReleaseChannel channel = OpenClawReleaseChannel.historical,
}) {
  if (channel == OpenClawReleaseChannel.experimental) {
    return '$version (${l10n.t('openClawVersionLatest')} · ${l10n.t('openClawVersionRecommended')})';
  }
  if (isRecommendedOpenClawReleaseVersion(version)) {
    return '$version (${l10n.t('openClawVersionRecommended')})';
  }
  return version;
}

class OpenClawInstallOptions {
  static const List<int> supportedParallelJobs = [1, 2, 4, 6, 8];

  final int? parallelJobs;
  final bool ignoreScripts;
  final String? prebuiltRootfsUrl;
  final String? prebuiltRootfsArchivePath;
  final String? ubuntuRootfsUrl;
  final String? ubuntuRootfsArchivePath;
  final String? nodeArchiveUrl;
  final String? nodeArchivePath;

  const OpenClawInstallOptions({
    this.parallelJobs,
    this.ignoreScripts = false,
    this.prebuiltRootfsUrl,
    this.prebuiltRootfsArchivePath,
    this.ubuntuRootfsUrl,
    this.ubuntuRootfsArchivePath,
    this.nodeArchiveUrl,
    this.nodeArchivePath,
  });

  String? get normalizedPrebuiltRootfsUrl {
    final value = prebuiltRootfsUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedPrebuiltRootfsArchivePath {
    final value = prebuiltRootfsArchivePath?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedUbuntuRootfsUrl {
    final value = ubuntuRootfsUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedUbuntuRootfsArchivePath {
    final value = ubuntuRootfsArchivePath?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedNodeArchiveUrl {
    final value = nodeArchiveUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedNodeArchivePath {
    final value = nodeArchivePath?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  bool get hasPrebuiltRootfsOverride =>
      normalizedPrebuiltRootfsUrl != null ||
      normalizedPrebuiltRootfsArchivePath != null;

  bool get hasBootstrapResourceOverrides =>
      hasPrebuiltRootfsOverride ||
      normalizedUbuntuRootfsUrl != null ||
      normalizedUbuntuRootfsArchivePath != null ||
      normalizedNodeArchiveUrl != null ||
      normalizedNodeArchivePath != null;

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
        '--prefer-offline',
        '--fetch-retries=2',
        '--fetch-retry-mintimeout=1000',
        '--fetch-retry-maxtimeout=10000',
        '--loglevel=warn',
        if (ignoreScripts) '--ignore-scripts',
      ];

  Map<String, String> get installEnvironment => {
        'npm_package_config_node_gyp_jobs': '$resolvedParallelJobs',
        'npm_config_cache': '/root/.cache/npm',
        'npm_config_prefer_offline': 'true',
        'npm_config_update_notifier': 'false',
        'npm_config_audit': 'false',
        'npm_config_fund': 'false',
        'npm_config_progress': 'false',
        'MAKEFLAGS': '-j$resolvedParallelJobs',
        'CMAKE_BUILD_PARALLEL_LEVEL': '$resolvedParallelJobs',
      };

  OpenClawInstallOptions copyWith({
    int? parallelJobs,
    bool? ignoreScripts,
    String? prebuiltRootfsUrl,
    String? prebuiltRootfsArchivePath,
    String? ubuntuRootfsUrl,
    String? ubuntuRootfsArchivePath,
    String? nodeArchiveUrl,
    String? nodeArchivePath,
    bool clearParallelJobs = false,
    bool clearPrebuiltRootfsUrl = false,
    bool clearPrebuiltRootfsArchivePath = false,
    bool clearUbuntuRootfsUrl = false,
    bool clearUbuntuRootfsArchivePath = false,
    bool clearNodeArchiveUrl = false,
    bool clearNodeArchivePath = false,
  }) {
    return OpenClawInstallOptions(
      parallelJobs:
          clearParallelJobs ? null : (parallelJobs ?? this.parallelJobs),
      ignoreScripts: ignoreScripts ?? this.ignoreScripts,
      prebuiltRootfsUrl: clearPrebuiltRootfsUrl
          ? null
          : (prebuiltRootfsUrl ?? this.prebuiltRootfsUrl),
      prebuiltRootfsArchivePath: clearPrebuiltRootfsArchivePath
          ? null
          : (prebuiltRootfsArchivePath ?? this.prebuiltRootfsArchivePath),
      ubuntuRootfsUrl: clearUbuntuRootfsUrl
          ? null
          : (ubuntuRootfsUrl ?? this.ubuntuRootfsUrl),
      ubuntuRootfsArchivePath: clearUbuntuRootfsArchivePath
          ? null
          : (ubuntuRootfsArchivePath ?? this.ubuntuRootfsArchivePath),
      nodeArchiveUrl:
          clearNodeArchiveUrl ? null : (nodeArchiveUrl ?? this.nodeArchiveUrl),
      nodeArchivePath: clearNodeArchivePath
          ? null
          : (nodeArchivePath ?? this.nodeArchivePath),
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
