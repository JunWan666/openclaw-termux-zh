import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/provider_model_catalog_service.dart';

void main() {
  test('模型列表请求保留基础路径并携带 Bearer Key', () async {
    final adapter = _FakeHttpClientAdapter((options) async {
      expect(options.uri.toString(), 'https://api.deepseek.com/v1/models');
      expect(options.headers['Authorization'], 'Bearer sk-test');
      return _jsonResponse({
        'data': [
          {'id': 'deepseek-v4-pro'},
          {'id': 'deepseek-v4-flash'},
          {'id': 'deepseek-v4-pro'},
        ],
      }, 200);
    });
    final service = ProviderModelCatalogService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final models = await service.fetchModels(
      baseUrl: 'https://api.deepseek.com/v1/',
      apiKey: 'sk-test',
    );

    expect(models, const ['deepseek-v4-flash', 'deepseek-v4-pro']);
  });

  test('NVIDIA 公共模型目录允许不带 Key 并兼容 models 字段', () async {
    final adapter = _FakeHttpClientAdapter((options) async {
      expect(
        options.uri.toString(),
        'https://integrate.api.nvidia.com/v1/models',
      );
      expect(options.headers.containsKey('Authorization'), isFalse);
      return _jsonResponse({
        'models': [
          'openai/gpt-oss-120b',
          {'name': 'z-ai/glm-5.2'}
        ],
      }, 200);
    });
    final service = ProviderModelCatalogService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final models = await service.fetchModels(
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      apiKey: '',
    );

    expect(models, const ['openai/gpt-oss-120b', 'z-ai/glm-5.2']);
  });

  test('模型目录错误返回结构化详情', () async {
    final adapter = _FakeHttpClientAdapter((_) async {
      return _jsonResponse({
        'error': {'message': 'invalid api key'},
      }, 401);
    });
    final service = ProviderModelCatalogService(
      dio: Dio()..httpClientAdapter = adapter,
    );

    expect(
      () => service.fetchModels(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'bad-key',
      ),
      throwsA(
        isA<ProviderModelCatalogException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', 'invalid api key'),
      ),
    );
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
