import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/custom_provider_preset.dart';

class CustomProviderConnectionTestResult {
  const CustomProviderConnectionTestResult({
    required this.success,
    required this.compatibility,
    required this.endpoint,
    this.statusCode,
    this.detail,
    this.autoDetected = false,
  });

  final bool success;
  final CustomProviderCompatibility compatibility;
  final Uri endpoint;
  final int? statusCode;
  final String? detail;
  final bool autoDetected;
}

class CustomProviderConnectionTestService {
  CustomProviderConnectionTestService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                sendTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                responseType: ResponseType.json,
                validateStatus: (_) => true,
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            );

  final Dio _dio;

  Future<CustomProviderConnectionTestResult> testConnection({
    required CustomProviderCompatibility compatibility,
    required String baseUrl,
    required String apiKey,
    required String modelId,
  }) async {
    final normalizedBaseUrl = baseUrl.trim();
    final normalizedApiKey = apiKey.trim();
    final normalizedModelId = modelId.trim();

    if (compatibility != CustomProviderCompatibility.autoDetect) {
      return _runProbe(
        compatibility,
        baseUrl: normalizedBaseUrl,
        apiKey: normalizedApiKey,
        modelId: normalizedModelId,
      );
    }

    final attempts = _autoDetectCompatibilities(
      normalizedBaseUrl,
      normalizedApiKey,
    );
    final failures = <CustomProviderConnectionTestResult>[];

    for (final candidate in attempts) {
      final result = await _runProbe(
        candidate,
        baseUrl: normalizedBaseUrl,
        apiKey: normalizedApiKey,
        modelId: normalizedModelId,
        autoDetected: true,
      );
      if (result.success) {
        return result;
      }
      failures.add(result);
    }

    return _pickBestFailure(failures);
  }

  Future<CustomProviderConnectionTestResult> _runProbe(
    CustomProviderCompatibility compatibility, {
    required String baseUrl,
    required String apiKey,
    required String modelId,
    bool autoDetected = false,
  }) async {
    final request = _buildRequest(
      compatibility,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
    );

    try {
      final response = await _dio.postUri(
        request.endpoint,
        data: request.body,
        options: Options(headers: request.headers),
      );
      final detail = _extractErrorDetail(response.data);
      final success = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;

      return CustomProviderConnectionTestResult(
        success: success,
        compatibility: compatibility,
        endpoint: request.endpoint,
        statusCode: response.statusCode,
        detail: success ? null : detail,
        autoDetected: autoDetected,
      );
    } on DioException catch (error) {
      return CustomProviderConnectionTestResult(
        success: false,
        compatibility: compatibility,
        endpoint: request.endpoint,
        statusCode: error.response?.statusCode,
        detail: _extractDioErrorDetail(error),
        autoDetected: autoDetected,
      );
    } on TimeoutException {
      return CustomProviderConnectionTestResult(
        success: false,
        compatibility: compatibility,
        endpoint: request.endpoint,
        detail: 'Request timed out',
        autoDetected: autoDetected,
      );
    } catch (error) {
      return CustomProviderConnectionTestResult(
        success: false,
        compatibility: compatibility,
        endpoint: request.endpoint,
        detail: '$error',
        autoDetected: autoDetected,
      );
    }
  }

  _ProbeRequest _buildRequest(
    CustomProviderCompatibility compatibility, {
    required String baseUrl,
    required String apiKey,
    required String modelId,
  }) {
    switch (compatibility) {
      case CustomProviderCompatibility.autoDetect:
        throw StateError('autoDetect is resolved before building a request');
      case CustomProviderCompatibility.openaiChatCompletions:
      case CustomProviderCompatibility.zhipuChatCompletions:
        return _ProbeRequest(
          endpoint: _appendPath(baseUrl, 'chat/completions'),
          headers: _bearerHeaders(apiKey),
          body: {
            'model': modelId,
            'messages': const [
              {
                'role': 'user',
                'content': 'ping',
              },
            ],
            'max_tokens': 1,
            'temperature': 0,
          },
        );
      case CustomProviderCompatibility.openaiResponses:
        return _ProbeRequest(
          endpoint: _appendPath(baseUrl, 'responses'),
          headers: _bearerHeaders(apiKey),
          body: {
            'model': modelId,
            'input': 'ping',
            'max_output_tokens': 1,
          },
        );
      case CustomProviderCompatibility.anthropicMessages:
        return _ProbeRequest(
          endpoint: _appendPath(baseUrl, 'messages'),
          headers: {
            if (apiKey.isNotEmpty) 'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          body: {
            'model': modelId,
            'max_tokens': 1,
            'messages': const [
              {
                'role': 'user',
                'content': 'ping',
              },
            ],
          },
        );
      case CustomProviderCompatibility.googleGenerativeAi:
        return _ProbeRequest(
          endpoint: _appendPath(
            baseUrl,
            'models/$modelId:generateContent',
            queryParameters: {
              if (apiKey.isNotEmpty) 'key': apiKey,
            },
          ),
          headers: const <String, String>{},
          body: {
            'contents': const [
              {
                'role': 'user',
                'parts': [
                  {
                    'text': 'ping',
                  },
                ],
              },
            ],
            'generationConfig': const {
              'maxOutputTokens': 1,
              'temperature': 0,
            },
          },
        );
    }
  }

  List<CustomProviderCompatibility> _autoDetectCompatibilities(
    String baseUrl,
    String apiKey,
  ) {
    final parsed = Uri.tryParse(baseUrl);
    final host = parsed?.host.toLowerCase() ?? '';
    final path = parsed?.path.toLowerCase() ?? '';

    final prioritized = <CustomProviderCompatibility>[];

    void add(CustomProviderCompatibility compatibility) {
      if (!prioritized.contains(compatibility)) {
        prioritized.add(compatibility);
      }
    }

    if (apiKey.startsWith('AIza') ||
        host.contains('googleapis.com') ||
        host.contains('generativelanguage')) {
      add(CustomProviderCompatibility.googleGenerativeAi);
    }
    if (host.contains('bigmodel.cn')) {
      add(CustomProviderCompatibility.zhipuChatCompletions);
    }
    if (apiKey.startsWith('sk-ant') || host.contains('anthropic')) {
      add(CustomProviderCompatibility.anthropicMessages);
    }
    if (path.contains('/responses')) {
      add(CustomProviderCompatibility.openaiResponses);
    }
    add(CustomProviderCompatibility.openaiChatCompletions);
    add(CustomProviderCompatibility.zhipuChatCompletions);
    add(CustomProviderCompatibility.openaiResponses);
    add(CustomProviderCompatibility.anthropicMessages);
    add(CustomProviderCompatibility.googleGenerativeAi);
    return prioritized;
  }

  CustomProviderConnectionTestResult _pickBestFailure(
    List<CustomProviderConnectionTestResult> failures,
  ) {
    if (failures.isEmpty) {
      throw StateError('Expected at least one failure result');
    }

    for (final result in failures) {
      if (result.statusCode != null &&
          result.statusCode != 404 &&
          result.statusCode != 405) {
        return result;
      }
    }

    for (final result in failures) {
      if (result.detail != null && result.detail!.trim().isNotEmpty) {
        return result;
      }
    }

    return failures.first;
  }

  Map<String, String> _bearerHeaders(String apiKey) {
    if (apiKey.isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $apiKey'};
  }

  Uri _appendPath(
    String baseUrl,
    String suffix, {
    Map<String, String>? queryParameters,
  }) {
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    final suffixPath = suffix.replaceFirst(RegExp(r'^/+'), '');
    final nextPath =
        basePath.isEmpty ? '/$suffixPath' : '$basePath/$suffixPath';
    final mergedQuery = <String, String>{
      ...baseUri.queryParameters,
      ...?queryParameters,
    };
    return baseUri.replace(
      path: nextPath,
      queryParameters: mergedQuery.isEmpty ? null : mergedQuery,
    );
  }

  String? _extractDioErrorDetail(DioException error) {
    final response = error.response;
    final responseDetail = _extractErrorDetail(response?.data);
    if (responseDetail != null) {
      return responseDetail;
    }

    if (error.message != null && error.message!.trim().isNotEmpty) {
      return error.message!.trim();
    }
    return error.type.name;
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
      final error = data['error'];
      if (error is Map) {
        final nestedMessage = _extractErrorDetail(error);
        if (nestedMessage != null) {
          return nestedMessage;
        }
      }

      final detailKeys = ['message', 'detail', 'error_description', 'type'];
      for (final key in detailKeys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    if (data is List) {
      for (final item in data) {
        final nestedMessage = _extractErrorDetail(item);
        if (nestedMessage != null) {
          return nestedMessage;
        }
      }
    }

    return '$data';
  }
}

class _ProbeRequest {
  const _ProbeRequest({
    required this.endpoint,
    required this.headers,
    required this.body,
  });

  final Uri endpoint;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}
