import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Metadata for a messaging platform channel that can be configured
/// for the OpenClaw gateway.
class MessagePlatform {
  final String id;
  final String nameKey;
  final String descriptionKey;
  final String configPath;
  final IconData icon;
  final Color color;

  const MessagePlatform({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.configPath,
    required this.icon,
    required this.color,
  });

  String name(AppLocalizations l10n) => l10n.t(nameKey);

  String description(AppLocalizations l10n) => l10n.t(descriptionKey);

  static const feishu = MessagePlatform(
    id: 'feishu',
    nameKey: 'messagePlatformNameFeishu',
    descriptionKey: 'messagePlatformDescriptionFeishu',
    configPath: 'channels.feishu',
    icon: Icons.chat_bubble_rounded,
    color: Color(0xFF1456F0),
  );

  static const all = [
    feishu,
  ];
}
