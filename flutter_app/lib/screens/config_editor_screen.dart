import 'dart:convert';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../services/native_bridge.dart';

class JsonSyntaxTextController extends TextEditingController {
  JsonSyntaxTextController({super.text});

  static final _tokenPattern = RegExp(
    r'"(?:\\.|[^"\\])*"|\btrue\b|\bfalse\b|\bnull\b|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|[{}\[\],:]',
    multiLine: true,
  );
  static final _numberPattern = RegExp(
    r'^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$',
  );
  static final _whitespacePattern = RegExp(r'\s');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final source = text;
    final spans = <TextSpan>[];
    var index = 0;

    for (final match in _tokenPattern.allMatches(source)) {
      if (match.start > index) {
        spans.add(
          TextSpan(
            text: source.substring(index, match.start),
            style: baseStyle,
          ),
        );
      }

      final token = match.group(0)!;
      spans.add(
        TextSpan(
          text: token,
          style: _styleForToken(
            context,
            baseStyle,
            token,
            source,
            match.end,
          ),
        ),
      );
      index = match.end;
    }

    if (index < source.length) {
      spans.add(TextSpan(text: source.substring(index), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  TextStyle _styleForToken(
    BuildContext context,
    TextStyle baseStyle,
    String token,
    String source,
    int tokenEnd,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (token.startsWith('"')) {
      final isKey = _isJsonKey(source, tokenEnd);
      return baseStyle.copyWith(
        color: isKey
            ? (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8))
            : (isDark ? const Color(0xFF86EFAC) : const Color(0xFF047857)),
        fontWeight: isKey ? FontWeight.w700 : FontWeight.w500,
      );
    }

    if (token == 'true' || token == 'false') {
      return baseStyle.copyWith(
        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
        fontWeight: FontWeight.w700,
      );
    }

    if (token == 'null') {
      return baseStyle.copyWith(
        color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED),
        fontStyle: FontStyle.italic,
      );
    }

    if (_numberPattern.hasMatch(token)) {
      return baseStyle.copyWith(
        color: isDark ? const Color(0xFF67E8F9) : const Color(0xFF0F766E),
        fontWeight: FontWeight.w600,
      );
    }

    return baseStyle.copyWith(
      color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
      fontWeight: FontWeight.w700,
    );
  }

  bool _isJsonKey(String source, int tokenEnd) {
    var index = tokenEnd;
    while (
        index < source.length && _whitespacePattern.hasMatch(source[index])) {
      index += 1;
    }
    return index < source.length && source[index] == ':';
  }
}

class ConfigEditorScreen extends StatefulWidget {
  const ConfigEditorScreen({super.key});

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> {
  static const _configPath = 'root/.openclaw/openclaw.json';

  final _controller = JsonSyntaxTextController();
  bool _loading = true;
  bool _saving = false;
  String? _validationError;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _loadConfig();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      final normalized = content?.trim().isNotEmpty == true ? content! : '{}\n';
      _controller.text = _prettyPrintJson(normalized);
      _validate(_controller.text);
    } catch (e) {
      _loadError = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _handleTextChanged() {
    _validate(_controller.text);
  }

  void _validate(String source) {
    String? error;

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        error = context.l10n.t('configEditorValidationObjectOnly');
      }
    } catch (e) {
      error = e.toString();
    }

    if (mounted && error != _validationError) {
      setState(() => _validationError = error);
    } else {
      _validationError = error;
    }
  }

  String _prettyPrintJson(String source) {
    try {
      final decoded = jsonDecode(source);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return source;
    }
  }

  Future<void> _formatJson() async {
    final error = _validationError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('configEditorValidationFailed', {
            'error': error,
          })),
        ),
      );
      return;
    }

    final selection = _controller.selection;
    final formatted = _prettyPrintJson(_controller.text);
    setState(() {
      _controller.text = '$formatted\n';
      final offset = selection.baseOffset < 0
          ? _controller.text.length
          : selection.baseOffset.clamp(0, _controller.text.length);
      _controller.selection = TextSelection.collapsed(
        offset: offset,
      );
    });
  }

  Future<void> _saveConfig() async {
    final error = _validationError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('configEditorValidationFailed', {
            'error': error,
          })),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final formatted = '${_prettyPrintJson(_controller.text)}\n';
      await NativeBridge.writeRootfsFile(_configPath, formatted);
      if (!mounted) return;
      _controller.text = formatted;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('configEditorSaved'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('configEditorSaveFailed', {'error': e}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final editorBg = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface;
    final validationError = _validationError;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('configEditorTitle')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadConfig,
            tooltip: l10n.t('configEditorRefresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.t('configEditorSubtitle'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _configPath,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'DejaVuSansMono',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: validationError == null
                                  ? AppColors.statusGreen.withAlpha(22)
                                  : theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              validationError == null
                                  ? l10n.t('configEditorValidationOk')
                                  : l10n.t('configEditorValidationError'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: validationError == null
                                    ? AppColors.statusGreen
                                    : theme.colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_loadError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              l10n.t('configEditorLoadFailed', {
                                'error': _loadError,
                              }),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          if (validationError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              validationError,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _formatJson,
                        icon: const Icon(Icons.auto_fix_high),
                        label: Text(l10n.t('configEditorFormat')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving || validationError != null
                            ? null
                            : _saveConfig,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving
                              ? l10n.t('configEditorSaving')
                              : l10n.t('configEditorSave'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: editorBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outline.withAlpha(60),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.multiline,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'DejaVuSansMono',
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: '{\n  "gateway": {}\n}',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                          filled: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
