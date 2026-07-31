import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// 从 OpenAI 兼容的 `/models` 接口读取模型标识。
class ProviderModelCatalogService {
  ProviderModelCatalogService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                responseType: ResponseType.json,
                validateStatus: (_) => true,
                headers: const {'Accept': 'application/json'},
              ),
            );

  final Dio _dio;

  Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final endpoint = _appendModelsPath(baseUrl.trim());

    try {
      final response = await _dio.getUri(
        endpoint,
        options: Options(
          headers: {
            if (apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
          },
        ),
      );
      final statusCode = response.statusCode;
      if (statusCode == null || statusCode < 200 || statusCode >= 300) {
        throw ProviderModelCatalogException(
          _extractErrorDetail(response.data) ??
              'HTTP ${statusCode ?? 'unknown'}',
          statusCode: statusCode,
        );
      }

      final models = _extractModelIds(response.data);
      if (models.isEmpty) {
        throw const ProviderModelCatalogException(
          'The provider returned an empty model list',
        );
      }
      return models;
    } on ProviderModelCatalogException {
      rethrow;
    } on DioException catch (error) {
      throw ProviderModelCatalogException(
        _extractErrorDetail(error.response?.data) ??
            error.message ??
            error.type.name,
        statusCode: error.response?.statusCode,
      );
    } on TimeoutException {
      throw const ProviderModelCatalogException('Request timed out');
    } catch (error) {
      throw ProviderModelCatalogException('$error');
    }
  }

  Uri _appendModelsPath(String baseUrl) {
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    return baseUri.replace(
      path: basePath.isEmpty ? '/models' : '$basePath/models',
    );
  }

  List<String> _extractModelIds(dynamic rawData) {
    dynamic decoded = rawData;
    if (decoded is String) {
      decoded = jsonDecode(decoded);
    }

    final rawModels =
        decoded is Map ? decoded['data'] ?? decoded['models'] : null;
    if (rawModels is! List) {
      return const [];
    }

    final models = <String>{};
    for (final item in rawModels) {
      final id = switch (item) {
        String value => value.trim(),
        Map value => (value['id'] ?? value['name'] ?? '').toString().trim(),
        _ => '',
      };
      if (id.isNotEmpty) {
        models.add(id);
      }
    }

    final sorted = models.toList()..sort();
    return sorted;
  }

  String? _extractErrorDetail(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return null;
      try {
        return _extractErrorDetail(jsonDecode(trimmed));
      } catch (_) {
        return trimmed;
      }
    }
    if (data is Map) {
      final nested = _extractErrorDetail(data['error']);
      if (nested != null) return nested;
      for (final key in const ['message', 'detail', 'error_description']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    return null;
  }
}

class ProviderModelCatalogException implements Exception {
  const ProviderModelCatalogException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
