import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/runtime_initialization_view.dart';
import '../providers/setup_provider.dart';
import '../services/preferences_service.dart';
import '../services/provider_config_service.dart';
import 'dashboard_screen.dart';
import 'setup_wizard_screen.dart';

class RuntimeInitializationScreen extends StatefulWidget {
  const RuntimeInitializationScreen({super.key});

  @override
  State<RuntimeInitializationScreen> createState() =>
      _RuntimeInitializationScreenState();
}

class _RuntimeInitializationScreenState
    extends State<RuntimeInitializationScreen> {
  final ScrollController _logController = ScrollController();
  Timer? _progressTimer;
  bool _started = false;
  bool _finishing = false;
  bool _configurationComplete = false;
  double _displayProgress = 0.02;
  int _activityPulse = 0;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted || _configurationComplete) return;
      final state = context.read<SetupProvider>().state;
      final stage = _finishing
          ? RuntimeInitializationStage.finalChecks
          : RuntimeInitializationView.stageFor(state.step);
      setState(() {
        _displayProgress = RuntimeInitializationView.nextDisplayProgress(
          current: _displayProgress,
          stage: stage,
        );
        _activityPulse = (_activityPulse + 1) % 4;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_started || !mounted) return;
    setState(() {
      _started = true;
      _finishing = false;
      _configurationComplete = false;
      _displayProgress = 0.02;
      _lastLogCount = 0;
    });

    final provider = context.read<SetupProvider>();
    provider.reset();
    await provider.runSetup(forceBundledRuntime: true);
    if (!mounted || !provider.state.isComplete) return;
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await ProviderConfigService.ensureInitialAppConfig();
      final prefs = PreferencesService();
      await prefs.init();
      prefs.pendingSetupCompletionChoice = false;
      prefs.setupComplete = true;
      prefs.isFirstRun = false;
      if (!mounted) return;
      setState(() {
        _displayProgress = 1;
        _finishing = false;
        _configurationComplete = true;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isChinese
              ? '本地配置失败：$error'
              : 'Local configuration failed: $error'),
        ),
      );
      setState(() => _finishing = false);
    }
  }

  bool get _isChinese => Localizations.localeOf(context).languageCode == 'zh';

  void _enterHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  void _openOnlineRecovery() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
    );
  }

  void _scrollLogsIfNeeded(int logCount) {
    if (logCount == _lastLogCount) return;
    _lastLogCount = logCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logController.hasClients) return;
      _logController.animateTo(
        _logController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SetupProvider>();
    final state = provider.state;
    final stage = _finishing
        ? RuntimeInitializationStage.finalChecks
        : RuntimeInitializationView.stageFor(state.step);
    final languageCode = Localizations.localeOf(context).languageCode;
    final failed = state.hasError;
    _scrollLogsIfNeeded(provider.logs.length);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: _AmbientBackground()),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 550),
                switchInCurve: Curves.easeOutCubic,
                child: _configurationComplete
                    ? _buildCompletion(context)
                    : _buildProgress(
                        context,
                        provider,
                        stage,
                        languageCode,
                        failed,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletion(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('completion'),
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BrandMark(
              caption: _isChinese ? '初始化完成' : 'SETUP COMPLETE',
            ),
          ),
          const SizedBox(height: 38),
          SizedBox(
            width: 164,
            height: 164,
            child: CustomPaint(
              painter: _CelebrationPainter(colors.primary),
              child: Center(
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colors.primary, colors.tertiary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withAlpha(70),
                        blurRadius: 34,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 62,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _isChinese ? '准备好了，开始探索吧' : 'Ready when you are',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isChinese
                ? 'OpenClaw 已在你的设备上完成部署，默认 AI 服务也已经接通。'
                : 'OpenClaw is deployed on your device and the default AI service is connected.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(220),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.outlineVariant.withAlpha(150)),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow.withAlpha(14),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(
                          colors: [
                            colors.primaryContainer,
                            colors.tertiaryContainer,
                          ],
                        ),
                      ),
                      child: Icon(Icons.auto_awesome_rounded,
                          color: colors.primary),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '7749API（ywd公益）',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 3),
                          Text('DeepSeek V4 Flash'),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _isChinese ? '已连接' : 'ONLINE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: colors.outlineVariant.withAlpha(120)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _ReadyPill(
                      icon: Icons.dns_outlined,
                      label: _isChinese ? '本地服务就绪' : 'Local service ready',
                    ),
                    _ReadyPill(
                      icon: Icons.lock_outline_rounded,
                      label: _isChinese ? '数据留在本机' : 'Local-first data',
                    ),
                    _ReadyPill(
                      icon: Icons.upgrade_rounded,
                      label: _isChinese ? '支持随时升级' : 'Upgrade anytime',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const Key('enter-home-button'),
              onPressed: _enterHome,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_isChinese ? '进入 OpenClaw' : 'Enter OpenClaw'),
                  const SizedBox(width: 9),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(
    BuildContext context,
    SetupProvider provider,
    RuntimeInitializationStage stage,
    String languageCode,
    bool failed,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activity = RuntimeInitializationView.activity(stage, languageCode);
    final stageIndex = _stageIndex(stage);

    return Padding(
      key: const ValueKey('progress'),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: _BrandMark(caption: 'LOCAL RUNTIME')),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.surface.withAlpha(180),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: failed ? colors.error : colors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (failed ? colors.error : colors.primary)
                                .withAlpha(100),
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      failed
                          ? (_isChinese ? '需要处理' : 'ATTENTION')
                          : (_isChinese ? '设备内运行' : 'ON DEVICE'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _ProgressOrb(
                progress: _displayProgress,
                color: failed ? colors.error : colors.primary,
                pulse: _activityPulse,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      RuntimeInitializationView.label(
                        failed ? RuntimeInitializationStage.failed : stage,
                        languageCode,
                      ),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        failed
                            ? (_isChinese
                                ? '没有修改你的数据，可以安全重试'
                                : 'Your data is unchanged; retry safely')
                            : activity,
                        key: ValueKey('$stage-$activity'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _StageRail(activeIndex: stageIndex, failed: failed),
          const SizedBox(height: 18),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surface.withAlpha(205),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.outlineVariant.withAlpha(170)),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withAlpha(12),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 11),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer.withAlpha(170),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.route_rounded,
                            size: 17,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isChinese ? '部署动态' : 'Deployment activity',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          failed
                              ? (_isChinese ? '已暂停' : 'PAUSED')
                              : (_isChinese ? '实时' : 'LIVE'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: failed ? colors.error : colors.primary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1, color: colors.outlineVariant.withAlpha(110)),
                  Expanded(
                    child: ListView.builder(
                      key: const Key('initialization-log'),
                      controller: _logController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      itemCount: provider.logs.length + (failed ? 0 : 1),
                      itemBuilder: (context, index) {
                        final active = index == provider.logs.length;
                        final text = active ? activity : provider.logs[index];
                        return _ActivityRow(
                          text: text,
                          active: active,
                          isLast: index == provider.logs.length,
                          pulse: _activityPulse,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!failed)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    size: 15, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _isChinese
                        ? '保持应用在前台，通常几分钟内完成'
                        : 'Keep the app open; this usually takes a few minutes',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          if (failed) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: provider.isRunning
                    ? null
                    : () {
                        setState(() => _started = false);
                        _start();
                      },
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_isChinese ? '重新尝试' : 'Try again'),
              ),
            ),
            const SizedBox(height: 7),
            TextButton(
              onPressed: _openOnlineRecovery,
              child: Text(
                  _isChinese ? '打开高级恢复选项' : 'Open advanced recovery options'),
            ),
          ],
        ],
      ),
    );
  }

  int _stageIndex(RuntimeInitializationStage stage) {
    return switch (stage) {
      RuntimeInitializationStage.checkingDevice => 0,
      RuntimeInitializationStage.preparingRuntime => 1,
      RuntimeInitializationStage.deployingCore => 2,
      RuntimeInitializationStage.configuringService ||
      RuntimeInitializationStage.finalChecks ||
      RuntimeInitializationStage.complete =>
        3,
      RuntimeInitializationStage.failed => 0,
    };
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [colors.surface, const Color(0xFF11172B), colors.surface]
              : [
                  const Color(0xFFF8FAFF),
                  const Color(0xFFF1F3FF),
                  colors.surface
                ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -110,
            right: -90,
            child: _Glow(
                size: 270, color: colors.primary.withAlpha(dark ? 32 : 24)),
          ),
          Positioned(
            bottom: -130,
            left: -100,
            child: _Glow(
                size: 300, color: colors.tertiary.withAlpha(dark ? 25 : 20)),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withAlpha(210),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Image.asset('assets/ic_launcher.png'),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OPENCLAW',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            Text(
              caption,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressOrb extends StatelessWidget {
  const _ProgressOrb({
    required this.progress,
    required this.color,
    required this.pulse,
  });

  final double progress;
  final Color color;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          painter: _ProgressOrbPainter(value, color, pulse),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(value * 100).round()}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                ),
                Text(
                  'PERCENT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
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

class _ProgressOrbPainter extends CustomPainter {
  _ProgressOrbPainter(this.progress, this.color, this.pulse);

  final double progress;
  final Color color;
  final int pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - 7);
    canvas.drawCircle(
      center,
      size.width / 2 - 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = color.withAlpha(25),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 7
        ..shader = SweepGradient(
          colors: [color.withAlpha(120), color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    final angle = -math.pi / 2 + math.pi * 2 * progress;
    final dot = center +
        Offset(math.cos(angle), math.sin(angle)) * (size.width / 2 - 7);
    canvas.drawCircle(dot, 3.5 + pulse * .25, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ProgressOrbPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.pulse != pulse;
}

class _StageRail extends StatelessWidget {
  const _StageRail({required this.activeIndex, required this.failed});

  final int activeIndex;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(4, (index) {
        final done = index < activeIndex;
        final active = index == activeIndex;
        final color = failed && active
            ? colors.error
            : (done || active ? colors.primary : colors.outlineVariant);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 3 ? 0 : 7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              height: active ? 6 : 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
                boxShadow: active
                    ? [BoxShadow(color: color.withAlpha(80), blurRadius: 8)]
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.text,
    required this.active,
    required this.isLast,
    required this.pulse,
  });

  final String text;
  final bool active;
  final bool isLast;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        active ? theme.colorScheme.primary : theme.colorScheme.outline;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: active ? 8 + pulse * .35 : 7,
                  height: active ? 8 + pulse * .35 : 7,
                  decoration: BoxDecoration(
                    color: active ? color : color.withAlpha(100),
                    shape: BoxShape.circle,
                    boxShadow: active
                        ? [
                            BoxShadow(
                                color: color.withAlpha(100), blurRadius: 7)
                          ]
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: active
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'DejaVuSansMono',
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyPill extends StatelessWidget {
  const _ReadyPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withAlpha(100),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 12; i++) {
      final angle = math.pi * 2 * i / 12;
      final near = center + Offset(math.cos(angle), math.sin(angle)) * 67;
      final far = center + Offset(math.cos(angle), math.sin(angle)) * 75;
      canvas.drawLine(
        near,
        far,
        Paint()
          ..color = color.withAlpha(i.isEven ? 130 : 65)
          ..strokeWidth = i.isEven ? 2.2 : 1.3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      center,
      68,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withAlpha(35),
    );
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) =>
      oldDelegate.color != color;
}
