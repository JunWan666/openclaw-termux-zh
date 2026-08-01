import 'setup_state.dart';

enum RuntimeInitializationStage {
  checkingDevice,
  preparingRuntime,
  deployingCore,
  configuringService,
  finalChecks,
  complete,
  failed,
}

class RuntimeInitializationView {
  const RuntimeInitializationView._();

  static RuntimeInitializationStage stageFor(SetupStep step) {
    return switch (step) {
      SetupStep.checkingStatus => RuntimeInitializationStage.checkingDevice,
      SetupStep.downloadingRootfs =>
        RuntimeInitializationStage.preparingRuntime,
      SetupStep.extractingRootfs ||
      SetupStep.installingNode ||
      SetupStep.installingOpenClaw =>
        RuntimeInitializationStage.deployingCore,
      SetupStep.configuringBypass =>
        RuntimeInitializationStage.configuringService,
      SetupStep.complete => RuntimeInitializationStage.complete,
      SetupStep.error => RuntimeInitializationStage.failed,
    };
  }

  static String label(RuntimeInitializationStage stage, String languageCode) {
    final zh = languageCode == 'zh';
    return switch (stage) {
      RuntimeInitializationStage.checkingDevice =>
        zh ? '正在检查设备环境…' : 'Checking device environment…',
      RuntimeInitializationStage.preparingRuntime =>
        zh ? '正在准备运行环境…' : 'Preparing the runtime…',
      RuntimeInitializationStage.deployingCore =>
        zh ? '正在部署核心组件…' : 'Deploying core components…',
      RuntimeInitializationStage.configuringService =>
        zh ? '正在配置本地服务…' : 'Configuring the local service…',
      RuntimeInitializationStage.finalChecks =>
        zh ? '正在进行最后检查…' : 'Performing final checks…',
      RuntimeInitializationStage.complete =>
        zh ? 'OpenClaw 已准备完成' : 'OpenClaw is ready',
      RuntimeInitializationStage.failed =>
        zh ? '运行环境准备失败' : 'Runtime preparation failed',
    };
  }

  static double stageCeiling(RuntimeInitializationStage stage) {
    return switch (stage) {
      RuntimeInitializationStage.checkingDevice => 0.12,
      RuntimeInitializationStage.preparingRuntime => 0.30,
      RuntimeInitializationStage.deployingCore => 0.76,
      RuntimeInitializationStage.configuringService => 0.94,
      RuntimeInitializationStage.finalChecks => 0.99,
      RuntimeInitializationStage.complete => 1.0,
      RuntimeInitializationStage.failed => 0.99,
    };
  }

  static double nextDisplayProgress({
    required double current,
    required RuntimeInitializationStage stage,
  }) {
    final ceiling = stageCeiling(stage);
    if (stage == RuntimeInitializationStage.complete) return 1.0;
    if (stage == RuntimeInitializationStage.failed || current >= ceiling) {
      return current.clamp(0.0, 0.99);
    }
    final gap = ceiling - current;
    final increment = (gap * 0.035).clamp(0.0007, 0.004);
    return (current + increment).clamp(0.0, ceiling);
  }

  static String activity(
      RuntimeInitializationStage stage, String languageCode) {
    final zh = languageCode == 'zh';
    return switch (stage) {
      RuntimeInitializationStage.checkingDevice =>
        zh ? '检查设备架构与可用空间' : 'Checking architecture and available storage',
      RuntimeInitializationStage.preparingRuntime =>
        zh ? '校验内置运行环境资源' : 'Verifying bundled runtime resources',
      RuntimeInitializationStage.deployingCore =>
        zh ? '部署并校验核心组件' : 'Deploying and verifying core components',
      RuntimeInitializationStage.configuringService => zh
          ? '写入配置并启动本地服务'
          : 'Writing configuration and starting local services',
      RuntimeInitializationStage.finalChecks =>
        zh ? '等待本地服务就绪' : 'Waiting for local services to become ready',
      RuntimeInitializationStage.complete => zh
          ? '初始化成功，所有组件已就绪'
          : 'Initialization succeeded; all components are ready',
      RuntimeInitializationStage.failed =>
        zh ? '初始化中断，请查看错误信息' : 'Initialization stopped; review the error below',
    };
  }
}
