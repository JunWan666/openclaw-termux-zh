import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/custom_provider_preset.dart';
import 'package:openclaw/services/custom_provider_connection_test_service.dart';

void main() {
  group('CustomProviderConnectionTestService', () {
    test('uses chat completions endpoint for OpenAI-compatible checks',
        () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        expect(
          options.uri.toString(),
          'https://api.example.com/v1/chat/completions',
        );
        expect(options.headers['Authorization'], 'Bearer sk-test');
        expect(options.data['model'], 'demo-model');
        expect(options.data['max_tokens'], 1);
        return _jsonResponse({'ok': true}, 200);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.openaiChatCompletions,
        apiKey: 'sk-test',
        baseUrl: 'https://api.example.com/v1',
        modelId: 'demo-model',
      );

      expect(result.success, isTrue);
      expect(
        result.compatibility,
        CustomProviderCompatibility.openaiChatCompletions,
      );
    });

    test('auto-detect prefers Google endpoint when base URL matches', () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        expect(
          options.uri.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=AIza-test',
        );
        expect(options.data['generationConfig']['maxOutputTokens'], 1);
        return _jsonResponse({'candidates': []}, 200);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.autoDetect,
        apiKey: 'AIza-test',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        modelId: 'gemini-2.0-flash',
      );

      expect(result.success, isTrue);
      expect(
        result.compatibility,
        CustomProviderCompatibility.googleGenerativeAi,
      );
      expect(result.autoDetected, isTrue);
    });

    test('auto-detect prefers Zhipu endpoint when host is bigmodel.cn',
        () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        expect(
          options.uri.toString(),
          'https://open.bigmodel.cn/api/paas/v4/chat/completions',
        );
        expect(options.headers['Authorization'], 'Bearer zhipu-test');
        expect(options.data['model'], 'glm-5');
        return _jsonResponse({'id': 'chatcmpl-test'}, 200);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.autoDetect,
        apiKey: 'zhipu-test',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        modelId: 'glm-5',
      );

      expect(result.success, isTrue);
      expect(
        result.compatibility,
        CustomProviderCompatibility.zhipuChatCompletions,
      );
      expect(result.autoDetected, isTrue);
    });

    test('returns HTTP error details when probe fails', () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        return _jsonResponse(
          {
            'error': {
              'message': 'invalid api key',
            },
          },
          401,
        );
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.openaiResponses,
        apiKey: 'bad-key',
        baseUrl: 'https://api.example.com/v1',
        modelId: 'demo-model',
      );

      expect(result.success, isFalse);
      expect(result.statusCode, 401);
      expect(result.detail, 'invalid api key');
    });
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
