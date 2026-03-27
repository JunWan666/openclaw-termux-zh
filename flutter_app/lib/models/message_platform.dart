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
  final String? connectUrl;

  const MessagePlatform({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.configPath,
    required this.icon,
    required this.color,
    this.connectUrl,
  });

  String name(AppLocalizations l10n) => l10n.t(nameKey);

  String description(AppLocalizations l10n) => l10n.t(descriptionKey);

  bool get isFeishu => id == feishu.id;

  bool get isQqbot => id == qqbot.id;

  bool get isWeixin => id == weixin.id;

  static const feishu = MessagePlatform(
    id: 'feishu',
    nameKey: 'messagePlatformNameFeishu',
    descriptionKey: 'messagePlatformDescriptionFeishu',
    configPath: 'channels.feishu',
    icon: Icons.chat_bubble_rounded,
    color: Color(0xFF1456F0),
  );

  static const qqbot = MessagePlatform(
    id: 'qqbot',
    nameKey: 'messagePlatformNameQqbot',
    descriptionKey: 'messagePlatformDescriptionQqbot',
    configPath: 'channels.qqbot',
    icon: Icons.smart_toy_rounded,
    color: Color(0xFF1677FF),
    connectUrl: 'https://q.qq.com/qqbot/openclaw/login.html',
  );

  static const weixin = MessagePlatform(
    id: 'weixin',
    nameKey: 'messagePlatformNameWeixin',
    descriptionKey: 'messagePlatformDescriptionWeixin',
    configPath: 'channels.weixin',
    icon: Icons.chat_rounded,
    color: Color(0xFF07C160),
  );

  static const all = [
    feishu,
    qqbot,
    weixin,
  ];
}
