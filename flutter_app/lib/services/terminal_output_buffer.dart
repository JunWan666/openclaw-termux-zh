import 'dart:async';

import 'package:xterm/xterm.dart';

const terminalScrollbackLines = 3000;

class TerminalOutputBuffer {
  TerminalOutputBuffer(
    this._terminal, {
    this.flushInterval = const Duration(milliseconds: 16),
    this.maxBufferedChars = 65536,
  });

  final Terminal _terminal;
  final Duration flushInterval;
  final int maxBufferedChars;
  final StringBuffer _buffer = StringBuffer();
  Timer? _timer;
  bool _disposed = false;

  void write(String text) {
    if (_disposed || text.isEmpty) {
      return;
    }

    _buffer.write(text);
    if (_buffer.length >= maxBufferedChars) {
      flush();
      return;
    }

    _timer ??= Timer(flushInterval, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;

    if (_buffer.isEmpty) {
      return;
    }

    final text = _buffer.toString();
    _buffer.clear();
    _terminal.write(text);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    flush();
    _disposed = true;
  }
}
