import 'package:flutter/material.dart';

import '../models/environment_recovery.dart';
import '../services/environment_recovery_service.dart';
import '../services/bootstrap_service.dart';
import 'backup_manager_screen.dart';
import 'dashboard_screen.dart';
import 'terminal_screen.dart';

class EnvironmentRecoveryScreen extends StatefulWidget {
  const EnvironmentRecoveryScreen({
    super.key,
    required this.assessment,
  });

  final EnvironmentAssessment assessment;

  @override
  State<EnvironmentRecoveryScreen> createState() =>
      _EnvironmentRecoveryScreenState();
}

class _EnvironmentRecoveryScreenState extends State<EnvironmentRecoveryScreen> {
  final _service = EnvironmentRecoveryService();
  late EnvironmentAssessment _assessment = widget.assessment;
  bool _busy = false;
  String? _error;

  bool get _isZh =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var result = await _service.inspect();
      if (result.canAutoRepair) {
        result = await _service.repair();
      }
      if (!mounted) return;
      if (result.shouldEnterDashboard) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (_) => false,
        );
        return;
      }
      setState(() => _assessment = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBundledRuntime() async {
    if (_busy) return;
    final zh = _isZh;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(zh ? '恢复内置运行环境' : 'Restore bundled runtime'),
            content: Text(
              zh
                  ? '将重新部署 APK 内置运行环境。现有配置、Token、Agents、Workspace 和 Memory 会被保留。'
                  : 'The APK bundled runtime will be redeployed. Existing configuration, tokens, agents, workspace, and memory will be preserved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(zh ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(zh ? '开始恢复' : 'Restore'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var completed = false;
      String? failure;
      await BootstrapService().runFullSetup(
        forceBundledRuntime: true,
        onProgress: (state) {
          completed = state.isComplete;
          failure = state.error;
          if (!mounted) return;
          setState(() {
            _error = state.error ??
                (state.detail == null
                    ? state.message
                    : '${state.message}\n${state.detail}');
          });
        },
      );
      if (!completed) {
        throw StateError(failure ?? 'Bundled runtime restore did not complete');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = _isZh;
    final interrupted =
        _assessment.state == EnvironmentRecoveryState.upgradeInterrupted;
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '环境恢复' : 'Environment Recovery'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      interrupted
                          ? Icons.sync_problem_rounded
                          : Icons.health_and_safety_outlined,
                      size: 42,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      interrupted
                          ? (zh ? '检测到升级中断' : 'Upgrade interrupted')
                          : (zh
                              ? '现有环境需要人工确认'
                              : 'Existing environment needs attention'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _assessment.reason ??
                          (zh
                              ? 'RootFS 和用户数据会被保留，应用不会自动重装或清除数据。'
                              : 'RootFS and user data are preserved. The app will not reinstall or delete data automatically.'),
                    ),
                    if (_assessment.snapshot.gatewayRunning) ...[
                      const SizedBox(height: 12),
                      Text(
                        zh
                            ? '检测到 Gateway 仍在运行，未停止现有进程。'
                            : 'A running Gateway was detected and left untouched.',
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _retry,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(zh ? '重新检测并修复' : 'Check and repair again'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restoreBundledRuntime,
              icon: const Icon(Icons.restore_rounded),
              label: Text(
                zh
                    ? '恢复 APK 内置的 OpenClaw 2026.3.23'
                    : 'Restore bundled OpenClaw 2026.3.23',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TerminalScreen()),
              ),
              icon: const Icon(Icons.terminal_rounded),
              label: Text(zh ? '打开终端' : 'Open terminal'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BackupManagerScreen(),
                ),
              ),
              icon: const Icon(Icons.backup_outlined),
              label: Text(zh ? '导出或管理备份' : 'Export or manage backups'),
            ),
            const SizedBox(height: 16),
            Text(
              zh
                  ? '为保护数据，此页面不提供一键删除或自动重装。'
                  : 'To protect your data, this page does not offer one-tap deletion or automatic reinstallation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
