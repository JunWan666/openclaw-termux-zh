import 'package:flutter/material.dart';

import '../services/preferences_service.dart';
import 'runtime_initialization_screen.dart';

class RuntimeWelcomeScreen extends StatefulWidget {
  const RuntimeWelcomeScreen({super.key});

  @override
  State<RuntimeWelcomeScreen> createState() => _RuntimeWelcomeScreenState();
}

class _RuntimeWelcomeScreenState extends State<RuntimeWelcomeScreen> {
  bool _accepted = false;
  bool _saving = false;

  bool get _isChinese => Localizations.localeOf(context).languageCode == 'zh';

  Future<void> _continue() async {
    if (!_accepted || _saving) return;
    setState(() => _saving = true);
    final prefs = PreferencesService();
    await prefs.init();
    await prefs.acceptBundledRuntimeAgreement();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RuntimeInitializationScreen()),
    );
  }

  Future<void> _showPolicy({required bool privacy}) {
    final title = privacy
        ? (_isChinese ? '隐私说明' : 'Privacy notice')
        : (_isChinese ? '使用说明' : 'Terms of use');
    final body = privacy
        ? (_isChinese
            ? 'OpenClaw 会在应用私有目录中创建本地运行环境和配置。APK 不预置 API Key、账号凭据或个人数据。你后续填写的模型服务密钥仅用于所选服务配置，请自行了解对应服务的隐私政策。'
            : 'OpenClaw creates its runtime and configuration in app-private storage. The APK contains no API keys, account credentials, or personal data. Credentials you add later are used for your selected model service; review that provider’s privacy policy separately.')
        : (_isChinese
            ? '应用会从安装包在本机部署 OpenClaw 2026.3.23，首次准备可能需要几分钟。请保持应用在前台，并确保至少有 1 GB 可用空间。完成后可在首页配置 AI 提供商，后续版本升级由版本管理功能处理。'
            : 'The app deploys OpenClaw 2026.3.23 locally from the installation package. Initial preparation may take several minutes. Keep the app in the foreground and ensure at least 1 GB of free space. Configure an AI provider from the dashboard afterward; later upgrades are handled by version management.');
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_isChinese ? '知道了' : 'Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Image.asset('assets/ic_launcher.png', width: 96, height: 96),
                const SizedBox(height: 28),
                Text(
                  _isChinese ? '欢迎使用 OpenClaw' : 'Welcome to OpenClaw',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isChinese
                      ? 'OpenClaw 会在本机创建独立的 AI 助手运行环境。首次准备大约需要几分钟，完成后即可进入首页配置 AI 提供商。'
                      : 'OpenClaw creates an independent local AI assistant runtime. Initial preparation takes a few minutes, then you can configure an AI provider from the dashboard.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withAlpha(120),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone_android,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isChinese
                              ? '核心组件已包含在安装包中，默认安装 OpenClaw 2026.3.23。'
                              : 'Core components are included in the app package. OpenClaw 2026.3.23 is installed by default.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _accepted,
                  onChanged: (value) =>
                      setState(() => _accepted = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(_isChinese
                      ? '我已阅读并同意使用说明与隐私说明'
                      : 'I have read and accept the terms and privacy notice'),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _showPolicy(privacy: false),
                      child: Text(_isChinese ? '使用说明' : 'Terms'),
                    ),
                    TextButton(
                      onPressed: () => _showPolicy(privacy: true),
                      child: Text(_isChinese ? '隐私说明' : 'Privacy'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _accepted && !_saving ? _continue : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(_isChinese ? '同意并继续' : 'Agree and continue'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
