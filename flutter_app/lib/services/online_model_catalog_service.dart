import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_model_service.dart';

class OnlineModelCatalogException implements Exception {
  const OnlineModelCatalogException(
    this.message, {
    required this.code,
    this.statusCode,
  });

  final String message;
  final String code;
  final int? statusCode;

  @override
  String toString() => message;
}

class OnlineModelCatalogSearchResult {
  const OnlineModelCatalogSearchResult({
    required this.repoId,
    required this.author,
    required this.pipelineTag,
    required this.tags,
    required this.downloads,
    required this.likes,
    required this.updatedAt,
    required this.gated,
  });

  final String repoId;
  final String author;
  final String pipelineTag;
  final List<String> tags;
  final int downloads;
  final int likes;
  final DateTime? updatedAt;
  final bool gated;

  String get title => repoId;

  String get subtitle {
    final parts = <String>[
      if (author.trim().isNotEmpty) author.trim(),
      if (pipelineTag.trim().isNotEmpty) pipelineTag.trim(),
    ];
    return parts.join(' 路 ');
  }
}

class OnlineModelCatalogVariant {
  const OnlineModelCatalogVariant({
    required this.fileName,
    required this.downloadUrl,
  });

  final String fileName;
  final String downloadUrl;

  String get defaultAlias {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.gguf')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
  }

  LocalModelDownloadSelection toSelection({
    required String title,
    required String subtitle,
    required String sourceLabel,
  }) {
    return LocalModelDownloadSelection(
      title: title,
      subtitle: subtitle,
      fileName: fileName,
      downloadUrl: downloadUrl,
      defaultAlias: defaultAlias,
      sourceLabel: sourceLabel,
    );
  }
}

class OnlineModelCatalogService {
  static const _baseUrl = 'https://huggingface.co';
  static const _userAgent = 'OpenClaw-Termux-ZH/2.0';
  static final Uri _searchEndpoint = Uri.parse('$_baseUrl/api/models');
  static final Map<String, _SearchCacheEntry> _searchCache =
      <String, _SearchCacheEntry>{};
  static final Map<String, _VariantCacheEntry> _variantCache =
      <String, _VariantCacheEntry>{};

  static Future<List<OnlineModelCatalogSearchResult>> searchGgufModels(
    String query, {
    int limit = 12,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <OnlineModelCatalogSearchResult>[];
    }

    final cacheKey = '${normalizedQuery.toLowerCase()}|$limit';
    final cached = _searchCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(minutes: 10)) {
      return cached.results;
    }

    final uri = _searchEndpoint.replace(queryParameters: {
      'search': '$normalizedQuery gguf',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '$limit',
    });

