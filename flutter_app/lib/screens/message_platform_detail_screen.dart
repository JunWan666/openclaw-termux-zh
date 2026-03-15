import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/message_platform.dart';
import '../services/message_platform_config_service.dart';

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

  bool get _isConfigured {
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
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _appSecretController.dispose();
    _botNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
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
    final payload = <String, dynamic>{
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('messagePlatformDetailSaved', {
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
          Card(
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
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
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
          if (_isConfigured) ...[
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
          const SizedBox(height: 12),
          Text(
            l10n.t('messagePlatformDetailSchemaNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
