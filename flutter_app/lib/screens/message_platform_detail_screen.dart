import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/message_platform.dart';
import '../providers/gateway_provider.dart';
import '../services/message_platform_config_service.dart';
import 'weixin_installer_screen.dart';

enum _QqbotPluginStatus {
  checking,
  installing,
  ready,
  failed,
}

enum _QqbotPostSaveAction {
  done,
  restartGateway,
}

enum _WeixinPluginStatus {
  checking,
  installed,
  missing,
  failed,
}

/// Form screen to configure a single messaging platform channel.
class MessagePlatformDetailScreen extends StatefulWidget {
  final MessagePlatform platform;
  final Map<String, dynamic>? existingConfig;

  const MessagePlatformDetailScreen({
    super.key,
    required this.platform,
    this.existingConfig,
  });

  @override
  State<MessagePlatformDetailScreen> createState() =>
      _MessagePlatformDetailScreenState();
}

class _MessagePlatformDetailScreenState
    extends State<MessagePlatformDetailScreen> {
  static const _defaultFeishuDomain = 'feishu';

  late final TextEditingController _appIdController;
  late final TextEditingController _appSecretController;
  late final TextEditingController _botNameController;
  late String _selectedDomain;
  bool _obscureSecret = true;
  bool _saving = false;
  bool _removing = false;
  bool _restartingGateway = false;
  _QqbotPluginStatus _qqbotPluginStatus = _QqbotPluginStatus.ready;
  String? _qqbotPluginError;
  _WeixinPluginStatus _weixinPluginStatus = _WeixinPluginStatus.checking;
  String? _weixinPluginError;

  bool get _isFeishu => widget.platform.isFeishu;

  bool get _isQqbot => widget.platform.isQqbot;

  bool get _isWeixin => widget.platform.isWeixin;

  bool get _qqbotPluginReady =>
      !_isQqbot || _qqbotPluginStatus == _QqbotPluginStatus.ready;

  bool get _isConfigured {
    if (widget.existingConfig?['configured'] == true) {
      return true;
    }
    if (_isWeixin) {
      return widget.existingConfig != null && widget.existingConfig!.isNotEmpty;
    }
    final appId = widget.existingConfig?['appId'] as String?;
    final appSecret = widget.existingConfig?['appSecret'] as String?;
    return appId != null &&
        appId.isNotEmpty &&
        appSecret != null &&
        appSecret.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _appIdController = TextEditingController(
      text: widget.existingConfig?['appId'] as String? ?? '',
    );
    _appSecretController = TextEditingController(
      text: widget.existingConfig?['appSecret'] as String? ?? '',
    );
    _botNameController = TextEditingController(
      text: widget.existingConfig?['botName'] as String? ?? '',
    );
    _selectedDomain =
        widget.existingConfig?['domain'] as String? ?? _defaultFeishuDomain;
    if (_isQqbot) {
      _qqbotPluginStatus = _QqbotPluginStatus.checking;
      unawaited(_prepareQqbotPlugin());
    }
    if (_isWeixin) {
      unawaited(_refreshWeixinPluginStatus());
    }
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _appSecretController.dispose();
    _botNameController.dispose();
    super.dispose();
  }

  Future<void> _prepareQqbotPlugin() async {
    if (!_isQqbot) return;

    setState(() {
      _qqbotPluginStatus = _QqbotPluginStatus.checking;
      _qqbotPluginError = null;
    });

    try {
      final installed =
          await MessagePlatformConfigService.isQqbotPluginInstalled();
      if (!mounted) return;

      if (installed) {
        setState(() => _qqbotPluginStatus = _QqbotPluginStatus.ready);
        return;
      }

      setState(() => _qqbotPluginStatus = _QqbotPluginStatus.installing);
      await MessagePlatformConfigService.ensureQqbotPluginInstalled();
      if (!mounted) return;

      setState(() => _qqbotPluginStatus = _QqbotPluginStatus.ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qqbotPluginStatus = _QqbotPluginStatus.failed;
        _qqbotPluginError = '$e';
      });
    }
  }

  Future<void> _refreshWeixinPluginStatus() async {
    if (!_isWeixin) return;

    setState(() {
      _weixinPluginStatus = _WeixinPluginStatus.checking;
      _weixinPluginError = null;
    });

    try {
      final installed =
          await MessagePlatformConfigService.isWeixinPluginInstalled();
      if (!mounted) return;

      setState(() {
        _weixinPluginStatus = installed
            ? _WeixinPluginStatus.installed
            : _WeixinPluginStatus.missing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weixinPluginStatus = _WeixinPluginStatus.failed;
        _weixinPluginError = '$e';
      });
    }
  }

  Future<void> _openWeixinInstaller() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WeixinInstallerScreen()),
    );
    if (result == true) {
      await _refreshWeixinPluginStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('messagePlatformDetailWeixinTerminalCompleted'),
          ),
        ),
      );
    }
  }

  Future<void> _openConnectPage() async {
    final l10n = context.l10n;
    final rawUrl = widget.platform.connectUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('commonNoUrlFound'))),
      );
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('commonNoUrlFound'))),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('messagePlatformDetailOpenPageFailed'))),
      );
    }
  }

  Future<void> _showQqbotSavedDialog() async {
    final l10n = context.l10n;
    final provider = context.read<GatewayProvider>();
    final shouldOfferRestart = !provider.state.isStopped;

    final action = await showDialog<_QqbotPostSaveAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('messagePlatformDetailQqbotSavedTitle')),
        content: Text(
          l10n.t(
            shouldOfferRestart
                ? 'messagePlatformDetailQqbotSavedBodyRunning'
                : 'messagePlatformDetailQqbotSavedBodyStopped',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _QqbotPostSaveAction.done),
            child: Text(l10n.t('commonDone')),
          ),
          if (shouldOfferRestart)
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _QqbotPostSaveAction.restartGateway,
              ),
              child: Text(l10n.t('messagePlatformDetailGatewayRestartAction')),
            ),
        ],
      ),
    );

    if (action == _QqbotPostSaveAction.restartGateway) {
      await _restartGateway();
    }
  }

  Future<void> _restartGateway() async {
    if (_restartingGateway || !mounted) return;

    final l10n = context.l10n;
    final provider = context.read<GatewayProvider>();
    var dialogVisible = false;

    setState(() => _restartingGateway = true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogVisible = true;
          return AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.t('messagePlatformDetailGatewayRestarting'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      if (!provider.state.isStopped) {
        await provider.stop();
      }
      await provider.start();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('messagePlatformDetailGatewayRestarted')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('messagePlatformDetailGatewayRestartFailed', {
              'error': '$e',
            }),
          ),
        ),
      );
    } finally {
      if (mounted && dialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        setState(() => _restartingGateway = false);
      }
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_isQqbot && !_qqbotPluginReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('messagePlatformDetailQqbotPluginFailed')),
        ),
      );
      return;
    }

    final appId = _appIdController.text.trim();
    if (appId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('messagePlatformDetailAppIdEmpty'))),
      );
      return;
    }

    final appSecret = _appSecretController.text.trim();
    if (appSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('messagePlatformDetailAppSecretEmpty'))),
      );
      return;
    }

    final botName = _botNameController.text.trim();
    final payload = _isQqbot
        ? <String, dynamic>{
            'appId': appId,
            'appSecret': appSecret,
          }
        : <String, dynamic>{
            'appId': appId,
            'appSecret': appSecret,
            if (botName.isNotEmpty) 'botName': botName,
            if (_selectedDomain.isNotEmpty) 'domain': _selectedDomain,
          };

    setState(() => _saving = true);
    try {
      await MessagePlatformConfigService.saveChannelConfig(
        channelId: widget.platform.id,
        payload: payload,
      );
      if (!mounted) return;

      if (_isQqbot) {
        await _showQqbotSavedDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.t('messagePlatformDetailSaved', {
                'platform': widget.platform.name(l10n),
              }),
            ),
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('messagePlatformDetailSaveFailed', {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.t('messagePlatformDetailRemoveTitle', {
            'platform': widget.platform.name(l10n),
          }),
        ),
        content: Text(l10n.t('messagePlatformDetailRemoveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('messagePlatformDetailRemoveAction')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _removing = true);
    try {
      await MessagePlatformConfigService.removeChannelConfig(
        channelId: widget.platform.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('messagePlatformDetailRemoved', {
              'platform': widget.platform.name(l10n),
            }),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('messagePlatformDetailRemoveFailed', {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _removing = false);
      }
    }
  }

  Widget _buildPlatformHeader(
    ThemeData theme,
    Color iconBg,
  ) {
    final l10n = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.platform.icon,
                color: widget.platform.color,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.platform.name(l10n),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.platform.description(l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeishuFields(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            l10n.t('messagePlatformDetailOfficialConfigHint', {
              'path': widget.platform.configPath,
            }),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.t('messagePlatformDetailAppId'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _appIdController,
          decoration: const InputDecoration(
            hintText: 'cli_xxxxxxxxxxxxx',
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.t('messagePlatformDetailAppSecret'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _appSecretController,
          obscureText: _obscureSecret,
          decoration: InputDecoration(
            hintText: 'cli_asxxxxxxxxxxxxx',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureSecret ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() => _obscureSecret = !_obscureSecret);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.t('messagePlatformDetailBotName'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _botNameController,
          decoration: InputDecoration(
            hintText: 'OpenClaw',
            helperText: l10n.t('messagePlatformDetailBotNameHelper'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.t('messagePlatformDetailDomain'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedDomain,
          decoration: InputDecoration(
            helperText: l10n.t('messagePlatformDetailDomainHelper'),
          ),
          items: [
            DropdownMenuItem(
              value: 'feishu',
              child: Text(l10n.t('messagePlatformDetailDomainOptionFeishu')),
            ),
            DropdownMenuItem(
              value: 'lark',
              child: Text(l10n.t('messagePlatformDetailDomainOptionLark')),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedDomain = value);
          },
        ),
      ],
    );
  }

  Widget _buildQqbotConnectCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('messagePlatformDetailQqbotConnectTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('messagePlatformDetailQqbotConnectBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openConnectPage,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.t('messagePlatformDetailQqbotOpenPage')),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.t('messagePlatformDetailQqbotPageHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQqbotPluginCard(ThemeData theme, AppLocalizations l10n) {
    final isBusy = _qqbotPluginStatus == _QqbotPluginStatus.checking ||
        _qqbotPluginStatus == _QqbotPluginStatus.installing;

    IconData statusIcon;
    Color statusColor;
    String statusText;

    switch (_qqbotPluginStatus) {
      case _QqbotPluginStatus.checking:
        statusIcon = Icons.search_rounded;
        statusColor = theme.colorScheme.primary;
        statusText = l10n.t('messagePlatformDetailQqbotPluginChecking');
        break;
      case _QqbotPluginStatus.installing:
        statusIcon = Icons.download_rounded;
        statusColor = theme.colorScheme.primary;
        statusText = l10n.t('messagePlatformDetailQqbotPluginInstalling');
        break;
      case _QqbotPluginStatus.ready:
        statusIcon = Icons.check_circle_rounded;
        statusColor = AppColors.statusGreen;
        statusText = l10n.t('messagePlatformDetailQqbotPluginReady');
        break;
      case _QqbotPluginStatus.failed:
        statusIcon = Icons.error_rounded;
        statusColor = theme.colorScheme.error;
        statusText = l10n.t('messagePlatformDetailQqbotPluginFailed');
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isBusy)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColor,
                    ),
                  )
                else
                  Icon(statusIcon, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.t('messagePlatformDetailQqbotPluginInstallHint', {
                'package': MessagePlatformConfigService.qqbotPluginPackage,
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_qqbotPluginError != null && _qqbotPluginError!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withAlpha(140),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _qqbotPluginError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            if (_qqbotPluginStatus == _QqbotPluginStatus.failed) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    _saving || _restartingGateway ? null : _prepareQqbotPlugin,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.t('messagePlatformDetailQqbotPluginRetry')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQqbotFields(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQqbotConnectCard(theme, l10n),
        const SizedBox(height: 16),
        _buildQqbotPluginCard(theme, l10n),
        const SizedBox(height: 24),
        Text(
          l10n.t('messagePlatformDetailAppId'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _appIdController,
          enabled: _qqbotPluginReady && !_saving && !_restartingGateway,
          decoration: const InputDecoration(
            hintText: '102868422',
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.t('messagePlatformDetailAppSecret'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _appSecretController,
          enabled: _qqbotPluginReady && !_saving && !_restartingGateway,
          obscureText: _obscureSecret,
          decoration: InputDecoration(
            hintText: 'Zabdfilpty39FMTbjs1BLWiu7KYm1GWm',
            helperText: l10n.t('messagePlatformDetailQqbotTokenHint'),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureSecret ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() => _obscureSecret = !_obscureSecret);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeixinStatusCard(ThemeData theme, AppLocalizations l10n) {
    final isChecking = _weixinPluginStatus == _WeixinPluginStatus.checking;

    IconData statusIcon;
    Color statusColor;
    String statusText;

    switch (_weixinPluginStatus) {
      case _WeixinPluginStatus.checking:
        statusIcon = Icons.search_rounded;
        statusColor = theme.colorScheme.primary;
        statusText = l10n.t('messagePlatformDetailWeixinPluginChecking');
        break;
      case _WeixinPluginStatus.installed:
        statusIcon = Icons.check_circle_rounded;
        statusColor = AppColors.statusGreen;
        statusText = l10n.t('messagePlatformDetailWeixinPluginInstalled');
        break;
      case _WeixinPluginStatus.missing:
        statusIcon = Icons.extension_off_rounded;
        statusColor = AppColors.statusAmber;
        statusText = l10n.t('messagePlatformDetailWeixinPluginMissing');
        break;
      case _WeixinPluginStatus.failed:
        statusIcon = Icons.error_rounded;
        statusColor = theme.colorScheme.error;
        statusText = l10n.t('messagePlatformDetailWeixinPluginFailed');
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isChecking)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColor,
                    ),
                  )
                else
                  Icon(statusIcon, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.t('messagePlatformDetailWeixinCommandHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                MessagePlatformConfigService.weixinInstallerCommand,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'DejaVuSansMono',
                ),
              ),
            ),
            if (_weixinPluginError != null &&
                _weixinPluginError!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withAlpha(140),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _weixinPluginError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: isChecking ? null : _openWeixinInstaller,
                  icon: Icon(
                    _weixinPluginStatus == _WeixinPluginStatus.installed
                        ? Icons.refresh_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(
                    l10n.t(
                      _weixinPluginStatus == _WeixinPluginStatus.installed
                          ? 'messagePlatformDetailWeixinRebindAction'
                          : 'messagePlatformDetailWeixinInstallAction',
                    ),
                  ),
                ),
                if (_weixinPluginStatus == _WeixinPluginStatus.failed ||
                    _weixinPluginStatus == _WeixinPluginStatus.missing)
                  OutlinedButton.icon(
                    onPressed: isChecking ? null : _refreshWeixinPluginStatus,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.t('commonRetry')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeixinUsageCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('messagePlatformDetailWeixinUsageTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('messagePlatformDetailWeixinUsageBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeixinFields(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWeixinUsageCard(theme, l10n),
        const SizedBox(height: 16),
        _buildWeixinStatusCard(theme, l10n),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);

    return Scaffold(
      appBar: AppBar(title: Text(widget.platform.name(l10n))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPlatformHeader(theme, iconBg),
          const SizedBox(height: 16),
          if (_isFeishu)
            _buildFeishuFields(theme, l10n)
          else if (_isQqbot)
            _buildQqbotFields(theme, l10n)
          else if (_isWeixin)
            _buildWeixinFields(theme, l10n),
          if (!_isWeixin) ...[
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving || _restartingGateway || !_qqbotPluginReady
                  ? null
                  : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.t('messagePlatformDetailSaveAction')),
            ),
          ],
          if (_isConfigured && !_isQqbot && !_isWeixin) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _removing ? null : _remove,
              child: _removing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.t('messagePlatformDetailRemoveConfiguration')),
            ),
          ],
          if (_isFeishu) ...[
            const SizedBox(height: 12),
            Text(
              l10n.t('messagePlatformDetailSchemaNote'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
