import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/custom_provider_preset.dart';

class LocalModelChatCancelledException implements Exception {
  const LocalModelChatCancelledException([
    this.message = 'The request was cancelled.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class LocalModelChatMetrics {
  const LocalModelChatMetrics({
    required this.totalDuration,
    this.firstTokenLatency,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.tokensPerSecond,
    this.completionTokensEstimated = false,
  });

  final Duration totalDuration;
  final Duration? firstTokenLatency;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final double? tokensPerSecond;
  final bool completionTokensEstimated;
}

class LocalModelChatResult {
  const LocalModelChatResult({
    required this.content,
    required this.reasoning,
    required this.metrics,
  });

  final String content;
  final String reasoning;
  final LocalModelChatMetrics metrics;
}

class LocalModelChatStreamEvent {
  const LocalModelChatStreamEvent({
    required this.content,
    required this.reasoning,
    required this.done,
    this.metrics,
  });

  final String content;
  final String reasoning;
  final bool done;
  final LocalModelChatMetrics? metrics;
}

class LocalModelChatService {
  LocalModelChatService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(minutes: 10),
                responseType: ResponseType.json,
                validateStatus: (_) => true,
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            );

  final Dio _dio;
  CancelToken? _activeCancelToken;

  bool get hasActiveRequest => _activeCancelToken != null;

  static bool supportsStreaming(
    CustomProviderCompatibility compatibility,
  ) {
    switch (compatibility) {
      case CustomProviderCompatibility.openaiChatCompletions:
      case CustomProviderCompatibility.zhipuChatCompletions:
      case CustomProviderCompatibility.autoDetect:
        return true;
      case CustomProviderCompatibility.openaiResponses:
      case CustomProviderCompatibility.anthropicMessages:
      case CustomProviderCompatibility.googleGenerativeAi:
        return false;
    }
  }

  @visibleForTesting
  static ({String content, String reasoning}) normalizeAssistantContentForTest({
    String content = '',
    String explicitReasoning = '',
  }) {
    final service = LocalModelChatService();
    final normalized = service._normalizeAssistantOutput(
      content: content,
      explicitReasoning: explicitReasoning,
    );
    service._dio.close(force: true);
    return (content: normalized.content, reasoning: normalized.reasoning);
  }

  @visibleForTesting
  static int estimateTokenCountForTest(String text) {
    final service = LocalModelChatService();
    final count = service._estimateTokenCount(text);
    service._dio.close(force: true);
    return count;
  }

  void cancelActiveRequest() {
    final activeCancelToken = _activeCancelToken;
    if (activeCancelToken == null || activeCancelToken.isCancelled) {
      return;
    }
    activeCancelToken.cancel('cancelled');
  }

  Future<LocalModelChatResult> createReply({
    required String baseUrl,
    required String modelId,
    required List<Map<String, String>> messages,
    String apiKey = '',
    CustomProviderCompatibility compatibility =
        CustomProviderCompatibility.openaiChatCompletions,
    bool enableThinking = false,
    int maxTokens = 512,
    double temperature = 0.7,
  }) async {
    _resetActiveCancelToken();
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    final startedAt = DateTime.now();

    try {
      final request = _buildRequest(
        baseUrl: baseUrl,
        modelId: modelId,
        messages: messages,
        apiKey: apiKey,
        compatibility: compatibility,
        stream: false,
        enableThinking: enableThinking,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      final response = await _dio.postUri(
        request.endpoint,
        cancelToken: cancelToken,
        data: request.body,
        options: Options(headers: request.headers),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        final detail = _extractErrorDetail(response.data);
        throw Exception(
          detail == null || detail.isEmpty
              ? 'Chat request failed with status $statusCode.'
              : 'Chat request failed with status $statusCode: $detail',
        );
      }

      final extracted =
          compatibility == CustomProviderCompatibility.openaiResponses
              ? _extractResponsesPayload(response.data)
              : _extractAssistantPayload(response.data);
      if (extracted.content.isEmpty && extracted.reasoning.isEmpty) {
        throw Exception('The local model returned an empty reply.');
      }

      final finishedAt = DateTime.now();
      return LocalModelChatResult(
        content: extracted.content,
        reasoning: extracted.reasoning,
        metrics: _buildMetrics(
          responseData: response.data,
          startedAt: startedAt,
          firstTokenAt: finishedAt,
          finishedAt: finishedAt,
          content: extracted.content,
        ),
      );
    } on DioException catch (error) {
      if (_isCancelled(error)) {
        throw const LocalModelChatCancelledException();
      }
      rethrow;
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }
  }

  Stream<LocalModelChatStreamEvent> streamReply({
    required String baseUrl,
    required String modelId,
    required List<Map<String, String>> messages,
    String apiKey = '',
    CustomProviderCompatibility compatibility =
        CustomProviderCompatibility.openaiChatCompletions,
    bool enableThinking = false,
    int maxTokens = 512,
    double temperature = 0.7,
  }) async* {
    if (!supportsStreaming(compatibility)) {
      final reply = await createReply(
        baseUrl: baseUrl,
        modelId: modelId,
        messages: messages,
        apiKey: apiKey,
        compatibility: compatibility,
        enableThinking: enableThinking,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      yield LocalModelChatStreamEvent(
        content: reply.content,
        reasoning: reply.reasoning,
        done: true,
        metrics: reply.metrics,
      );
      return;
    }

    _resetActiveCancelToken();
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    final startedAt = DateTime.now();
    DateTime? firstTokenAt;

    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    dynamic lastMetricsPayload;

    try {
      final request = _buildRequest(
        baseUrl: baseUrl,
        modelId: modelId,
        messages: messages,
        apiKey: apiKey,
        compatibility: compatibility,
        stream: true,
        enableThinking: enableThinking,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      final response = await _dio.postUri(
        request.endpoint,
        cancelToken: cancelToken,
        data: request.body,
        options: Options(
          responseType: ResponseType.stream,
          headers: request.headers,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        final detail =
            _extractErrorDetail(await _readErrorPayload(response.data));
        throw Exception(
          detail == null || detail.isEmpty
              ? 'Chat request failed with status $statusCode.'
              : 'Chat request failed with status $statusCode: $detail',
        );
      }

      final responseBody = response.data;
      if (responseBody is! ResponseBody) {
        throw Exception('The local model did not return a stream response.');
      }

      await for (final line in responseBody.stream
          .map<List<int>>((chunk) => chunk)
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) {
          continue;
        }
        if (!trimmed.startsWith('data:')) {
          continue;
        }

        final payload = trimmed.substring(5).trim();
        if (payload.isEmpty) {
          continue;
        }
        if (payload == '[DONE]') {
          break;
        }

        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        lastMetricsPayload = decoded;
        final delta = _extractAssistantDelta(decoded);
        if (delta.content.isEmpty &&
            delta.reasoning.isEmpty &&
            decoded['usage'] == null &&
            decoded['timings'] == null) {
          continue;
        }

        if (firstTokenAt == null &&
            (delta.content.isNotEmpty || delta.reasoning.isNotEmpty)) {
          firstTokenAt = DateTime.now();
        }

        if (delta.reasoning.isNotEmpty) {
          reasoningBuffer.write(delta.reasoning);
        }
        if (delta.content.isNotEmpty) {
          contentBuffer.write(delta.content);
        }

        final extracted = _normalizeAssistantOutput(
          content: contentBuffer.toString(),
          explicitReasoning: reasoningBuffer.toString(),
        );
        yield LocalModelChatStreamEvent(
          content: extracted.content,
          reasoning: extracted.reasoning,
          done: false,
        );
      }

      final finishedAt = DateTime.now();
      final extracted = _normalizeAssistantOutput(
        content: contentBuffer.toString(),
        explicitReasoning: reasoningBuffer.toString(),
      );
      if (extracted.content.isEmpty && extracted.reasoning.isEmpty) {
        throw Exception('The local model returned an empty reply.');
      }

      yield LocalModelChatStreamEvent(
        content: extracted.content,
        reasoning: extracted.reasoning,
        done: true,
        metrics: _buildMetrics(
          responseData: lastMetricsPayload,
          startedAt: startedAt,
          firstTokenAt: firstTokenAt,
          finishedAt: finishedAt,
          content: extracted.content,
        ),
      );
    } on DioException catch (error) {
      if (_isCancelled(error)) {
        throw const LocalModelChatCancelledException();
      }
      rethrow;
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }
  }

  Uri _appendPath(String baseUrl, String suffix) {
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    final suffixPath = suffix.replaceFirst(RegExp(r'^/+'), '');
    final nextPath =
        basePath.isEmpty ? '/$suffixPath' : '$basePath/$suffixPath';
    return baseUri.replace(path: nextPath);
  }

  void _resetActiveCancelToken() {
    final previous = _activeCancelToken;
    if (previous != null && !previous.isCancelled) {
      previous.cancel('replaced');
    }
    _activeCancelToken = null;
  }

  _ChatRequest _buildRequest({
    required String baseUrl,
    required String modelId,
    required List<Map<String, String>> messages,
    required String apiKey,
    required CustomProviderCompatibility compatibility,
    required bool stream,
    required bool enableThinking,
    required int maxTokens,
    required double temperature,
  }) {
    switch (compatibility) {
      case CustomProviderCompatibility.autoDetect:
      case CustomProviderCompatibility.openaiChatCompletions:
      case CustomProviderCompatibility.zhipuChatCompletions:
        return _ChatRequest(
          endpoint: _appendPath(baseUrl, 'chat/completions'),
          headers: _authorizationHeaders(apiKey),
          body: _buildChatCompletionsRequestPayload(
            modelId: modelId,
            messages: messages,
            stream: stream,
            enableThinking: enableThinking,
            maxTokens: maxTokens,
            temperature: temperature,
          ),
        );
      case CustomProviderCompatibility.openaiResponses:
        return _ChatRequest(
          endpoint: _appendPath(baseUrl, 'responses'),
          headers: _authorizationHeaders(apiKey),
          body: _buildResponsesRequestPayload(
            modelId: modelId,
            messages: messages,
            stream: stream,
            enableThinking: enableThinking,
            maxTokens: maxTokens,
            temperature: temperature,
          ),
        );
      case CustomProviderCompatibility.anthropicMessages:
      case CustomProviderCompatibility.googleGenerativeAi:
        throw UnsupportedError(
          'This chat page currently supports local and OpenAI-compatible endpoints only.',
        );
    }
  }

  Map<String, dynamic> _buildChatCompletionsRequestPayload({
    required String modelId,
    required List<Map<String, String>> messages,
    required bool stream,
    required bool enableThinking,
    required int maxTokens,
    required double temperature,
  }) {
    final normalizedMessages = <Map<String, String>>[
      {
        'role': 'system',
        'content': _systemPrompt(enableThinking),
      },
      for (final message in messages)
        {
          'role': (message['role'] ?? 'user').trim(),
          'content': (message['content'] ?? '').trim(),
        },
    ]
        .where((message) => message['content']!.isNotEmpty)
        .toList(growable: false);

    return {
      'model': modelId,
      'messages': normalizedMessages,
      'stream': stream,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
  }

  Map<String, dynamic> _buildResponsesRequestPayload({
    required String modelId,
    required List<Map<String, String>> messages,
    required bool stream,
    required bool enableThinking,
    required int maxTokens,
    required double temperature,
  }) {
    final normalizedInput = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': [
          {
            'type': 'input_text',
            'text': _systemPrompt(enableThinking),
          },
        ],
      },
      for (final message in messages)
        if ((message['content'] ?? '').trim().isNotEmpty)
          {
            'role': (message['role'] ?? 'user').trim(),
            'content': [
              {
                'type': 'input_text',
                'text': (message['content'] ?? '').trim(),
              },
            ],
          },
    ];

    return {
      'model': modelId,
      'input': normalizedInput,
      'stream': stream,
      'temperature': temperature,
      'max_output_tokens': maxTokens,
    };
  }

  String _systemPrompt(bool enableThinking) {
    return enableThinking
        ? 'When reasoning is useful, first write your thought process inside <think>...</think>, then write the final answer outside the tag. / 如果需要思考，请先把思考写在 <think>...</think> 中，再在标签外给最终答案。'
        : 'Give only the final answer. Do not reveal hidden reasoning and do not output <think> tags. / 请直接给最终答案，不要输出思考过程，也不要输出 <think> 标签。';
  }

  Map<String, String> _authorizationHeaders(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $trimmed'};
  }

  _AssistantPayload _extractAssistantPayload(dynamic data) {
    if (data is! Map) {
      return const _AssistantPayload(content: '', reasoning: '');
    }

    final normalized = Map<String, dynamic>.from(data);
    final choices = normalized['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final normalizedChoice = Map<String, dynamic>.from(first);
        final message = normalizedChoice['message'];
        if (message is Map) {
          final normalizedMessage = Map<String, dynamic>.from(message);
          return _normalizeAssistantOutput(
            content: _flattenText(normalizedMessage['content']),
            explicitReasoning: _firstNonEmptyText([
              normalizedMessage['reasoning_content'],
              normalizedMessage['reasoning'],
              normalizedMessage['thinking'],
              normalizedMessage['reasoningContent'],
              normalizedMessage['thoughts'],
            ]),
          );
        }

        final text = _flattenText(normalizedChoice['text']);
        if (text.isNotEmpty) {
          return _normalizeAssistantOutput(content: text);
        }
      }
    }

    final outputText = _flattenText(normalized['output_text']);
    if (outputText.isNotEmpty) {
      return _normalizeAssistantOutput(content: outputText);
    }

    return _normalizeAssistantOutput(
      content: _flattenText(normalized['content']),
      explicitReasoning: _firstNonEmptyText([
        normalized['reasoning_content'],
        normalized['reasoning'],
        normalized['thinking'],
      ]),
    );
  }

  _AssistantPayload _extractResponsesPayload(dynamic data) {
    if (data is! Map) {
      return const _AssistantPayload(content: '', reasoning: '');
    }

    final normalized = Map<String, dynamic>.from(data);
    final outputText = _flattenText(normalized['output_text']);
    final explicitReasoning = _firstNonEmptyText([
      normalized['reasoning'],
      normalized['reasoning_content'],
      normalized['thinking'],
    ]);

    if (outputText.isNotEmpty || explicitReasoning.isNotEmpty) {
      return _normalizeAssistantOutput(
        content: outputText,
        explicitReasoning: explicitReasoning,
      );
    }

    final output = normalized['output'];
    if (output is! List) {
      return const _AssistantPayload(content: '', reasoning: '');
    }

    final contentParts = <String>[];
    final reasoningParts = <String>[];

    for (final item in output) {
      if (item is! Map) {
        continue;
      }
      final normalizedItem = Map<String, dynamic>.from(item);
      final content = normalizedItem['content'];
      if (content is! List) {
        continue;
      }
      for (final part in content) {
        if (part is! Map) {
          continue;
        }
        final normalizedPart = Map<String, dynamic>.from(part);
        final partType =
            (normalizedPart['type']?.toString().trim().toLowerCase() ?? '');
        final text = _firstNonEmptyText([
          normalizedPart['text'],
          normalizedPart['content'],
          normalizedPart['summary'],
        ]);
        if (text.isEmpty) {
          continue;
        }
        if (partType.contains('reason') || partType.contains('thinking')) {
          reasoningParts.add(text);
        } else {
          contentParts.add(text);
        }
      }
    }

    return _normalizeAssistantOutput(
      content: contentParts.join('\n\n'),
      explicitReasoning: reasoningParts.join('\n\n'),
    );
  }

  _AssistantPayload _extractAssistantDelta(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return const _AssistantPayload(content: '', reasoning: '');
    }

    final first = choices.first;
    if (first is! Map) {
      return const _AssistantPayload(content: '', reasoning: '');
    }

    final normalizedChoice = Map<String, dynamic>.from(first);
    final delta = normalizedChoice['delta'];
    if (delta is Map) {
      final normalizedDelta = Map<String, dynamic>.from(delta);
      return _AssistantPayload(
        content: _flattenText(normalizedDelta['content']),
        reasoning: _firstNonEmptyText([
          normalizedDelta['reasoning_content'],
          normalizedDelta['reasoning'],
          normalizedDelta['thinking'],
          normalizedDelta['reasoningContent'],
          normalizedDelta['thoughts'],
        ]),
      );
    }

    final message = normalizedChoice['message'];
    if (message is Map) {
      final normalizedMessage = Map<String, dynamic>.from(message);
      return _AssistantPayload(
        content: _flattenText(normalizedMessage['content']),
        reasoning: _firstNonEmptyText([
          normalizedMessage['reasoning_content'],
          normalizedMessage['reasoning'],
          normalizedMessage['thinking'],
          normalizedMessage['reasoningContent'],
          normalizedMessage['thoughts'],
        ]),
      );
    }

    return const _AssistantPayload(content: '', reasoning: '');
  }

