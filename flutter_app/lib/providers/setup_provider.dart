import 'package:flutter/foundation.dart';
import '../models/openclaw_install_options.dart';
import '../models/setup_state.dart';
import '../services/bootstrap_service.dart';
import '../services/openclaw_version_service.dart';

class SetupProvider extends ChangeNotifier {
  static const int maxLogLines = 120;

  final BootstrapService _bootstrapService = BootstrapService();
  SetupState _state = const SetupState();
  bool _isRunning = false;
  final List<String> _logs = [];

  SetupState get state => _state;
  bool get isRunning => _isRunning;
  List<String> get logs => List.unmodifiable(_logs);

  static String sanitizeLog(String value) {
    var sanitized = value.replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), 'sk-***');
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'([#?&](?:token|access_token)=)[^&\s]+', caseSensitive: false),
      (match) => '${match.group(1)}***',
    );
    return sanitized.replaceAllMapped(
      RegExp(
        r'((?:api[_-]?key|authorization)["\x27]?\s*[:=]\s*["\x27]?)[^"\x27,\s}]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}***',
    );
  }

  static void appendSanitizedLog(List<String> logs, String? value) {
    if (value == null || value.trim().isEmpty) return;
    for (final rawLine in value.split(RegExp(r'[\r\n]+'))) {
      final line = sanitizeLog(rawLine.trim());
      if (line.isEmpty || (logs.isNotEmpty && logs.last == line)) continue;
      logs.add(line);
    }
    if (logs.length > maxLogLines) {
      logs.removeRange(0, logs.length - maxLogLines);
    }
  }

  void _appendLog(String? value) {
    appendSanitizedLog(_logs, value);
  }

  void _recordState(SetupState state) {
    _appendLog(state.message);
    _appendLog(state.detail);
    _appendLog(state.error);
  }

  Future<bool> checkIfSetupNeeded() async {
    _state = await _bootstrapService.checkStatus();
    notifyListeners();
    return !_state.isComplete;
  }

  Future<void> runSetup({
    OpenClawReleaseInfo? selectedOpenClawRelease,
    OpenClawInstallOptions installOptions = const OpenClawInstallOptions(),
    bool forceBundledRuntime = false,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    _appendLog('Initialization started');
    notifyListeners();

    await _bootstrapService.runFullSetup(
      selectedOpenClawRelease: selectedOpenClawRelease,
      installOptions: installOptions,
      forceBundledRuntime: forceBundledRuntime,
      onProgress: (state) {
        _state = state;
        _recordState(state);
        notifyListeners();
      },
    );

    _isRunning = false;
    notifyListeners();
  }

  Future<void> cancelSetup() async {
    if (!_isRunning) return;
    await _bootstrapService.cancelSetup();
    _isRunning = false;
    _state = const SetupState();
    notifyListeners();
  }

  void reset() {
    _state = const SetupState();
    _isRunning = false;
    _logs.clear();
    notifyListeners();
  }
}
