import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../services/message_platform_config_service.dart';
import '../services/native_bridge.dart';
import '../services/terminal_output_buffer.dart';
import '../services/terminal_service.dart';
import '../widgets/terminal_toolbar.dart';

/// Runs the QQ Bot plugin installation only after an explicit user action.
class QqbotInstallerScreen extends StatefulWidget {
  const QqbotInstallerScreen({super.key});

  @override
  State<QqbotInstallerScreen> createState() => _QqbotInstallerScreenState();
}

class _QqbotInstallerScreenState extends State<QqbotInstallerScreen> {
  late final Terminal _terminal;
  late final TerminalController _controller;
  late final TerminalOutputBuffer _outputBuffer;
  final _ctrlNotifier = ValueNotifier<bool>(false);
  final _altNotifier = ValueNotifier<bool>(false);
  Pty? _pty;
  bool _loading = true;
  bool _finished = false;
  bool _succeeded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: terminalScrollbackLines);
    _controller = TerminalController();
    _outputBuffer = TerminalOutputBuffer(_terminal);
    NativeBridge.startTerminalService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInstaller());
  }

  Future<void> _startInstaller() async {
    _outputBuffer.flush();
    _pty?.kill();
    _pty = null;
    try {
      final config = await TerminalService.getProotShellConfig();
      final args = TerminalService.buildProotArgs(
        config,
        columns: _terminal.viewWidth,
        rows: _terminal.viewHeight,
      );
      final installerArgs = List<String>.from(args)
        ..removeLast()
        ..removeLast()
        ..addAll([
          '/bin/bash',
          '-lc',
          'echo "=== OpenClaw QQ Bot Plugin Installer ===" && '
              'echo "Installing ${MessagePlatformConfigService.qqbotPluginPackage}" && '
              'echo "" && '
              'openclaw plugins install ${MessagePlatformConfigService.qqbotPluginPackage}',
        ]);

      _pty = Pty.start(
        config['executable']!,
        arguments: installerArgs,
        environment: TerminalService.buildHostEnv(config),
        columns: _terminal.viewWidth,
        rows: _terminal.viewHeight,
      );
      _pty!.output.cast<List<int>>().listen((data) {
        _outputBuffer.write(utf8.decode(data, allowMalformed: true));
      });
      _pty!.exitCode.then((code) {
        _outputBuffer.write('\r\n[Process exited with code $code]\r\n');
        _outputBuffer.flush();
        if (mounted) {
          setState(() {
            _finished = true;
            _succeeded = code == 0;
          });
        }
      });
      _terminal.onOutput = (data) {
        if (_ctrlNotifier.value && data.length == 1) {
          final code = data.toLowerCase().codeUnitAt(0);
          if (code >= 97 && code <= 122) {
            _pty?.write(Uint8List.fromList([code - 96]));
            _ctrlNotifier.value = false;
            return;
          }
        }
        if (_altNotifier.value && data.isNotEmpty) {
          _pty?.write(utf8.encode('\x1b$data'));
          _altNotifier.value = false;
          return;
        }
        _pty?.write(utf8.encode(data));
      };
      _terminal.onResize = (w, h, pw, ph) => _pty?.resize(h, w);
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  void dispose() {
    _ctrlNotifier.dispose();
    _altNotifier.dispose();
    _controller.dispose();
    _outputBuffer.dispose();
    _pty?.kill();
    NativeBridge.stopTerminalService();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final text? when text.isNotEmpty) {
      _pty?.write(utf8.encode(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('messagePlatformDetailQqbotTerminalTitle')),
        actions: [
          IconButton(
            onPressed: _paste,
            tooltip: l10n.t('commonPaste'),
            icon: const Icon(Icons.paste),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Theme.of(context).colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _finished = false;
                            _error = null;
                          });
                          _startInstaller();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.t('commonRetry')),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Expanded(
              child: TerminalView(
                _terminal,
                controller: _controller,
                textStyle: const TerminalStyle(fontSize: 11, height: 1),
              ),
            ),
            TerminalToolbar(
              pty: _pty,
              ctrlNotifier: _ctrlNotifier,
              altNotifier: _altNotifier,
            ),
          ],
          if (_finished)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_succeeded),
                  icon: Icon(_succeeded ? Icons.check : Icons.close),
                  label: Text(
                      _succeeded ? l10n.t('commonDone') : l10n.t('commonDone')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