  _AssistantPayload _normalizeAssistantOutput({
    String content = '',
    String explicitReasoning = '',
  }) {
    final split = _splitThinkBlocks(content);
    final reasoningParts = <String>[];

    final trimmedExplicit = explicitReasoning.trim();
    if (trimmedExplicit.isNotEmpty) {
      reasoningParts.add(trimmedExplicit);
    }

    final trimmedInline = split.reasoning.trim();
    if (trimmedInline.isNotEmpty &&
        !reasoningParts.any((part) => part == trimmedInline)) {
      reasoningParts.add(trimmedInline);
    }

    return _AssistantPayload(
      content: split.content.trim(),
      reasoning: reasoningParts.join('\n\n').trim(),
    );
  }

  _ThinkSplit _splitThinkBlocks(String rawContent) {
    final matches = RegExp(
      r'<think>([\s\S]*?)</think>',
      caseSensitive: false,
    ).allMatches(rawContent);

    if (matches.isEmpty) {
      return _ThinkSplit(
        content: rawContent.trim(),
        reasoning: '',
      );
    }

    final reasoningParts = <String>[];
    for (final match in matches) {
      final reasoning = (match.group(1) ?? '').trim();
      if (reasoning.isNotEmpty) {
        reasoningParts.add(reasoning);
      }
    }

    final content = rawContent
        .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return _ThinkSplit(
      content: content,
      reasoning: reasoningParts.join('\n\n').trim(),
    );
  }

