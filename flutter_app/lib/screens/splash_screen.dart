import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants.dart';
import '../services/native_bridge.dart';
import '../services/preferences_service.dart';
import '../services/provider_config_service.dart';
import '../services/environment_recovery_service.dart';
import '../services/bootstrap_service.dart';
import '../models/environment_recovery.dart';
import 'environment_recovery_screen.dart';
import 'runtime_initialization_screen.dart';
import 'runtime_welcome_screen.dart';
import 'setup_wizard_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _status = 'Loading...';
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _checkAndRoute();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkAndRoute() async {
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      setState(() => _status = 'Checking setup status...');

      // Ensure directories and resolv.conf exist on every app open.
      // Android may clear the files directory during update or reinstall (#40).
      try {
        await NativeBridge.setupDirs();
      } catch (_) {}
      try {
        await NativeBridge.writeResolv();
      } catch (_) {}

      // Direct Dart fallback: create resolv.conf if native calls failed (#40).
      try {
        final filesDir = await NativeBridge.getFilesDir();
        const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';
        final configDir = '$filesDir/config';
        final resolvFile = File('$configDir/resolv.conf');
        if (!resolvFile.existsSync()) {
          Directory(configDir).createSync(recursive: true);
          resolvFile.writeAsStringSync(resolvContent);
        }
        // Also write into rootfs /etc/ so DNS works even if bind-mount fails
        final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
        if (!rootfsResolv.existsSync()) {
          rootfsResolv.parent.createSync(recursive: true);
          rootfsResolv.writeAsStringSync(resolvContent);
        }
      } catch (_) {}

      final prefs = PreferencesService();
      await prefs.init();

      // Auto-export snapshot when app version changes (#55)
      try {
        final oldVersion = prefs.lastAppVersion;
        if (oldVersion != null && oldVersion != AppConstants.version) {
          final hasPermission = await NativeBridge.hasStoragePermission();
          if (hasPermission) {
            final sdcard = await NativeBridge.getExternalStoragePath();
            final downloadDir = Directory('$sdcard/Download');
            if (!await downloadDir.exists()) {
              await downloadDir.create(recursive: true);
            }
            final snapshotPath =
                '$sdcard/Download/openclaw-snapshot-$oldVersion.json';
            final openclawJson = await NativeBridge.readRootfsFile(
                'root/.openclaw/openclaw.json');
            final persistentGatewayLogs =
                await NativeBridge.isGatewayLogPersistenceEnabled();
            final snapshot = {
              'version': oldVersion,
              'timestamp': DateTime.now().toIso8601String(),
              'openclawConfig': openclawJson,
              'dashboardUrl': prefs.dashboardUrl,
              'autoStart': prefs.autoStartGateway,
              'persistentGatewayLogs': persistentGatewayLogs,
              'nodeEnabled': prefs.nodeEnabled,
              'nodeDeviceToken': prefs.nodeDeviceToken,
              'nodeGatewayHost': prefs.nodeGatewayHost,
              'nodeGatewayPort': prefs.nodeGatewayPort,
              'nodeGatewayToken': prefs.nodeGatewayToken,
            };
            await File(snapshotPath).writeAsString(
              const JsonEncoder.withIndent('  ').convert(snapshot),
            );
          }
        }
        prefs.lastAppVersion = AppConstants.version;
      } catch (_) {}

      bool setupComplete;
      var bundledRuntimeUpdateRequired = false;
      EnvironmentAssessment? recoveryAssessment;
      try {
        setState(() => _status = 'Checking existing environment...');
        final recoveryService = EnvironmentRecoveryService();
        recoveryAssessment = await recoveryService.inspect();
        if (recoveryAssessment.canAutoRepair) {
          setState(() => _status = 'Repairing existing environment...');
          recoveryAssessment = await recoveryService.repair();
        }
        setupComplete = recoveryAssessment.shouldEnterDashboard;
        if (setupComplete) {
          final bootstrapState = await BootstrapService().checkStatus();
          bundledRuntimeUpdateRequired = !bootstrapState.isComplete;
          setupComplete = !bundledRuntimeUpdateRequired;
        }
      } catch (_) {
        // 兼容原生检查异常场景，保留旧版完成标记作为兜底。
        setupComplete = await NativeBridge.isBootstrapComplete();
      }

      if (!mounted) return;

      if (setupComplete) {
        var gatewayConfigured =
            await ProviderConfigService.hasRequiredGatewayConfig();
        if (!gatewayConfigured) {
          try {
            setState(() => _status = 'Preparing local configuration...');
            await ProviderConfigService.ensureInitialAppConfig();
            gatewayConfigured =
                await ProviderConfigService.hasRequiredGatewayConfig();
          } catch (_) {
            // 保留完成页重试入口，不用终端 onboarding 覆盖异常配置。
          }
        }
        final pendingSetupCompletionChoice = prefs.pendingSetupCompletionChoice;
        if (!mounted) return;

        if (gatewayConfigured) {
          prefs.pendingSetupCompletionChoice = false;
          prefs.setupComplete = true;
          prefs.isFirstRun = false;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => gatewayConfigured
                ? const DashboardScreen()
                : SetupWizardScreen(
                    resumeCompletionChoice:
                        pendingSetupCompletionChoice || setupComplete,
                  ),
          ),
        );
      } else if (bundledRuntimeUpdateRequired ||
          recoveryAssessment == null ||
          recoveryAssessment.state == EnvironmentRecoveryState.fresh) {
        prefs.pendingSetupCompletionChoice = false;
        final showWelcome =
            recoveryAssessment?.state == EnvironmentRecoveryState.fresh &&
                !prefs.hasAcceptedBundledRuntimeAgreement;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => showWelcome
                ? const RuntimeWelcomeScreen()
                : const RuntimeInitializationScreen(),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EnvironmentRecoveryScreen(
              assessment: recoveryAssessment!,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/ic_launcher.png',
                width: 80,
                height: 80,
              ),
              const SizedBox(height: 24),
              Text(
                'OpenClaw',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI Gateway for Android',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'by ${AppConstants.authorName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _status,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
