import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../l10n/app_localizations.dart';
import 'native_bridge.dart';
import 'update_service.dart';

/// Shared app update dialogs and install flow for dashboard/settings entrypoints.
class UpdateFlowService {
  static Future<void> showUpdateDialog(
    BuildContext context,
    UpdateResult result,
  ) async {
    final l10n = context.l10n;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('settingsUpdateAvailableTitle')),
        content: Text(
          l10n.t('settingsUpdateAvailableBody', {
            'current': AppConstants.version,
            'latest': result.latest,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('settingsUpdateLater')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstallUpdate(context, result);
            },
            child: Text(l10n.t('settingsUpdateDownload')),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadAndInstallUpdate(
    BuildContext context,
    UpdateResult result,
  ) async {
    final l10n = context.l10n;
    final progress = ValueNotifier<_UpdateProgressState>(
      _UpdateProgressState(
        title: l10n.t('settingsUpdateDownloadingTitle'),
        detail: l10n.t('settingsUpdatePreparingDownload'),
      ),
    );
    UpdateReleaseAsset? selectedAsset;
    var dialogShown = false;

    try {
      final arch = await NativeBridge.getArch();
      selectedAsset = result.preferredApkAssetForArch(arch);
      if (selectedAsset == null) {
        throw Exception(l10n.t('settingsUpdateNoCompatibleAsset'));
      }

      if (!context.mounted) return;
      dialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: ValueListenableBuilder<_UpdateProgressState>(
            valueListenable: progress,
            builder: (context, state, _) {
              final detailStyle =
                  Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      );
              final progressText = state.progress == null
                  ? l10n.t('settingsUpdateProgressUnknown')
                  : l10n.t('settingsUpdateProgressPercent', {
                      'percent': (state.progress! * 100).clamp(0, 100).round(),
                    });

              return AlertDialog(
                title: Text(state.title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.detail),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: state.progress),
                    const SizedBox(height: 8),
                    Text(progressText, style: detailStyle),
                  ],
                ),
              );
            },
          ),
        ),
      );

      progress.value = _UpdateProgressState(
        title: l10n.t('settingsUpdateDownloadingTitle'),
        detail: l10n.t('settingsUpdateDownloadingFile', {
          'file': selectedAsset.name,
        }),
      );

      final apkPath = await UpdateService.downloadAsset(
        selectedAsset,
        onProgress: (received, total) {
          final normalizedProgress =
              total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          progress.value = _UpdateProgressState(
            title: l10n.t('settingsUpdateDownloadingTitle'),
            detail: l10n.t('settingsUpdateDownloadingFile', {
              'file': selectedAsset!.name,
            }),
            progress: normalizedProgress,
          );
        },
      );

      progress.value = _UpdateProgressState(
        title: l10n.t('settingsUpdateDownloadingTitle'),
        detail: l10n.t('settingsUpdateInstalling'),
      );

      await NativeBridge.installApk(apkPath);

      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('settingsUpdateInstallerOpened'))),
      );
    } catch (_) {
      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      await _openUpdateFallback(context, result, asset: selectedAsset);
    } finally {
      progress.dispose();
    }
  }

  static Future<void> _openUpdateFallback(
    BuildContext context,
    UpdateResult result, {
    UpdateReleaseAsset? asset,
  }) async {
    if (!context.mounted) return;
    final l10n = context.l10n;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('settingsUpdateFallbackBrowser'))),
    );

    final preferredUrl = asset?.downloadUrl ?? result.url;
    final preferredUri = Uri.parse(preferredUrl);
    final openedPreferred = await launchUrl(
      preferredUri,
      mode: LaunchMode.externalApplication,
    );

    if (openedPreferred || preferredUrl == result.url) {
      return;
    }

    await launchUrl(
      Uri.parse(result.url),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _UpdateProgressState {
  const _UpdateProgressState({
    required this.title,
    required this.detail,
    this.progress,
  });

  final String title;
  final String detail;
  final double? progress;
}
