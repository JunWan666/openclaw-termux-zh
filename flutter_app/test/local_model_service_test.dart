import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/local_model_service.dart';

void main() {
  group('LocalModelService.sanitizeModelFileName', () {
    test('appends gguf extension when missing', () {
      expect(
        LocalModelService.sanitizeModelFileName('qwen-3b-q4_k_m'),
        'qwen-3b-q4_k_m.gguf',
      );
    });

    test('removes invalid filesystem characters', () {
      expect(
        LocalModelService.sanitizeModelFileName('qwen:/3b?*.gguf'),
        'qwen-3b-.gguf',
      );
    });

    test('suggests file name from URL with query string', () {
      expect(
        LocalModelService.suggestFileNameFromUrl(
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
        ),
        'qwen2.5-3b-instruct-q4_k_m.gguf',
      );
    });
  });

  group('LocalModelService.buildDownloadSourceUrls', () {
    test('adds fallback mirror for Hugging Face URLs', () {
      expect(
        LocalModelService.buildDownloadSourceUrls(
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
        ),
        [
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
          'https://hf-mirror.com/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
        ],
      );
    });

    test('keeps a single source for non-Hugging Face URLs', () {
      expect(
        LocalModelService.buildDownloadSourceUrls(
          'https://example.com/models/demo.gguf',
        ),
        ['https://example.com/models/demo.gguf'],
      );
    });
  });

  group('LocalModelService.buildRecommendations', () {
    test('returns low-memory guidance for small devices', () {
      final recommendations = LocalModelService.buildRecommendations(
        const LocalModelHardwareProfile(
          cpuCount: 4,
          memoryKiB: 4 * 1024 * 1024,
          freeStorageKiB: 32 * 1024 * 1024,
        ),
      );

      expect(recommendations.first.title, contains('Low-memory'));
    });

    test('returns high-memory guidance for larger devices', () {
      final recommendations = LocalModelService.buildRecommendations(
        const LocalModelHardwareProfile(
          cpuCount: 8,
          memoryKiB: 12 * 1024 * 1024,
          freeStorageKiB: 64 * 1024 * 1024,
        ),
      );

      expect(recommendations.first.title, contains('High-memory'));
    });
  });

  group('LocalModelService.searchCatalog', () {
    test('returns coding entries for coding query', () {
      final results = LocalModelService.searchCatalog(query: '代码');

      expect(
        results.any((entry) => entry.id == 'qwen2.5-coder-3b-q4km'),
        isTrue,
      );
    });

    test('prefers smaller models on low-memory devices', () {
      final results = LocalModelService.searchCatalog(
        hardware: const LocalModelHardwareProfile(
          cpuCount: 4,
          memoryKiB: 4 * 1024 * 1024,
          freeStorageKiB: 32 * 1024 * 1024,
        ),
      );

      expect(results.first.id, 'qwen2-0.5b-q4km');
    });
  });
  group('LocalModelService.recommendServerTuning', () {
    test('uses conservative tuning on smaller devices', () {
      final tuning = LocalModelService.recommendServerTuning(
        hardware: const LocalModelHardwareProfile(
          cpuCount: 4,
          memoryKiB: 4 * 1024 * 1024,
          freeStorageKiB: 32 * 1024 * 1024,
        ),
        modelSizeBytes: 400 * 1024 * 1024,
        contextSize: 4096,
      );

      expect(tuning.threads, 4);
      expect(tuning.threadsBatch, 4);
      expect(tuning.batchSize, 384);
      expect(tuning.ubatchSize, 256);
    });

    test('uses more aggressive tuning on larger devices', () {
      final tuning = LocalModelService.recommendServerTuning(
        hardware: const LocalModelHardwareProfile(
          cpuCount: 8,
          memoryKiB: 12 * 1024 * 1024,
          freeStorageKiB: 64 * 1024 * 1024,
        ),
        modelSizeBytes: 1200 * 1024 * 1024,
        contextSize: 4096,
      );

      expect(tuning.threads, 8);
      expect(tuning.threadsBatch, 8);
      expect(tuning.batchSize, 2048);
      expect(tuning.ubatchSize, 1536);
    });

    test('reduces batch size when context is large', () {
      final tuning = LocalModelService.recommendServerTuning(
        hardware: const LocalModelHardwareProfile(
          cpuCount: 8,
          memoryKiB: 12 * 1024 * 1024,
          freeStorageKiB: 64 * 1024 * 1024,
        ),
        modelSizeBytes: 1200 * 1024 * 1024,
        contextSize: 12288,
      );

      expect(tuning.batchSize, 1152);
      expect(tuning.ubatchSize, 1152);
    });
  });
}