    final response =
        await _getWithRetry(uri, actionLabel: 'Online model search');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const <OnlineModelCatalogSearchResult>[];
    }

    final results = <OnlineModelCatalogSearchResult>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final normalized = item.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final repoId =
          (normalized['id'] ?? normalized['modelId'] ?? '').toString().trim();
      if (repoId.isEmpty) {
        continue;
      }

      final tags = (normalized['tags'] as List?)
              ?.map((tag) => tag.toString().trim())
              .where((tag) => tag.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      if (!tags.any((tag) => tag.toLowerCase() == 'gguf') &&
          !repoId.toLowerCase().contains('gguf')) {
        continue;
      }

      results.add(
        OnlineModelCatalogSearchResult(
          repoId: repoId,
          author: normalized['author']?.toString().trim() ??
              _authorFromRepoId(repoId),
          pipelineTag: normalized['pipeline_tag']?.toString().trim() ?? '',
          tags: tags,
          downloads: (normalized['downloads'] as num?)?.toInt() ?? 0,
          likes: (normalized['likes'] as num?)?.toInt() ?? 0,
          updatedAt: DateTime.tryParse(
            normalized['lastModified']?.toString().trim() ??
                normalized['createdAt']?.toString().trim() ??
                '',
          ),
          gated: normalized['gated'] == true,
        ),
      );
    }

    _searchCache[cacheKey] = _SearchCacheEntry(
      fetchedAt: DateTime.now(),
      results: results,
    );
    return results;
  }

  static Future<List<OnlineModelCatalogVariant>> fetchGgufVariants(
    String repoId,
  ) async {
    final normalizedRepoId = repoId.trim();
    if (normalizedRepoId.isEmpty) {
      return const <OnlineModelCatalogVariant>[];
    }

    final cached = _variantCache[normalizedRepoId];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(minutes: 10)) {
      return cached.variants;
    }

    final uri = Uri.parse('$_baseUrl/api/models/$normalizedRepoId');
    final response =
        await _getWithRetry(uri, actionLabel: 'Model detail lookup');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return const <OnlineModelCatalogVariant>[];
    }

    final normalized = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final siblings = normalized['siblings'];
    if (siblings is! List) {
      return const <OnlineModelCatalogVariant>[];
    }

    final variants = <OnlineModelCatalogVariant>[];
    for (final item in siblings) {
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final fileName = normalizedItem['rfilename']?.toString().trim() ?? '';
      if (!fileName.toLowerCase().endsWith('.gguf')) {
        continue;
      }

      variants.add(
        OnlineModelCatalogVariant(
          fileName: fileName,
          downloadUrl:
              '$_baseUrl/$normalizedRepoId/resolve/main/$fileName?download=true',
        ),
      );
    }

    variants.sort((left, right) {
      final leftRank = _variantRank(left.fileName);
      final rightRank = _variantRank(right.fileName);
      if (leftRank != rightRank) {
        return leftRank.compareTo(rightRank);
      }
      return left.fileName.compareTo(right.fileName);
    });

    _variantCache[normalizedRepoId] = _VariantCacheEntry(
      fetchedAt: DateTime.now(),
      variants: variants,
    );
    return variants;
  }

  static Future<http.Response> _getWithRetry(
    Uri uri, {
    required String actionLabel,
  }) async {
    OnlineModelCatalogException? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http.get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': _userAgent,
          },
        ).timeout(const Duration(seconds: 12));

        final statusCode = response.statusCode;
        if (statusCode >= 200 && statusCode < 300) {
          return response;
        }

        if (statusCode == 429) {
          lastError = OnlineModelCatalogException(
            '$actionLabel failed (HTTP 429).',
            code: 'http_429',
            statusCode: statusCode,
          );
          if (attempt < 3) {
            await Future.delayed(
                _retryDelay(response.headers['retry-after'], attempt));
            continue;
          }
          throw lastError;
        }

        if (_isRetriableStatus(statusCode) && attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }

        throw OnlineModelCatalogException(
          '$actionLabel failed (HTTP $statusCode).',
          code: 'http_other',
          statusCode: statusCode,
        );
      } on TimeoutException {
        lastError = const OnlineModelCatalogException(
          'Online model search timed out.',
          code: 'timeout',
        );
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
      } catch (error) {
        if (error is OnlineModelCatalogException) {
          rethrow;
        }
        lastError = OnlineModelCatalogException(
          '$actionLabel failed: $error',
          code: 'network',
        );
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
      }
    }

    throw lastError ??
        OnlineModelCatalogException(
          '$actionLabel failed.',
          code: 'unknown',
        );
  }

  static bool _isRetriableStatus(int statusCode) {
    return const <int>{408, 425, 500, 502, 503, 504}.contains(statusCode);
  }

  static Duration _retryDelay(String? retryAfterHeader, int attempt) {
    final retryAfterSeconds = int.tryParse((retryAfterHeader ?? '').trim());
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      return Duration(seconds: retryAfterSeconds.clamp(1, 30));
    }
    return Duration(seconds: (attempt * 2).clamp(2, 8));
  }

  static String _authorFromRepoId(String repoId) {
    final separator = repoId.indexOf('/');
    if (separator <= 0) {
      return '';
    }
    return repoId.substring(0, separator);
  }

  static int _variantRank(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('q4_k_m')) {
      return 0;
    }
    if (lower.contains('q4_0')) {
      return 1;
    }
    if (lower.contains('q5_k_m')) {
      return 2;
    }
    if (lower.contains('q5_0')) {
      return 3;
    }
    if (lower.contains('q6_k')) {
      return 4;
    }
    if (lower.contains('q8_0')) {
      return 5;
    }
    if (lower.contains('fp16')) {
      return 90;
    }
    return 20;
  }
}

class _SearchCacheEntry {
  const _SearchCacheEntry({
    required this.fetchedAt,
    required this.results,
  });

  final DateTime fetchedAt;
  final List<OnlineModelCatalogSearchResult> results;
}

class _VariantCacheEntry {
  const _VariantCacheEntry({
    required this.fetchedAt,
    required this.variants,
  });

  final DateTime fetchedAt;
  final List<OnlineModelCatalogVariant> variants;
}
