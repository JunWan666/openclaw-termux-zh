import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';

class CommandShortcutsScreen extends StatelessWidget {
  const CommandShortcutsScreen({super.key});

  static final List<_GuideSpec> _guides = [
    const _GuideSpec(
      icon: Icons.rocket_launch_outlined,
      titleZh: '如何重新引导并安装守护进程？',
      titleEn: 'How do I re-run onboarding and install the daemon?',
      summaryZh: '重新执行 onboarding，并把 daemon 一起补装上。',
      summaryEn:
          'Run onboarding again and install the daemon in the same pass.',
      blocksZh: [
        _GuideBlock.markdown('''
## 适用场景

当你想重新走一次 OpenClaw 的初始化流程，或者之前没有安装 daemon，现在想一起补上时，可以用这个方式。

## 操作步骤

### 1. 打开终端

进入首页的“终端”页面，或者使用你常用的系统终端。

### 2. 执行命令
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw onboard --install-daemon',
          textEn: 'openclaw onboard --install-daemon',
        ),
        _GuideBlock.markdown('''
### 3. 按提示完成引导

按照交互提示重新配置模型、工作目录、网关绑定等内容。

### 4. 返回首页验证

完成后回到首页，重新启动网关，确认服务已经正常工作。

## 补充说明

- 如果你只是想修改局部配置，不一定要重新引导，通常 `openclaw configure` 就够了。
- 建议在没有重要会话运行时再做这类操作。
'''),
      ],
      blocksEn: [
        _GuideBlock.markdown('''
## When to use this

Use this when you want to run the onboarding flow again, or when the daemon was not installed before and you want to add it now.

## Steps

### 1. Open a terminal

Use the Terminal screen in the app, or your preferred system terminal.

### 2. Run the command
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw onboard --install-daemon',
          textEn: 'openclaw onboard --install-daemon',
        ),
        _GuideBlock.markdown('''
### 3. Follow the prompts

Complete the interactive flow for model setup, workspace paths, and gateway binding.

### 4. Verify from the dashboard

Return to the dashboard, restart the gateway, and confirm that everything works.

## Notes

- If you only need to change part of the configuration, `openclaw configure` is usually enough.
- It is safer to do this when the gateway is not serving an important live session.
'''),
      ],
    ),
    const _GuideSpec(
      icon: Icons.tune,
      titleZh: '如何切换到完整工具配置？',
      titleEn: 'How do I switch to the full tools profile?',
      summaryZh: '把 `tools.profile` 切换成 `full`，启用更完整的工具集。',
      summaryEn:
          'Switch `tools.profile` to `full` to enable a broader tool set.',
      blocksZh: [
        _GuideBlock.markdown('''
## 适用场景

如果你当前环境使用的是精简工具配置，导致某些能力不可用，可以把工具档位切换到 `full`。

## 操作步骤

### 1. 打开终端

进入终端页面。

### 2. 执行命令
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw config set tools.profile full',
          textEn: 'openclaw config set tools.profile full',
        ),
        _GuideBlock.markdown('''
### 3. 检查是否生效

如有需要，可以打开 `openclaw.json`，确认 `tools.profile` 已经变成 `full`。

### 4. 重启网关并验证

建议重启一次网关，再测试之前缺失的工具能力是否已经恢复。

## 补充说明

- `full` 会启用更完整的工具能力，但也可能需要更多权限或环境支持。
- 如果只是临时排查问题，改完后记得重新验证你的正常工作流。
'''),
      ],
      blocksEn: [
        _GuideBlock.markdown('''
## When to use this

If your environment is using a reduced tools profile and some capabilities are missing, switch it to `full`.

## Steps

### 1. Open a terminal

Go to the Terminal screen.

### 2. Run the command
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw config set tools.profile full',
          textEn: 'openclaw config set tools.profile full',
        ),
        _GuideBlock.markdown('''
### 3. Verify the config

If needed, open `openclaw.json` and confirm that `tools.profile` is now `full`.

### 4. Restart and test

Restart the gateway once and test whether the missing tools are available again.

## Notes

- `full` enables a broader tool set, but it can also require more permissions or environment support.
- If you are changing this only for debugging, re-check your normal workflow afterwards.
'''),
      ],
    ),
    const _GuideSpec(
      icon: Icons.settings_suggest_outlined,
      titleZh: '如何重新进入交互式配置？',
      titleEn: 'How do I re-enter interactive configuration?',
      summaryZh: '重新打开 `openclaw configure` 的交互式配置流程。',
      summaryEn: 'Open the interactive `openclaw configure` flow again.',
      blocksZh: [
        _GuideBlock.markdown('''
## 适用场景

如果你想重新调整模型、工作目录、网关、Web 或 channel 相关配置，最直接的方法就是重新进入交互式配置。

## 操作步骤

### 1. 打开终端

进入终端页面。

### 2. 执行命令
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw configure',
          textEn: 'openclaw configure',
        ),
        _GuideBlock.markdown('''
### 3. 进入需要修改的配置项

按需进入你想修改的配置部分。

### 4. 保存并退出

修改完成后一路选择 `continue`，或按提示保存退出。

### 5. 如有必要，回首页重启网关

如果你改动了网关绑定、认证或控制台地址，建议回到首页重启一次网关。

## 补充说明

- 这是最稳妥的官方交互式改配置入口。
- 如果你已经很熟悉 JSON 结构，也可以直接去“修改配置文件”页面手动编辑。
'''),
      ],
      blocksEn: [
        _GuideBlock.markdown('''
## When to use this

If you want to adjust models, workspace paths, gateway settings, web settings, or channels again, the interactive configure flow is the most direct path.

## Steps

### 1. Open a terminal

Go to the Terminal screen.

### 2. Run the command
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw configure',
          textEn: 'openclaw configure',
        ),
        _GuideBlock.markdown('''
### 3. Enter the sections you want to change

Open only the parts you want to adjust.

### 4. Save and exit

When you are done, continue through the prompts until the flow exits.

### 5. Restart the gateway if needed

If you changed gateway binding, auth, or dashboard address, restart the gateway from the dashboard afterwards.

## Notes

- This is the safest official interactive entry for changing configuration.
- If you already know the JSON structure well, you can also edit the config file directly in the app.
'''),
      ],
    ),
    const _GuideSpec(
      icon: Icons.wifi_tethering,
      titleZh: '如何进行局域网访问？',
      titleEn: 'How do I enable LAN access?',
      summaryZh: '按顺序完成 gateway 绑定、allowedOrigins、浏览器安全例外和设备授权。',
      summaryEn:
          'Set the gateway to LAN mode, then handle allowed origins, browser trust, and device approval in order.',
      blocksZh: [
        _GuideBlock.markdown('''
## 操作步骤

### 1. 进入交互配置

先在终端里进入 OpenClaw 的交互式配置。
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw configure',
          textEn: 'openclaw configure',
        ),
        _GuideBlock.markdown('''
### 2. 选择 Local 和 gateway

进入交互配置后，先选择 `Local`，然后选择 `gateway`。

### 3. 设置 LAN 绑定

- 端口直接回车
- `gateway bind mode` 选择 `LAN`
- `gateway auth` 保持默认 `token`

### 4. 完成配置

后面的提示基本一路回车，回到交互式配置主菜单后，选择 `continue` 完成配置。

### 5. 让另一台局域网设备先访问一次

用另一台局域网设备访问 OpenClaw，第一次通常会看到类似下面的报错：
'''),
        _GuideBlock.code(
          titleZh: '常见报错',
          titleEn: 'Expected first error',
          textZh:
              'origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)',
          textEn:
              'origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)',
        ),
        _GuideBlock.markdown('''
### 6. 修改 `controlUi.allowedOrigins`

打开配置文件，在 `controlUi.allowedOrigins` 数组下面添加当前局域网访问地址加 `:18789` 端口，保存后再刷新页面。
'''),
        _GuideBlock.code(
          titleZh: '示例地址',
          titleEn: 'Example origin',
          textZh: 'http://192.168.1.23:18789',
          textEn: 'http://192.168.1.23:18789',
        ),
        _GuideBlock.markdown('''
### 7. 如果浏览器提示需要设备身份

电脑页面刷新后，通常会变成下面这类提示：
'''),
        _GuideBlock.code(
          titleZh: '常见提示',
          titleEn: 'Expected browser message',
          textZh:
              'control ui requires device identity (use HTTPS or localhost secure context)',
          textEn:
              'control ui requires device identity (use HTTPS or localhost secure context)',
        ),
        _GuideBlock.markdown('''
### 8. 打开浏览器对应的 flags 页面

根据你正在使用的浏览器，打开对应的地址，把相关选项设置为 `Enabled`。
'''),
        _GuideBlock.code(
          titleZh: 'Chrome 地址',
          titleEn: 'Chrome URL',
          textZh: 'chrome://flags/#unsafely-treat-insecure-origin-as-secure',
          textEn: 'chrome://flags/#unsafely-treat-insecure-origin-as-secure',
        ),
        _GuideBlock.code(
          titleZh: 'Edge 地址',
          titleEn: 'Edge URL',
          textZh: 'edge://flags/#unsafely-treat-insecure-origin-as-secure',
          textEn: 'edge://flags/#unsafely-treat-insecure-origin-as-secure',
        ),
        _GuideBlock.markdown('''
### 9. 在浏览器里豁免你的局域网地址

在下方的文本框中输入你要“豁免”的网址或 IP 地址，如果有多个就用逗号隔开。然后点击页面底部的 `Relaunch`，浏览器会自动重启。

重启后，页面应该会变成 `pairing required` 提示。这时需要填写网关令牌，也就是 token。

### 10. 在手机终端批准设备请求

接下来回到手机终端，先查看待批准请求，再执行批准命令。
'''),
        _GuideBlock.code(
          titleZh: '查看待批准请求',
          titleEn: 'List pending device requests',
          textZh: 'openclaw devices list',
          textEn: 'openclaw devices list',
        ),
        _GuideBlock.code(
          titleZh: '批准请求',
          titleEn: 'Approve the request',
          textZh: 'openclaw devices approve <请求ID>',
          textEn: 'openclaw devices approve <request-id>',
        ),
        _GuideBlock.prompt(
          titleZh: '可直接发给 OpenClaw 的提示词',
          titleEn: 'Prompt you can send to OpenClaw',
          textZh:
              '请帮我在当前终端完成局域网设备授权：先执行 `openclaw devices list` 找出待审批的请求 ID，再执行 `openclaw devices approve <请求ID>`，最后把执行结果回显给我。',
          textEn:
              'Please help me approve the LAN device from the current terminal: first run `openclaw devices list` to find the pending request ID, then run `openclaw devices approve <request-id>`, and finally show me the command output.',
        ),
        _GuideBlock.markdown('''
## 补充说明

- `allowedOrigins` 一定要填写实际访问地址，不能只写 IP 不带协议或端口。
- 浏览器 flag 更适合局域网测试场景。
- 如果你后面改了访问地址或端口，也要同步更新 `allowedOrigins`。
'''),
      ],
      blocksEn: [
        _GuideBlock.markdown('''
## Steps

### 1. Enter interactive configuration

Open the OpenClaw interactive configuration flow from a terminal.
'''),
        _GuideBlock.code(
          titleZh: '执行命令',
          titleEn: 'Run this command',
          textZh: 'openclaw configure',
          textEn: 'openclaw configure',
        ),
        _GuideBlock.markdown('''
### 2. Choose Local and then gateway

Inside the interactive flow, choose `Local`, then choose `gateway`.

### 3. Set LAN binding

- Press Enter for the port
- Choose `LAN` for `gateway bind mode`
- Keep `gateway auth` on the default `token`

### 4. Finish the configuration

Continue through the remaining prompts, then choose `continue` from the main menu to finish.

### 5. Visit from another device on the same LAN

Open OpenClaw from another device on the same LAN. The first visit usually shows this error:
'''),
        _GuideBlock.code(
          titleZh: '常见报错',
          titleEn: 'Expected first error',
          textZh:
              'origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)',
          textEn:
              'origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)',
        ),
        _GuideBlock.markdown('''
### 6. Update `controlUi.allowedOrigins`

Open the config file and add the actual LAN access address plus `:18789` to `controlUi.allowedOrigins`, then save and refresh.
'''),
        _GuideBlock.code(
          titleZh: '示例地址',
          titleEn: 'Example origin',
          textZh: 'http://192.168.1.23:18789',
          textEn: 'http://192.168.1.23:18789',
        ),
        _GuideBlock.markdown('''
### 7. If the browser asks for device identity

After refreshing, the desktop page usually changes to this message:
'''),
        _GuideBlock.code(
          titleZh: '常见提示',
          titleEn: 'Expected browser message',
          textZh:
              'control ui requires device identity (use HTTPS or localhost secure context)',
          textEn:
              'control ui requires device identity (use HTTPS or localhost secure context)',
        ),
        _GuideBlock.markdown('''
### 8. Open the matching browser flags page

Open the correct flags page for your browser and set the related option to `Enabled`.
'''),
        _GuideBlock.code(
          titleZh: 'Chrome 地址',
          titleEn: 'Chrome URL',
          textZh: 'chrome://flags/#unsafely-treat-insecure-origin-as-secure',
          textEn: 'chrome://flags/#unsafely-treat-insecure-origin-as-secure',
        ),
        _GuideBlock.code(
          titleZh: 'Edge 地址',
          titleEn: 'Edge URL',
          textZh: 'edge://flags/#unsafely-treat-insecure-origin-as-secure',
          textEn: 'edge://flags/#unsafely-treat-insecure-origin-as-secure',
        ),
        _GuideBlock.markdown('''
### 9. Whitelist your LAN address in the browser

Enter the LAN URL or IP you want to exempt in the text box. If there are multiple entries, separate them with commas. Then press `Relaunch` so the browser restarts.

After restart, the page should change to `pairing required`. At that point, enter the gateway token.

### 10. Approve the device from the phone terminal

Back on the phone terminal, list pending requests first, then approve the request.
'''),
        _GuideBlock.code(
          titleZh: '查看待批准请求',
          titleEn: 'List pending device requests',
          textZh: 'openclaw devices list',
          textEn: 'openclaw devices list',
        ),
        _GuideBlock.code(
          titleZh: '批准请求',
          titleEn: 'Approve the request',
          textZh: 'openclaw devices approve <请求ID>',
          textEn: 'openclaw devices approve <request-id>',
        ),
        _GuideBlock.prompt(
          titleZh: '可直接发给 OpenClaw 的提示词',
          titleEn: 'Prompt you can send to OpenClaw',
          textZh:
              '请帮我在当前终端完成局域网设备授权：先执行 `openclaw devices list` 找出待审批的请求 ID，再执行 `openclaw devices approve <请求ID>`，最后把执行结果回显给我。',
          textEn:
              'Please help me approve the LAN device from the current terminal: first run `openclaw devices list` to find the pending request ID, then run `openclaw devices approve <request-id>`, and finally show me the command output.',
        ),
        _GuideBlock.markdown('''
## Notes

- `allowedOrigins` must use the real access address, including protocol and port.
- The browser flag is best kept for LAN testing scenarios.
- If you later change the access address or port, update `allowedOrigins` too.
'''),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_screenTitle(context))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _guides.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _screenSubtitle(context),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            );
          }

          final guide = _guides[index - 1];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withAlpha(18),
                child: Text(
                  '$index',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                guide.title(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  guide.summary(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _GuideDetailScreen(
                      order: index,
                      guide: guide,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  static String _screenTitle(BuildContext context) =>
      _isChinese(context) ? '常用说明' : 'Guides';

  static String _screenSubtitle(BuildContext context) => _isChinese(context)
      ? '这里整理了常见操作说明。点击条目可进入详细页面查看步骤，命令、浏览器地址和提示词都支持一键复制。'
      : 'This page collects common how-to guides. Open an item to view the steps, and use the copy buttons for commands, browser URLs, and prompts.';
}

class _GuideDetailScreen extends StatelessWidget {
  const _GuideDetailScreen({
    required this.order,
    required this.guide,
  });

  final int order;
  final _GuideSpec guide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markdownTheme = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
      h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      h3: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'DejaVuSansMono',
        fontSize: 12,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(16),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
      listBullet: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text('$order. ${guide.title(context)}')),
      body: SelectionArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: guide.blocks(context).length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withAlpha(18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          guide.icon,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          guide.summary(context),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final block = guide.blocks(context)[index - 1];
            switch (block.type) {
              case _GuideBlockType.markdown:
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MarkdownBody(
                      data: block.text(context),
                      selectable: true,
                      styleSheet: markdownTheme,
                    ),
                  ),
                );
              case _GuideBlockType.code:
              case _GuideBlockType.prompt:
                return _SectionCard(
                  title: block.title(context),
                  child: _CopyBlock(
                    text: block.text(context),
                    monospace: block.monospace,
                  ),
                );
            }
          },
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title?.isNotEmpty == true) ...[
              Text(
                title!,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _CopyBlock extends StatelessWidget {
  const _CopyBlock({
    required this.text,
    required this.monospace,
  });

  final String text;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceAlt =
        isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: monospace ? 'DejaVuSansMono' : null,
                fontWeight: monospace ? FontWeight.w600 : FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.t('commonCopy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.t('commonCopiedToClipboard'),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _GuideSpec {
  const _GuideSpec({
    required this.icon,
    required this.titleZh,
    required this.titleEn,
    required this.summaryZh,
    required this.summaryEn,
    required this.blocksZh,
    required this.blocksEn,
  });

  final IconData icon;
  final String titleZh;
  final String titleEn;
  final String summaryZh;
  final String summaryEn;
  final List<_GuideBlock> blocksZh;
  final List<_GuideBlock> blocksEn;

  String title(BuildContext context) =>
      CommandShortcutsScreen._isChinese(context) ? titleZh : titleEn;

  String summary(BuildContext context) =>
      CommandShortcutsScreen._isChinese(context) ? summaryZh : summaryEn;

  List<_GuideBlock> blocks(BuildContext context) =>
      CommandShortcutsScreen._isChinese(context) ? blocksZh : blocksEn;
}

enum _GuideBlockType { markdown, code, prompt }

class _GuideBlock {
  const _GuideBlock.markdown(String text)
      : type = _GuideBlockType.markdown,
        textZh = text,
        textEn = text,
        titleZh = null,
        titleEn = null,
        monospace = false;

  const _GuideBlock.code({
    required this.titleZh,
    required this.titleEn,
    required this.textZh,
    required this.textEn,
  })  : type = _GuideBlockType.code,
        monospace = true;

  const _GuideBlock.prompt({
    required this.titleZh,
    required this.titleEn,
    required this.textZh,
    required this.textEn,
  })  : type = _GuideBlockType.prompt,
        monospace = false;

  final _GuideBlockType type;
  final String textZh;
  final String textEn;
  final String? titleZh;
  final String? titleEn;
  final bool monospace;

  String text(BuildContext context) =>
      CommandShortcutsScreen._isChinese(context) ? textZh : textEn;

  String? title(BuildContext context) =>
      CommandShortcutsScreen._isChinese(context) ? titleZh : titleEn;
}
