import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/message_platform.dart';
import '../services/message_platform_config_service.dart';
import 'message_platform_detail_screen.dart';

/// Lists all supported messaging platform channels.
class MessagePlatformsScreen extends StatefulWidget {
  const MessagePlatformsScreen({super.key});

  @override
  State<MessagePlatformsScreen> createState() => _MessagePlatformsScreenState();
}

class _MessagePlatformsScreenState extends State<MessagePlatformsScreen> {
  Map<String, dynamic> _platforms = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final config = await MessagePlatformConfigService.readConfig();
    if (!mounted) return;
    setState(() {
      _platforms = config['platforms'] as Map<String, dynamic>? ?? {};
      _loading = false;
    });
  }

  Future<void> _openPlatform(MessagePlatform platform) async {
    final platformConfig = _platforms[platform.id] as Map<String, dynamic>?;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MessagePlatformDetailScreen(
          platform: platform,
          existingConfig: platformConfig,
        ),
      ),
    );
    if (result == true) {
      _refresh();
    }
  }

  bool _isConfigured(MessagePlatform platform) {
    final config = _platforms[platform.id] as Map<String, dynamic>?;
    if (config?['configured'] == true) {
      return true;
    }
    if (platform.isWeixin) {
      return config != null && config.isNotEmpty;
    }
    final appId = config?['appId'] as String?;
    final appSecret = config?['appSecret'] as String?;
    return appId != null &&
        appId.isNotEmpty &&
        appSecret != null &&
        appSecret.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('messagePlatformsScreenTitle'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.t('messagePlatformsScreenIntro'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final platform in MessagePlatform.all)
                  _buildPlatformCard(theme, platform, isDark),
              ],
            ),
    );
  }

  Widget _buildPlatformCard(
    ThemeData theme,
    MessagePlatform platform,
    bool isDark,
  ) {
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);
    final isConfigured = _isConfigured(platform);
    final l10n = context.l10n;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openPlatform(platform),
        borderRadius: BorderRadius.circular(12),
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
                child: Icon(platform.icon, color: platform.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          platform.name(l10n),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isConfigured) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.statusGreen.withAlpha(25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              l10n.t('messagePlatformsStatusConfigured'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.statusGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      platform.description(l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