  String _flattenText(dynamic value) {
    if (value == null) {
      return '';
    }

    if (value is String) {
      return value.trim();
    }

    if (value is List) {
      final parts = value
          .map(_flattenText)
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      return parts.join('\n\n').trim();
    }

    if (value is Map) {
      final normalized = Map<String, dynamic>.from(value);
      final text = normalized['text'];
      if (text is String && text.trim().isNotEmpty) {
        return text.trim();
      }

      final content = normalized['content'];
      final nested = _flattenText(content);
      if (nested.isNotEmpty) {
        return nested;
      }
    }

    return '';
  }

  String _firstNonEmptyText(List<dynamic> values) {
    for (final value in values) {
      final text = _flattenText(value);
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  LocalModelChatMetrics _buildMetrics({
    required dynamic responseData,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String content,
    DateTime? firstTokenAt,
  }) {
    final metricsSource = responseData is Map
        ? Map<String, dynamic>.from(responseData)
        : const <String, dynamic>{};
    final totalDuration = finishedAt.difference(startedAt);
    final promptTokens = _readNestedInt(metricsSource, const [
      ['usage', 'prompt_tokens'],
      ['usage', 'input_tokens'],
      ['prompt_tokens'],
      ['prompt_eval_count'],
      ['timings', 'prompt_n'],
      ['timings', 'prompt_tokens'],
    ]);
    final rawCompletionTokens = _readNestedInt(metricsSource, const [
      ['usage', 'completion_tokens'],
      ['usage', 'output_tokens'],
      ['completion_tokens'],
      ['output_tokens'],
      ['eval_count'],
      ['timings', 'predicted_n'],
      ['timings', 'completion_tokens'],
    ]);
    final estimatedCompletionTokens =
        rawCompletionTokens ?? _estimateTokenCount(content);
    final totalTokens = _readNestedInt(metricsSource, const [
          ['usage', 'total_tokens'],
          ['total_tokens'],
        ]) ??
        ((promptTokens ?? 0) + estimatedCompletionTokens);

    final generationDuration = (() {
      final evalSeconds = _readNestedSeconds(metricsSource, const [
        ['timings', 'predicted_ms'],
        ['timings', 'eval_ms'],
      ]);
      if (evalSeconds != null && evalSeconds > 0) {
        return Duration(milliseconds: (evalSeconds * 1000).round());
      }
      if (firstTokenAt != null) {
        final delta = finishedAt.difference(firstTokenAt);
        if (delta.inMilliseconds > 0) {
          return delta;
        }
      }
      return totalDuration;
    })();

    final directTokensPerSecond = _readNestedDouble(metricsSource, const [
      ['timings', 'predicted_per_second'],
      ['timings', 'tokens_per_second'],
      ['tokens_per_second'],
    ]);
    final tokensPerSecond = directTokensPerSecond ??
        _computeTokensPerSecond(estimatedCompletionTokens, generationDuration);

    return LocalModelChatMetrics(
      totalDuration: totalDuration,
      firstTokenLatency: firstTokenAt?.difference(startedAt),
      promptTokens: promptTokens,
      completionTokens: estimatedCompletionTokens,
      totalTokens: totalTokens,
      tokensPerSecond: tokensPerSecond,
      completionTokensEstimated: rawCompletionTokens == null,
    );
  }

  double? _computeTokensPerSecond(int completionTokens, Duration duration) {
    if (completionTokens <= 0 || duration.inMilliseconds <= 0) {
      return null;
    }
    return completionTokens / (duration.inMilliseconds / 1000);
  }

  int _estimateTokenCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    final cjkChars = RegExp(r'[\u3400-\u9FFF]').allMatches(trimmed).length;
    final latinWords = RegExp(r'[A-Za-z0-9_]+').allMatches(trimmed).length;
    final punctuation =
        RegExp(r'[^\sA-Za-z0-9_\u3400-\u9FFF]').allMatches(trimmed).length;

    final heuristicA = latinWords + cjkChars + (punctuation / 2).ceil();
    final heuristicB =
        (trimmed.replaceAll(RegExp(r'\s+'), '').length / 4).ceil();
    return math.max(1, math.max(heuristicA, heuristicB));
  }

  int? _readNestedInt(
    Map<String, dynamic> source,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      final value = _readNestedValue(source, path);
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  double? _readNestedDouble(
    Map<String, dynamic> source,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      final value = _readNestedValue(source, path);
      if (value is double) {
        return value;
      }
      if (value is num) {
        return value.toDouble();
      }
      final textValue = value?.toString();
      if (textValue != null) {
        final parsed = double.tryParse(textValue.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  double? _readNestedSeconds(
    Map<String, dynamic> source,
    List<List<String>> paths,
  ) {
    final rawValue = _readNestedDouble(source, paths);
    if (rawValue == null || rawValue <= 0) {
      return null;
    }
    if (rawValue > 1000) {
      return rawValue / 1000;
    }
    return rawValue;
  }

  dynamic _readNestedValue(Map<String, dynamic> source, List<String> path) {
    dynamic current = source;
    for (final segment in path) {
      if (current is! Map) {
        return null;
      }
      current = current[segment];
    }
    return current;
  }

  Future<dynamic> _readErrorPayload(dynamic responseData) async {
    if (responseData is ResponseBody) {
      final bytes = await responseData.stream.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) {
        return null;
      }
      try {
        return jsonDecode(text);
      } catch (_) {
        return text;
      }
    }
    return responseData;
  }

  bool _isCancelled(DioException error) {
    return error.type == DioExceptionType.cancel ||
        error.error is LocalModelChatCancelledException ||
        CancelToken.isCancel(error);
  }

  String? _extractErrorDetail(dynamic data) {
    if (data == null) {
      return null;
    }

    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) {
        return null;
      }

      try {
        return _extractErrorDetail(jsonDecode(trimmed));
      } catch (_) {
        return trimmed;
      }
    }

    if (data is Map) {
      final normalized = Map<String, dynamic>.from(data);
      final error = normalized['error'];
      if (error != null) {
        final nested = _extractErrorDetail(error);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }

      for (final key in const ['message', 'detail', 'error_description']) {
        final value = normalized[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    if (data is List) {
      for (final item in data) {
        final nested = _extractErrorDetail(item);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    }

    final fallback = '$data'.trim();
    return fallback.isEmpty ? null : fallback;
  }
}

class _AssistantPayload {
  const _AssistantPayload({
    required this.content,
    required this.reasoning,
  });

  final String content;
  final String reasoning;
}

class _ThinkSplit {
  const _ThinkSplit({
    required this.content,
    required this.reasoning,
  });

  final String content;
  final String reasoning;
}

class _ChatRequest {
  const _ChatRequest({
    required this.endpoint,
    required this.headers,
    required this.body,
  });

  final Uri endpoint;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}
